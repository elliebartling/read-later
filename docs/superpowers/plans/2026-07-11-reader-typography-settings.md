# Reader Typography Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the reader richer, accessible typography — 9 theme presets, named column widths, independent line/paragraph-spacing sliders, a size slider, an expanded system-font picker, and theme-aware (opaque) highlight compositing — by extending the existing `AppSettings` + `TypographyControls` + `HighlightableTextView` stack.

**Architecture:** No WebKit rewrite. New prefs are inline-default fields on the local-only `AppSettings` SwiftData row. `HighlightableTextView` (a `UITextView` `UIViewRepresentable`) stays the single attributed-string render path; it gains spacing + width inputs and composited highlight colors. Theme color helpers move next to the `ReaderTheme` enum so Settings and the reader share one source. Highlight UTF-16 anchoring is untouched.

**Tech Stack:** Swift 6 / SwiftUI / SwiftData / UIKit (`UITextView`, `NSParagraphStyle`, `UIColor`); XcodeGen (`project.yml`); XCTest. Build/run via XcodeBuildMCP (project `ReadLater.xcodeproj`, scheme `ReadLater`, sim `iPhone 17`).

**Scope note:** This plan covers everything that needs **no external assets**. **Bundled OFL fonts** (Literata, Source Serif 4, Merriweather, Atkinson Hyperlegible Next, Lexend, OpenDyslexic, Geist, Inter — plus `UIAppFonts` registration and license files) are deferred to a **separate follow-up plan** because they require downloading font files (a permissioned action). This plan expands `ReaderFont` with **system-resolvable faces only**; the follow-up adds the bundled families and the Accessibility group.

**Preserve:** `TypographyControls` already has a **"Read Aloud"** section (provider + voice) added by the audio-player work now on `main`. Keep it — this plan adds sections around it.

---

## File Structure

- `Shared/Models/AppSettings.swift` — add `readerLineSpacing`, `readerParagraphSpacing`, `readerWidthRaw` fields + `readerWidth` accessor; expand `ReaderTheme` cases; add `ReaderWidth` enum.
- `Shared/Models/ReaderTheme+Colors.swift` — **new.** `ReaderTheme.foreground` / `.background` (UIColor) for all 9 themes + `isDarkBackground(for:)`. Moved out of `HighlightableTextView`.
- `Shared/Models/HighlightColor.swift` — add opaque `uiColor(on:darkBackground:)` theme-aware compositing.
- `ReadLater/UI/ReaderFont.swift` — add system faces (Charter) + `group` for picker sections.
- `ReadLater/Features/Reader/HighlightableTextView.swift` — consume spacing + width; composited highlight + spoken-range paint; extend `renderSignature`; remove the moved `ReaderTheme` color extension.
- `ReadLater/Features/Reader/ReaderView.swift` — pass the new settings to `HighlightableTextView`.
- `ReadLater/Features/Reader/TypographyControls.swift` — full UI (theme grid, grouped font picker, three sliders, width), keeping the Read Aloud section.
- `ReadLater/Features/Settings/SettingsView.swift` — swap the size Stepper for a slider; leave family/spacing/width reader-only.
- `ReadLaterTests/ReaderTypographyTests.swift` — **new.** Model fallbacks, width→inset, theme colors, highlight compositing, font fallback.

---

## Task 1: Data model — spacing/width fields + `ReaderWidth`

**Files:**
- Modify: `Shared/Models/AppSettings.swift`
- Test: `ReadLaterTests/ReaderTypographyTests.swift` (new)

- [ ] **Step 1: Write failing tests**

Create `ReadLaterTests/ReaderTypographyTests.swift`:

```swift
import XCTest
@testable import ReadLater

final class ReaderTypographyTests: XCTestCase {

    // MARK: ReaderWidth

    func testReaderWidthRawFallback() {
        XCTAssertEqual(ReaderWidth(rawValue: "bogus") ?? .medium, .medium)
    }

    func testReaderWidthInsetsOrdering() {
        // Narrower column = larger horizontal inset.
        XCTAssertGreaterThan(ReaderWidth.narrow.horizontalInset, ReaderWidth.medium.horizontalInset)
        XCTAssertGreaterThan(ReaderWidth.medium.horizontalInset, ReaderWidth.wide.horizontalInset)
        XCTAssertGreaterThan(ReaderWidth.wide.horizontalInset, ReaderWidth.full.horizontalInset)
    }

    func testAppSettingsSpacingDefaults() {
        let s = AppSettings()
        XCTAssertEqual(s.readerLineSpacing, 6, accuracy: 0.001)
        XCTAssertEqual(s.readerParagraphSpacing, 12, accuracy: 0.001)
        XCTAssertEqual(s.readerWidth, .medium)
    }

    func testAppSettingsWidthAccessorRoundTrips() {
        let s = AppSettings()
        s.readerWidth = .wide
        XCTAssertEqual(s.readerWidthRaw, "wide")
        XCTAssertEqual(s.readerWidth, .wide)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run (XcodeBuildMCP): `test_sim`
Expected: FAIL — `ReaderWidth` and the new `AppSettings` members don't exist yet (compile error is an acceptable "fail").

- [ ] **Step 3: Add fields + accessor to `AppSettings`**

In `Shared/Models/AppSettings.swift`, after the `readerFontRaw` line (currently line 27) add:

```swift
    /// NSParagraphStyle.lineSpacing for reader body text.
    var readerLineSpacing: Double = 6
    /// NSParagraphStyle.paragraphSpacing between reader paragraphs.
    var readerParagraphSpacing: Double = 12
    /// Raw value of ReaderWidth (column measure).
    var readerWidthRaw: String = ReaderWidth.medium.rawValue
```

After the `readerTheme` computed property (currently ends line 37) add:

```swift
    var readerWidth: ReaderWidth {
        get { ReaderWidth(rawValue: readerWidthRaw) ?? .medium }
        set { readerWidthRaw = newValue.rawValue }
    }
```

- [ ] **Step 4: Add the `ReaderWidth` enum**

At the end of `Shared/Models/AppSettings.swift` (after the `ReaderTheme` enum) add:

```swift
enum ReaderWidth: String, Codable, CaseIterable, Identifiable {
    case narrow, medium, wide, full

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    /// Left/right `textContainerInset` in points. Narrower column = larger inset.
    var horizontalInset: CGFloat {
        switch self {
        case .narrow: return 48
        case .medium: return 32
        case .wide:   return 20
        case .full:   return 12
        }
    }
}
```

Add `import CoreGraphics` at the top of the file if `CGFloat` does not resolve (Foundation usually re-exports it on iOS; add only if the build complains).

- [ ] **Step 5: Run tests to verify they pass**

Run: `test_sim`
Expected: PASS for the four Task-1 tests.

- [ ] **Step 6: Commit**

```bash
git add Shared/Models/AppSettings.swift ReadLaterTests/ReaderTypographyTests.swift
git commit -m "Add reader spacing/width settings and ReaderWidth enum"
```

---

## Task 2: Expand `ReaderTheme` + move color helpers

**Files:**
- Create: `Shared/Models/ReaderTheme+Colors.swift`
- Modify: `Shared/Models/AppSettings.swift` (enum cases)
- Modify: `ReadLater/Features/Reader/HighlightableTextView.swift` (remove moved extension)
- Test: `ReadLaterTests/ReaderTypographyTests.swift`

- [ ] **Step 1: Write failing tests**

Append to `ReaderTypographyTests.swift`:

```swift
extension ReaderTypographyTests {
    func testReaderThemeRawFallback() {
        XCTAssertEqual(ReaderTheme(rawValue: "bogus") ?? .system, .system)
    }

    func testAllThemesHaveOpaqueColors() {
        for theme in ReaderTheme.allCases {
            var alpha: CGFloat = 0
            theme.background.getRed(nil, green: nil, blue: nil, alpha: &alpha)
            XCTAssertEqual(alpha, 1, accuracy: 0.001, "\(theme) background must be opaque")
        }
    }

    func testExplicitThemeDarkness() {
        XCTAssertTrue(ReaderTheme.dark.isDarkBackground(for: nil))
        XCTAssertTrue(ReaderTheme.slate.isDarkBackground(for: nil))
        XCTAssertTrue(ReaderTheme.forest.isDarkBackground(for: nil))
        XCTAssertTrue(ReaderTheme.darkGray.isDarkBackground(for: nil))
        XCTAssertFalse(ReaderTheme.light.isDarkBackground(for: nil))
        XCTAssertFalse(ReaderTheme.sepia.isDarkBackground(for: nil))
        XCTAssertFalse(ReaderTheme.paper.isDarkBackground(for: nil))
        XCTAssertFalse(ReaderTheme.mediumGray.isDarkBackground(for: nil))
    }

    func testNewThemeCasesExist() {
        let raws = Set(ReaderTheme.allCases.map(\.rawValue))
        for expected in ["darkGray", "mediumGray", "slate", "paper", "forest"] {
            XCTAssertTrue(raws.contains(expected), "missing theme \(expected)")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `test_sim`
Expected: FAIL — new cases and `isDarkBackground(for:)` don't exist.

- [ ] **Step 3: Expand the enum cases**

In `Shared/Models/AppSettings.swift`, replace the `ReaderTheme` case line:

```swift
    case light, dark, sepia, system
```

with:

```swift
    case light, dark, sepia, system
    case darkGray, mediumGray, slate, paper, forest
```

Update `displayName` to read nicely for camelCase cases — replace the `displayName` line with:

```swift
    var displayName: String {
        switch self {
        case .darkGray:   return "Dark Gray"
        case .mediumGray: return "Medium Gray"
        default:          return rawValue.capitalized
        }
    }
```

- [ ] **Step 4: Create the colors file and remove the old extension**

Create `Shared/Models/ReaderTheme+Colors.swift`:

```swift
#if canImport(UIKit)
import UIKit

extension ReaderTheme {
    var foreground: UIColor {
        switch self {
        case .light:      return UIColor(red: 0.11, green: 0.10, blue: 0.10, alpha: 1)
        case .dark:       return UIColor(white: 0.92, alpha: 1)
        case .sepia:      return UIColor(red: 0.35, green: 0.24, blue: 0.14, alpha: 1)
        case .system:     return .label
        case .darkGray:   return UIColor(white: 0.95, alpha: 1)
        case .mediumGray: return UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        case .slate:      return UIColor(red: 0.85, green: 0.89, blue: 0.95, alpha: 1)
        case .paper:      return UIColor(red: 0.17, green: 0.14, blue: 0.11, alpha: 1)
        case .forest:     return UIColor(red: 0.88, green: 0.94, blue: 0.87, alpha: 1)
        }
    }

    var background: UIColor {
        switch self {
        case .light:      return UIColor(white: 0.99, alpha: 1)
        case .dark:       return UIColor(white: 0.06, alpha: 1)
        case .sepia:      return UIColor(red: 0.98, green: 0.94, blue: 0.85, alpha: 1)
        case .system:     return .systemBackground
        case .darkGray:   return UIColor(red: 0.227, green: 0.227, blue: 0.235, alpha: 1)
        case .mediumGray: return UIColor(red: 0.82, green: 0.82, blue: 0.839, alpha: 1)
        case .slate:      return UIColor(red: 0.118, green: 0.161, blue: 0.231, alpha: 1)
        case .paper:      return UIColor(red: 0.961, green: 0.941, blue: 0.909, alpha: 1)
        case .forest:     return UIColor(red: 0.102, green: 0.180, blue: 0.110, alpha: 1)
        }
    }

    /// Whether highlight/spoken paint should use the dark (screen) recipe.
    /// Explicit themes are known; `.system` follows the trait collection
    /// (defaults to light when no trait is available, e.g. in unit tests).
    func isDarkBackground(for traitCollection: UITraitCollection?) -> Bool {
        switch self {
        case .dark, .darkGray, .slate, .forest:
            return true
        case .light, .sepia, .paper, .mediumGray:
            return false
        case .system:
            return traitCollection?.userInterfaceStyle == .dark
        }
    }
}
#endif
```

In `ReadLater/Features/Reader/HighlightableTextView.swift`, **delete** the entire trailing `extension ReaderTheme { ... }` block (currently lines 405–422) — it now lives in the new file.

- [ ] **Step 5: Run tests to verify they pass**

Run: `test_sim`
Expected: PASS for the Task-2 tests; existing tests still green.

- [ ] **Step 6: Commit**

```bash
git add Shared/Models/AppSettings.swift Shared/Models/ReaderTheme+Colors.swift ReadLater/Features/Reader/HighlightableTextView.swift ReadLaterTests/ReaderTypographyTests.swift
git commit -m "Add 5 reader theme presets; move theme colors beside the enum"
```

> **XcodeGen note:** `Shared/**` is already globbed into both the app and test targets by `project.yml`, so the new file needs no manual target wiring. If a fresh file isn't picked up, run `xcodegen generate` before building.

---

## Task 3: Theme-aware highlight compositing

**Files:**
- Modify: `Shared/Models/HighlightColor.swift`
- Test: `ReadLaterTests/ReaderTypographyTests.swift`

- [ ] **Step 1: Write failing tests**

Append to `ReaderTypographyTests.swift`:

```swift
extension ReaderTypographyTests {
    private func luminance(_ c: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    func testCompositedHighlightsAreOpaque() {
        for color in HighlightColor.allCases {
            for dark in [true, false] {
                var a: CGFloat = 0
                color.uiColor(darkBackground: dark).getRed(nil, green: nil, blue: nil, alpha: &a)
                XCTAssertEqual(a, 1, accuracy: 0.001)
            }
        }
    }

    func testLightAndDarkRecipesDiffer() {
        for color in HighlightColor.allCases {
            XCTAssertNotEqual(color.uiColor(darkBackground: false),
                              color.uiColor(darkBackground: true))
        }
    }

    func testDarkRecipeIsLighterThanDarkPage() {
        // On a dark page the band must be brighter than the page to stay legible.
        let darkPage = ReaderTheme.dark.background
        for color in HighlightColor.allCases {
            XCTAssertGreaterThan(luminance(color.uiColor(darkBackground: true)),
                                 luminance(darkPage))
        }
    }

    func testLightRecipeStaysBelowWhite() {
        for color in HighlightColor.allCases {
            XCTAssertLessThan(luminance(color.uiColor(darkBackground: false)), 1.0)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `test_sim`
Expected: FAIL — `uiColor(darkBackground:)` not defined.

- [ ] **Step 3: Implement compositing**

In `Shared/Models/HighlightColor.swift`, inside the `#if canImport(UIKit)` block (after the existing `uiColor` property), add:

```swift
    /// RGB components of the identity marker color.
    private var rgb: (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch self {
        case .yellow: return (1.0, 0.93, 0.55)
        case .green:  return (0.72, 0.94, 0.72)
        case .blue:   return (0.68, 0.84, 1.0)
        case .pink:   return (1.0, 0.75, 0.85)
        }
    }

    /// Opaque highlight paint tuned to the page darkness.
    /// - Light pages: the marker multiplied onto near-white at 0.55 strength
    ///   (matches the old translucent look, but opaque so it composites cleanly
    ///   over sepia/paper too).
    /// - Dark pages: a screen-lifted mid band, brighter than the page so the
    ///   text underneath stays readable.
    func uiColor(darkBackground: Bool) -> UIColor {
        let (r, g, b) = rgb
        if darkBackground {
            let base: CGFloat = 0.16   // nominal dark page level
            func screen(_ m: CGFloat) -> CGFloat { 1 - (1 - base) * (1 - m * 0.55) }
            return UIColor(red: screen(r), green: screen(g), blue: screen(b), alpha: 1)
        } else {
            let page: CGFloat = 0.99   // nominal light page level
            func multiply(_ m: CGFloat) -> CGFloat { page * (0.45 + 0.55 * m) }
            return UIColor(red: multiply(r), green: multiply(g), blue: multiply(b), alpha: 1)
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `test_sim`
Expected: PASS for the Task-3 tests.

- [ ] **Step 5: Commit**

```bash
git add Shared/Models/HighlightColor.swift ReadLaterTests/ReaderTypographyTests.swift
git commit -m "Add opaque, page-aware highlight compositing"
```

---

## Task 4: Expand `ReaderFont` (system faces + groups)

**Files:**
- Modify: `ReadLater/UI/ReaderFont.swift`
- Test: `ReadLaterTests/ReaderTypographyTests.swift`

- [ ] **Step 1: Write failing tests**

Append to `ReaderTypographyTests.swift`:

```swift
extension ReaderTypographyTests {
    func testReaderFontRawFallback() {
        XCTAssertEqual(ReaderFont(rawValue: "Bogus") ?? .serif, .serif)
    }

    func testEveryFontResolvesToAFont() {
        for font in ReaderFont.allCases {
            XCTAssertGreaterThan(font.uiFont(size: 18).pointSize, 0)
        }
    }

    func testFontGroupsCoverAllCases() {
        for font in ReaderFont.allCases {
            XCTAssertFalse(font.group.title.isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `test_sim`
Expected: FAIL — `group` doesn't exist.

- [ ] **Step 3: Add Charter case + groups**

Replace the body of `ReadLater/UI/ReaderFont.swift` with:

```swift
import UIKit

/// Reader typefaces that resolve on iOS without bundled files. "New York" and
/// "San Francisco" are NOT name-addressable — UIFont(name:) returns nil — so
/// the system designs go through UIFontDescriptor.withDesign instead.
///
/// Bundled OFL faces (Literata, Atkinson Hyperlegible, etc.) are added in a
/// follow-up plan; this enum stays system-only.
enum ReaderFont: String, CaseIterable, Identifiable {
    case serif = "Serif"            // system serif (New York)
    case charter = "Charter"        // bundled with iOS
    case georgia = "Georgia"
    case palatino = "Palatino"
    case iowan = "Iowan Old Style"
    case sansSerif = "Sans Serif"   // system (San Francisco)

    var id: String { rawValue }
    var displayName: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case reading = "Reading"
        case sans = "Sans"
        var id: String { rawValue }
        var title: String { rawValue }
    }

    var group: Group {
        switch self {
        case .sansSerif: return .sans
        default:         return .reading
        }
    }

    func uiFont(size: CGFloat) -> UIFont {
        switch self {
        case .serif:
            let base = UIFont.systemFont(ofSize: size)
            if let descriptor = base.fontDescriptor.withDesign(.serif) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return base
        case .sansSerif:
            return .systemFont(ofSize: size)
        case .charter, .georgia, .palatino, .iowan:
            return UIFont(name: rawValue, size: size) ?? .systemFont(ofSize: size)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `test_sim`
Expected: PASS for the Task-4 tests.

- [ ] **Step 5: Commit**

```bash
git add ReadLater/UI/ReaderFont.swift ReadLaterTests/ReaderTypographyTests.swift
git commit -m "Add Charter face and picker groups to ReaderFont"
```

---

## Task 5: Apply spacing, width, and composited highlights in the render path

**Files:**
- Modify: `ReadLater/Features/Reader/HighlightableTextView.swift`
- Modify: `ReadLater/Features/Reader/ReaderView.swift`

No unit test (UIKit render wiring); verified by build + on-device check in Task 7's verification.

- [ ] **Step 1: Add inputs to `HighlightableTextView`**

In `HighlightableTextView.swift`, after the `fontRaw` stored property (currently line 42) add:

```swift
    let lineSpacing: CGFloat
    let paragraphSpacing: CGFloat
    let width: ReaderWidth
```

- [ ] **Step 2: Extend `renderSignature`**

Replace the `renderSignature()` return (currently line 128) with:

```swift
        return "\(text.utf16.count)|\(theme.rawValue)|\(fontSize)|\(fontRaw)|\(lineSpacing)|\(paragraphSpacing)|\(width.rawValue)|\(highlightSig)|\(spoken)"
```

- [ ] **Step 3: Use spacing + composited paint in `render()`**

In `render()`, replace the hardcoded paragraph style lines:

```swift
        paragraphStyle.lineSpacing = 6
        paragraphStyle.paragraphSpacing = 12
```

with:

```swift
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = paragraphSpacing
```

Compute page darkness once at the top of `render()` (first line of the method):

```swift
        let darkBackground = theme.isDarkBackground(for: UITraitCollection.current)
```

Replace the highlight paint line:

```swift
                str.addAttribute(.backgroundColor, value: h.color.uiColor.withAlphaComponent(0.55), range: nsRange)
```

with:

```swift
                str.addAttribute(.backgroundColor, value: h.color.uiColor(darkBackground: darkBackground), range: nsRange)
```

Replace the spoken-range paint line:

```swift
            str.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.15), range: range)
```

with:

```swift
            let spokenTint: UIColor = darkBackground
                ? UIColor(white: 1, alpha: 0.14)
                : UIColor.systemYellow.withAlphaComponent(0.16)
            str.addAttribute(.backgroundColor, value: spokenTint, range: range)
```

- [ ] **Step 4: Drive `textContainerInset` from width**

In `makeUIView`, replace the fixed inset line:

```swift
        tv.textContainerInset = UIEdgeInsets(top: 24, left: 20, bottom: 40, right: 20)
```

with:

```swift
        tv.textContainerInset = Self.inset(for: width)
```

In `updateUIView`, right after `context.coordinator.parent = self` (currently line 90), add:

```swift
        let desiredInset = Self.inset(for: width)
        if tv.textContainerInset != desiredInset {
            tv.textContainerInset = desiredInset
        }
```

Add this helper to the struct (place it just above `renderSignature()`):

```swift
    private static func inset(for width: ReaderWidth) -> UIEdgeInsets {
        UIEdgeInsets(top: 24, left: width.horizontalInset, bottom: 40, right: width.horizontalInset)
    }
```

- [ ] **Step 5: Pass new settings from `ReaderView`**

In `ReadLater/Features/Reader/ReaderView.swift`, in the `HighlightableTextView(...)` call (currently around lines 185–212), after the `fontRaw: settings.readerFontRaw,` argument add:

```swift
                lineSpacing: CGFloat(settings.readerLineSpacing),
                paragraphSpacing: CGFloat(settings.readerParagraphSpacing),
                width: settings.readerWidth,
```

- [ ] **Step 6: Build and verify it compiles**

Run: `build_sim`
Expected: SUCCEEDED, no errors.

- [ ] **Step 7: Commit**

```bash
git add ReadLater/Features/Reader/HighlightableTextView.swift ReadLater/Features/Reader/ReaderView.swift
git commit -m "Apply reader spacing, width insets, and page-aware highlights"
```

---

## Task 6: Expand the Typography sheet UI

**Files:**
- Modify: `ReadLater/Features/Reader/TypographyControls.swift`

No unit test (SwiftUI); verified by build + on-device check in Task 7.

- [ ] **Step 1: Replace the sheet body, keeping the Read Aloud section**

Replace the `Form { ... }` contents in `TypographyControls.swift` so the sections are: **Theme** (swatch grid) → **Font** (grouped picker) → **Size** slider → **Line Spacing** slider → **Paragraph Spacing** slider → **Width** (segmented) → **Read Aloud** (unchanged). Full file:

```swift
import SwiftUI
import SwiftData

struct TypographyControls: View {
    @Bindable var settings: AppSettings
    /// Optional live controller so a voice change while listening applies
    /// immediately (restarts the current paragraph) rather than next start.
    var controller: TTSController? = nil
    @Environment(\.dismiss) private var dismiss

    private let swatchColumns = [GridItem(.adaptive(minimum: 64), spacing: 12)]

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    LazyVGrid(columns: swatchColumns, spacing: 12) {
                        ForEach(ReaderTheme.allCases) { theme in
                            ThemeSwatch(
                                theme: theme,
                                selected: settings.readerTheme == theme
                            ) { settings.readerTheme = theme }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Font") {
                    ForEach(ReaderFont.Group.allCases) { group in
                        let fonts = ReaderFont.allCases.filter { $0.group == group }
                        if !fonts.isEmpty {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(fonts) { font in
                                FontRow(
                                    font: font,
                                    selected: settings.readerFontRaw == font.rawValue
                                ) { settings.readerFontRaw = font.rawValue }
                            }
                        }
                    }
                }

                Section("Size") {
                    Slider(value: $settings.readerFontSize, in: 12...32, step: 1) {
                        Text("Size")
                    } minimumValueLabel: {
                        Text("A").font(.footnote)
                    } maximumValueLabel: {
                        Text("A").font(.title3)
                    }
                    Text("\(Int(settings.readerFontSize)) pt")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Line Spacing") {
                    Slider(value: $settings.readerLineSpacing, in: 0...16, step: 1)
                    Text("\(Int(settings.readerLineSpacing)) pt")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Paragraph Spacing") {
                    Slider(value: $settings.readerParagraphSpacing, in: 0...28, step: 1)
                    Text("\(Int(settings.readerParagraphSpacing)) pt")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Width") {
                    Picker("Width", selection: .init(
                        get: { settings.readerWidth },
                        set: { settings.readerWidth = $0 }
                    )) {
                        ForEach(ReaderWidth.allCases) { w in
                            Text(w.displayName).tag(w)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Read Aloud") {
                    Picker("Provider", selection: $settings.ttsProvider) {
                        ForEach(TTSProvider.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    switch settings.ttsProvider {
                    case .apple:
                        Picker("Voice", selection: appleVoiceBinding) {
                            Text("System Default").tag("")
                            ForEach(VoiceCatalog.appleVoices(), id: \.identifier) { voice in
                                Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                            }
                        }
                    case .openAI:
                        Picker("Voice", selection: openAIVoiceBinding) {
                            ForEach(VoiceCatalog.openAIVoices, id: \.self) { v in
                                Text(v.capitalized).tag(v)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Typography")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var openAIVoiceBinding: Binding<String> {
        Binding(
            get: { settings.openAIVoice },
            set: { newVoice in
                settings.openAIVoice = newVoice
                controller?.setVoice(newVoice)
            }
        )
    }

    private var appleVoiceBinding: Binding<String> {
        Binding(
            get: { settings.appleVoiceID },
            set: { newVoice in
                settings.appleVoiceID = newVoice
                controller?.setVoice(newVoice)
            }
        )
    }
}

/// A tappable paper swatch showing a theme's background + a sample glyph in its
/// ink color, ringed when selected.
private struct ThemeSwatch: View {
    let theme: ReaderTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: theme.background))
                    Text("Aa")
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: theme.foreground))
                }
                .frame(height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12),
                                      lineWidth: selected ? 2.5 : 1)
                )
                Text(theme.displayName)
                    .font(.caption2)
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// A font-family row rendered in its own typeface, with a checkmark when active.
private struct FontRow: View {
    let font: ReaderFont
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(font.displayName)
                    .font(Font(font.uiFont(size: 18)))
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .font(.body.weight(.semibold))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
```

- [ ] **Step 2: Build**

Run: `build_sim`
Expected: SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ReadLater/Features/Reader/TypographyControls.swift
git commit -m "Expand Typography sheet: theme grid, font preview, spacing/width"
```

---

## Task 7: Settings size slider + full verification

**Files:**
- Modify: `ReadLater/Features/Settings/SettingsView.swift`

- [ ] **Step 1: Swap the size Stepper for a slider**

In `SettingsView.swift`, in the `Section("Reader")` block, replace:

```swift
                Stepper("Font Size: \(Int(settings.readerFontSize))",
                        value: $settings.readerFontSize,
                        in: 14...28)
```

with:

```swift
                VStack(alignment: .leading) {
                    Text("Font Size: \(Int(settings.readerFontSize)) pt")
                    Slider(value: $settings.readerFontSize, in: 12...32, step: 1)
                }
```

Leave the `Theme` picker as-is (Settings stays light; font family / spacing / width remain reader-sheet-only).

- [ ] **Step 2: Build + run the app**

Run: `build_run_sim`
Expected: SUCCEEDED and launches.

- [ ] **Step 3: On-device verification (drive the simulator)**

Open an article → tap to reveal chrome → tap the `AA` button. Confirm the sheet shows, in order: Theme swatch grid (9 tappable papers), Font (Reading + Sans groups, each row in its own face), Size / Line Spacing / Paragraph Spacing sliders, Width segmented control, and the Read Aloud section still present. Then:
- Pick **Paper** and **Slate** themes → reader background + ink update behind the sheet.
- Drag **Line Spacing** and **Paragraph Spacing** → body reflows.
- Change **Width** to Narrow / Full → column insets change.
- Create a highlight on a light theme and on a dark theme → both are legible (opaque, not muddy).

Capture screenshots (XcodeBuildMCP `screenshot`) of the sheet and of a dark-theme highlight for the record.

- [ ] **Step 4: Run the full test suite**

Run: `test_sim`
Expected: all tests PASS (the original 38 + the new ReaderTypography tests).

- [ ] **Step 5: Commit**

```bash
git add ReadLater/Features/Settings/SettingsView.swift
git commit -m "Use a font-size slider in Settings' Reader section"
```

---

## Self-Review (completed during authoring)

- **Spec coverage:** data model ✓ (T1), 5 new themes + moved colors ✓ (T2), theme-aware opaque highlights ✓ (T3), font groups ✓ (T4, system-only; bundled fonts deferred by design), render path spacing/width/paint ✓ (T5), full sheet UI ✓ (T6), Settings size slider ✓ (T7), tests ✓ (T1–T4). **Deferred by scope:** bundled OFL fonts + `UIAppFonts` registration + Accessibility font group + license files → follow-up plan. Live in-sheet body preview → spec's own v2.
- **Type consistency:** `uiColor(darkBackground:)`, `isDarkBackground(for:)`, `ReaderWidth.horizontalInset`, `ReaderFont.Group`, `readerWidth`/`readerLineSpacing`/`readerParagraphSpacing` are used identically across tasks.
- **No placeholders:** every code step shows complete code.

## Follow-up plan (separate)

**Bundled OFL fonts** — acquire Literata, Source Serif 4, Merriweather, Atkinson Hyperlegible Next, Lexend, OpenDyslexic, Geist, Inter (Regular + Italic); add under `ReadLater/Resources/Fonts/<Family>/` with each `OFL.txt`; register via `UIAppFonts` in `project.yml`; extend `ReaderFont` with the bundled cases + the **Accessibility** group + PostScript-name resolution with system fallback. **Requires downloading font files (permissioned).**
