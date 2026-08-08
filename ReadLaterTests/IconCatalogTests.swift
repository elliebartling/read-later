import UIKit
import XCTest
@testable import ReadLater

/// §5 / I13 — the Phosphor substrate's tripwire.
///
/// `Image(_ name: String)` fails *silently*: a typo'd or unbundled asset draws
/// nothing at all, with no compiler error and no runtime log. That is exactly
/// how the swap to Phosphor could rot — a renamed asset, a catalog dropped from
/// `project.yml`, or a generator re-run that changes a filename. These tests
/// make every one of those a red build.
final class IconCatalogTests: XCTestCase {
    private static let allIcons = Icon.allCases

    /// Every icon the app can name actually resolves out of the bundle.
    func testEveryIconResolvesFromTheAssetCatalog() {
        for icon in Self.allIcons {
            XCTAssertNotNil(
                UIImage(named: icon.rawValue),
                "\(icon) (\(icon.rawValue)) is missing from PhosphorSymbols.xcassets — re-run tools/phosphor_symbols.py"
            )
        }
    }

    /// **§5.4 criterion 3.** They must be *symbols*, not plain images. A plain
    /// image loses Dynamic Type, `.imageScale`, baseline alignment in a label
    /// run and `symbolRenderingMode` — the whole reason we compile SF Symbol
    /// templates instead of dropping the SVGs in as artwork.
    func testEveryIconIsASymbolImage() {
        for icon in Self.allIcons {
            guard let image = UIImage(named: icon.rawValue) else { continue }
            XCTAssertTrue(
                image.isSymbolImage,
                "\(icon) compiled as a plain image, not a symbol — its .symbolset template is malformed"
            )
        }
    }

    /// **I2.** A symbol has to answer to the point size `uiGlyph` gives it;
    /// if it did not, every glyph would render at one fixed size and Dynamic
    /// Type would be dead on arrival.
    func testIconsScaleWithTheirFont() {
        for icon in Self.allIcons {
            guard let image = UIImage(named: icon.rawValue) else { continue }
            let small = image.withConfiguration(UIImage.SymbolConfiguration(pointSize: 12))
            let large = image.withConfiguration(UIImage.SymbolConfiguration(pointSize: 48))
            XCTAssertGreaterThan(
                large.size.height, small.size.height,
                "\(icon) does not respond to point size"
            )
        }
    }

    /// The enum is the only surface (I13), so nothing may name an asset that
    /// is not a Phosphor one — including by accidentally taking Swift's
    /// implicit raw value (`case trash` alone would be `"trash"`, the old SF
    /// Symbol, which still resolves and would look like it worked).
    func testEveryIconNamesAPhosphorAsset() {
        XCTAssertFalse(Self.allIcons.isEmpty)
        XCTAssertEqual(
            Set(Self.allIcons.map(\.rawValue)).count, Self.allIcons.count,
            "two cases share a raw value"
        )
        for icon in Self.allIcons {
            XCTAssertTrue(
                icon.rawValue.hasPrefix("ph."),
                "\(icon) does not name a Phosphor asset"
            )
        }
    }
}
