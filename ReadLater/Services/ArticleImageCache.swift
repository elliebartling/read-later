import ImageIO
import UIKit

/// Downloads and downsamples article images for the block reader.
///
/// Two layers of caching sit in front of network:
/// - a private `URLSession` with a dedicated 50 MB disk `URLCache` (main app
///   only — no App Group; extensions never render blocks), and
/// - an in-memory `NSCache` of already-decoded, downsampled `UIImage`s keyed by
///   URL + target width.
///
/// Images are decoded straight to a thumbnail via ImageIO
/// (`CGImageSourceCreateThumbnailAtIndex`) so a full-resolution bitmap is never
/// held in memory — only the pixels the layout will actually show.
final class ArticleImageCache {
    static let shared = ArticleImageCache()

    private let session: URLSession
    private let decodedCache = NSCache<NSString, UIImage>()

    /// Guards `inFlight` so concurrent callers for the same key share one Task.
    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        let cachesDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ArticleImageCache", isDirectory: true)
        let urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024, // 8 MB
            diskCapacity: 50 * 1024 * 1024, // 50 MB
            directory: cachesDir
        )
        let config = URLSessionConfiguration.default
        config.urlCache = urlCache
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)

        decodedCache.totalCostLimit = 48 * 1024 * 1024 // ~48 MB of decoded pixels
    }

    /// Returns a downsampled image sized for `targetWidth` points, or nil on
    /// failure. Concurrent calls for the same key are coalesced into one load.
    func image(for url: URL, targetWidth: CGFloat) async -> UIImage? {
        let key = Self.cacheKey(url: url, targetWidth: targetWidth)
        if let cached = decodedCache.object(forKey: key as NSString) {
            return cached
        }

        let maxPixel = Self.maxPixelSize(
            targetWidth: targetWidth,
            scale: Self.displayScale
        )
        let task = existingOrNewTask(for: key, url: url, maxPixelSize: maxPixel)
        return await task.value
    }

    /// Returns a near-full-resolution decode for the full-screen zoom viewer,
    /// capped at `fullImageMaxPixel` on the longest edge (crisp under pinch-zoom
    /// while keeping memory bounded). Shares the same disk/URL cache and
    /// in-flight coalescing as thumbnail loads, under its own decoded-cache key.
    func fullImage(for url: URL) async -> UIImage? {
        let key = "\(url.absoluteString)#full"
        if let cached = decodedCache.object(forKey: key as NSString) {
            return cached
        }

        let task = existingOrNewTask(for: key, url: url, maxPixelSize: Self.fullImageMaxPixel)
        return await task.value
    }

    /// Under the lock: reuse an in-flight Task for `key` or start a new one.
    private func existingOrNewTask(
        for key: String,
        url: URL,
        maxPixelSize maxPixel: Int
    ) -> Task<UIImage?, Never> {
        lock.lock()
        defer { lock.unlock() }

        if let existing = inFlight[key] {
            return existing
        }

        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            let image = await self.load(url: url, maxPixelSize: maxPixel)
            if let image {
                self.decodedCache.setObject(
                    image,
                    forKey: key as NSString,
                    cost: Self.cost(of: image)
                )
            }
            self.removeInFlight(key)
            return image
        }
        inFlight[key] = task
        return task
    }

    /// Synchronous so it is safe to call from the load Task's async body
    /// (`NSLock.lock()` is unavailable directly from async contexts).
    private func removeInFlight(_ key: String) {
        lock.lock()
        inFlight[key] = nil
        lock.unlock()
    }

    private func load(url: URL, maxPixelSize: Int) async -> UIImage? {
        do {
            let (data, _) = try await session.data(from: url)
            return Self.downsample(data: data, maxPixelSize: maxPixelSize)
        } catch {
            return nil
        }
    }

    // MARK: - Pure helpers (unit-tested)

    /// Longest-edge pixel cap for `fullImage` decodes. 4096 px keeps zoomed
    /// article images crisp without holding an unbounded full-res bitmap.
    static let fullImageMaxPixel = 4096

    /// Cache key uniquely identifying a decode of `url` at a given point width.
    /// Truncates width to an Int so near-identical layout widths still hit.
    static func cacheKey(url: URL, targetWidth: CGFloat) -> String {
        "\(url.absoluteString)#\(Int(targetWidth))"
    }

    /// Max thumbnail edge in pixels for a `targetWidth`-point image at `scale`.
    /// Falls back to 1x for a non-positive scale and never returns below 1
    /// (ImageIO treats a 0 max pixel size as "no limit").
    static func maxPixelSize(targetWidth: CGFloat, scale: CGFloat) -> Int {
        let effectiveScale = scale > 0 ? scale : 1
        let pixels = (targetWidth * effectiveScale).rounded()
        return max(1, Int(pixels))
    }

    // MARK: - Private helpers

    /// Screen scale captured once, off the main actor. A 3x fallback keeps
    /// Retina devices crisp if the trait collection isn't populated yet.
    private static let displayScale: CGFloat = {
        let scale = UITraitCollection.current.displayScale
        return scale > 0 ? scale : 3.0
    }()

    private static func downsample(data: Data, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbOptions as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
