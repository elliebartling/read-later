import UIKit

/// Fetches a site's favicon so `FaviconTile` (BR1) has something to tile.
///
/// Deliberately thin: the bytes go through `ArticleImageCache`, which already
/// owns the disk `URLCache`, the ImageIO downsample and the in-flight
/// coalescing, so this only adds the per-host candidate walk and a *negative*
/// cache — without one, every scroll pass would re-issue three 404s for the
/// long tail of sites that ship no icon.
///
/// No third-party favicon proxy: the app never tells anyone else which sites
/// the user reads. The only requests are to the site itself, which the user
/// already visited to save the article.
final class FaviconStore {
    static let shared = FaviconStore()

    private let lock = NSLock()
    private var resolved: [String: UIImage] = [:]
    private var failed: Set<String> = []
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {}

    /// The icon for `host`, or nil when the site has none we can find. Repeat
    /// misses are answered from the negative cache, never re-fetched.
    func icon(for host: String) async -> UIImage? {
        let key = Self.normalisedHost(host)
        guard !key.isEmpty else { return nil }

        lock.lock()
        if let cached = resolved[key] {
            lock.unlock()
            return cached
        }
        if failed.contains(key) {
            lock.unlock()
            return nil
        }
        if let existing = inFlight[key] {
            lock.unlock()
            return await existing.value
        }
        let task = Task<UIImage?, Never> { [weak self] in
            let image = await Self.fetch(host: key)
            self?.finish(key: key, image: image)
            return image
        }
        inFlight[key] = task
        lock.unlock()
        return await task.value
    }

    private func finish(key: String, image: UIImage?) {
        lock.lock()
        inFlight[key] = nil
        if let image {
            resolved[key] = image
        } else {
            failed.insert(key)
        }
        lock.unlock()
    }

    private static func fetch(host: String) async -> UIImage? {
        for url in candidateURLs(host: host) {
            if let image = await ArticleImageCache.shared.image(
                for: url,
                targetWidth: Metric.faviconMark
            ) {
                return image
            }
        }
        return nil
    }

    // MARK: - Pure helpers (unit-tested)

    /// Lowercased, `www.`-stripped, trailing-dot-free host. Empty for anything
    /// that isn't a usable host, which short-circuits the fetch.
    static func normalisedHost(_ host: String) -> String {
        var value = host.trimmingCharacters(in: .whitespaces).lowercased()
        while value.hasSuffix(".") { value.removeLast() }
        if value.hasPrefix("www.") { value.removeFirst(4) }
        return value.contains(".") ? value : ""
    }

    /// Well-known icon paths, best fidelity first. Apple-touch icons are tried
    /// ahead of `favicon.ico` because they are square, ≥120pt and never the
    /// 16px bitmap that turns into mush on a 20pt mark.
    static func candidateURLs(host: String) -> [URL] {
        let key = normalisedHost(host)
        guard !key.isEmpty else { return [] }
        return [
            "apple-touch-icon.png",
            "apple-touch-icon-precomposed.png",
            "favicon.ico",
        ].compactMap { URL(string: "https://\(key)/\($0)") }
    }
}
