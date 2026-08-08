import Foundation

/// What a saved URL points at when it is *not* a readable web page.
///
/// Lives in `Shared/` rather than beside its classifier (`MediaLink`, in
/// `ReadLater/Services/Parsing/`) because `Article.mediaKindRaw` persists its
/// `rawValue`, and `Shared/` is the only sources root every target compiles.
///
/// The cases are therefore a **stored vocabulary**: renaming one orphans
/// existing records. Adding one is safe — an unrecognised string decodes to
/// nil, which reads as "an ordinary article".
enum MediaKind: String, Codable, Sendable, CaseIterable {
    /// A single still image or animated GIF (`i.redd.it/abc.jpeg`).
    case image
    /// A video asset, or a video host page we don't play in-app
    /// (`v.redd.it/abc`). Rendered as a poster frame plus a link out.
    case video
    /// A multi-image album whose members we can't enumerate without an API
    /// (`reddit.com/gallery/abc`) — we hold the cover only.
    case gallery
}
