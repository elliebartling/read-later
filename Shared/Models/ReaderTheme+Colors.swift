#if canImport(UIKit)
import UIKit

// The eight reader papers and their inks.
//
// **§4.1 T1/T2 still govern: this catalogue is finished work and nobody
// "improves" it.** What changed here, and only here, is the *hue of the four
// papers that were never meant to have one* — handed over from the build-44
// defect sweep (PR #82 §6) and carried out under §2.1.
//
// The sweep sampled the rendered app and found every neutral in the chrome
// already on the warm 72° spine — and then found that the reader's own
// catalogue was the one place in the codebase where cool and pure-neutral greys
// still lived. Ellen's standing complaint that the app "can't pick between warm
// gray and neutral" survived a clean chrome for exactly that reason: you leave a
// warm charcoal app and land on a page that is either pure grey or Apple's cool
// system grey, and the seam is at the moment you start reading.
//
// So the four **neutral** papers move onto the same spine as the app, at their
// existing lightness (every channel moves by ≤3/255, so no contrast figure
// changes and no paper changes place in the ramp):
//
// | Paper | Was | Now | Was |
// |---|---|---|---|
// | `light` | `#FCFCFC` | `#FCFAF9` | pure white |
// | `dark` | `#0F0F0F` | `#110F0C` | pure neutral |
// | `darkGray` | `#3A3A3C` | `#3C3A37` | Apple system grey, B > R |
// | `mediumGray` | `#D1D1D6` | `#D3D1CE` | Apple system grey, B > R |
//
// Each keeps the ramp's own shape — `R − B = 5` on the darks, 3 at the top,
// which is `Surface.ground`'s exact relationship in both schemes — so they read
// as charcoal rather than slate, and stay far under the chroma 0.006 ceiling
// that would make them parchment (N4). Their inks move with them, mirroring
// `Ink.primary`'s warm offset, because a warm page carrying a cool ink is the
// same defect one layer down.
//
// **The four papers with a deliberate hue are untouched**: `sepia`, `paper`,
// `slate` (navy) and `forest` (green) are choices a reader makes on purpose, and
// §4.1 protects them. The sweep's companion suggestion — that Slate is the
// default dark paper and should be swapped — was checked and is **not the
// case**: `AppSettings.readerDarkThemeRaw` defaults to `.dark` and
// `migrateLegacyThemeIfNeeded` lands on `.light`/`.dark`, so no reader has ever
// opened onto navy unless they picked it.

extension ReaderTheme {
    var foreground: UIColor {
        switch self {
        // Warm neutrals — ink offsets mirror `Ink.primary` (§2.1).
        case .light:      return UIColor(red: 30 / 255, green: 27 / 255, blue: 23 / 255, alpha: 1)
        case .dark:       return UIColor(red: 237 / 255, green: 235 / 255, blue: 232 / 255, alpha: 1)
        case .darkGray:   return UIColor(red: 244 / 255, green: 242 / 255, blue: 239 / 255, alpha: 1)
        case .mediumGray: return UIColor(red: 30 / 255, green: 28 / 255, blue: 25 / 255, alpha: 1)
        // Deliberate hues — untouched (§4.1).
        case .sepia:      return UIColor(red: 0.35, green: 0.24, blue: 0.14, alpha: 1)
        case .slate:      return UIColor(red: 0.85, green: 0.89, blue: 0.95, alpha: 1)
        case .paper:      return UIColor(red: 0.17, green: 0.14, blue: 0.11, alpha: 1)
        case .forest:     return UIColor(red: 0.88, green: 0.94, blue: 0.87, alpha: 1)
        }
    }

    var background: UIColor {
        switch self {
        // Warm neutrals — on the 72° spine, at their original lightness.
        case .light:      return UIColor(red: 252 / 255, green: 250 / 255, blue: 249 / 255, alpha: 1)
        case .dark:       return UIColor(red: 17 / 255, green: 15 / 255, blue: 12 / 255, alpha: 1)
        case .darkGray:   return UIColor(red: 60 / 255, green: 58 / 255, blue: 55 / 255, alpha: 1)
        case .mediumGray: return UIColor(red: 211 / 255, green: 209 / 255, blue: 206 / 255, alpha: 1)
        // Deliberate hues — untouched (§4.1).
        case .sepia:      return UIColor(red: 0.98, green: 0.94, blue: 0.85, alpha: 1)
        case .slate:      return UIColor(red: 0.118, green: 0.161, blue: 0.231, alpha: 1)
        case .paper:      return UIColor(red: 0.961, green: 0.941, blue: 0.909, alpha: 1)
        case .forest:     return UIColor(red: 0.102, green: 0.180, blue: 0.110, alpha: 1)
        }
    }

    /// The papers that carry no hue on purpose, and therefore must sit on the
    /// app's warm spine rather than on a grey of their own. A test pins this.
    static let neutralCases: [ReaderTheme] = [.light, .dark, .darkGray, .mediumGray]

    /// The papers whose hue is the point. `sepia` and `paper` are warm by
    /// intent, `slate` is navy, `forest` is green — none is on the spine and
    /// none may be "corrected" onto it (§4.1).
    static let huedCases: [ReaderTheme] = [.sepia, .paper, .slate, .forest]
}
#endif
