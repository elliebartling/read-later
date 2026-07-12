# Theme Appearance Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split reader theming into appearance mode (Light/Dark/System) × palette choice, where System mode auto-switches between a user-chosen light palette and dark palette.

**Architecture:** Additive model changes first (new `ReaderAppearance` + palette fields + resolution + migration), then render-path switch to the resolved concrete theme, then UI, then removal of the legacy `.system` theme case and dead plumbing. Each task compiles and tests green on its own.

**Tech Stack:** Swift 6 / SwiftUI / SwiftData / UIKit; XcodeGen; XCTest. Build via XcodeBuildMCP (scheme `ReadLater`, sim iPhone 17). Worktree: `.claude/worktrees/theme-appearance-split`, branch `claude/theme-appearance-split`.

**Spec:** `docs/superpowers/specs/2026-07-11-theme-appearance-split-design.md`.

---

## File Structure

- `Shared/Models/AppSettings.swift` — `ReaderAppearance` enum; `readerAppearanceRaw`(=""), `readerLightThemeRaw`, `readerDarkThemeRaw` + accessors; `resolvedReaderTheme(systemIsDark:)`; `migrateLegacyThemeIfNeeded()`; `ReaderTheme.lightCases/darkCases/isDark`; (Task 4) delete `.system` case + `readerTheme` accessor.
- `Shared/Models/ReaderTheme+Colors.swift` — (Task 4) drop `.system` color branches and delete `isDarkBackground(for:)`.
- `ReadLater/RootView.swift` — run migration at the settings seed point.
- `ReadLater/Features/Reader/ReaderView.swift` — resolve theme from `colorScheme`, pass concrete theme.
- `ReadLater/Features/Reader/HighlightableTextView.swift` — `darkBackground = theme.isDark`; drop trait plumbing and signature suffix.
- `ReadLater/Features/Reader/TypographyControls.swift` — appearance segmented control + filtered swatch grids.
- `ReadLater/Features/Settings/SettingsView.swift` — Appearance picker replaces Theme picker.
- `ReadLaterTests/ReaderTypographyTests.swift` — new appearance/resolution/migration tests; update `.system`-referencing tests.

---

## Task 1: Model layer (additive) — appearance, palettes, resolution, migration

**Files:**
- Modify: `Shared/Models/AppSettings.swift`
- Modify: `ReadLater/RootView.swift`
- Test: `ReadLaterTests/ReaderTypographyTests.swift` (append)

- [ ] **Step 1: Write failing tests** — append to `ReaderTypographyTests.swift`:

```swift
extension ReaderTypographyTests {
    func testReaderAppearanceRawFallback() {
        let s = AppSettings()
        s.readerAppearanceRaw = "bogus"
        XCTAssertEqual(s.readerAppearance, .system)
    }

    func testPaletteMembership() {
        XCTAssertEqual(ReaderTheme.lightCases, [.light, .sepia, .paper, .mediumGray])
        XCTAssertEqual(ReaderTheme.darkCases, [.dark, .darkGray, .slate, .forest])
        for t in ReaderTheme.lightCases { XCTAssertFalse(t.isDark, "\(t) should be light") }
        for t in ReaderTheme.darkCases { XCTAssertTrue(t.isDark, "\(t) should be dark") }
    }

    func testPaletteAccessorsRejectWrongSide() {
        let s = AppSettings()
        s.readerLightThemeRaw = ReaderTheme.slate.rawValue   // dark palette in light slot
        XCTAssertEqual(s.readerLightTheme, .light)
        s.readerDarkThemeRaw = ReaderTheme.sepia.rawValue    // light palette in dark slot
        XCTAssertEqual(s.readerDarkTheme, .dark)
    }

    func testResolutionTruthTable() {
        let s = AppSettings()
        s.readerLightTheme = .paper
        s.readerDarkTheme = .slate

        s.readerAppearance = .light
        XCTAssertEqual(s.resolvedReaderTheme(systemIsDark: false), .paper)
        XCTAssertEqual(s.resolvedReaderTheme(systemIsDark: true), .paper)

        s.readerAppearance = .dark
        XCTAssertEqual(s.resolvedReaderTheme(systemIsDark: false), .slate)
        XCTAssertEqual(s.resolvedReaderTheme(systemIsDark: true), .slate)

        s.readerAppearance = .system
        XCTAssertEqual(s.resolvedReaderTheme(systemIsDark: false), .paper)
        XCTAssertEqual(s.resolvedReaderTheme(systemIsDark: true), .slate)
    }

    func testMigrationFromLegacyTheme() {
        // Light palette → light appearance carrying that palette.
        let a = AppSettings()
        a.readerThemeRaw = "sepia"
        a.migrateLegacyThemeIfNeeded()
        XCTAssertEqual(a.readerAppearance, .light)
        XCTAssertEqual(a.readerLightTheme, .sepia)
        XCTAssertEqual(a.readerDarkTheme, .dark)

        // Dark palette → dark appearance carrying that palette.
        let b = AppSettings()
        b.readerThemeRaw = "slate"
        b.migrateLegacyThemeIfNeeded()
        XCTAssertEqual(b.readerAppearance, .dark)
        XCTAssertEqual(b.readerDarkTheme, .slate)
        XCTAssertEqual(b.readerLightTheme, .light)

        // "system" and unknown → system + defaults.
        let c = AppSettings()
        c.readerThemeRaw = "system"
        c.migrateLegacyThemeIfNeeded()
        XCTAssertEqual(c.readerAppearance, .system)

        let d = AppSettings()
        d.readerThemeRaw = "bogus"
        d.migrateLegacyThemeIfNeeded()
        XCTAssertEqual(d.readerAppearance, .system)

        // Idempotent: second run doesn't clobber a user change.
        a.readerLightTheme = .paper
        a.migrateLegacyThemeIfNeeded()
        XCTAssertEqual(a.readerLightTheme, .paper)
    }
}
```

- [ ] **Step 2: Run `test_sim`** — expect FAIL/compile-error (new members missing).

- [ ] **Step 3: Add fields + accessors to `AppSettings`** — after the `readerWidthRaw` field add:

```swift
    /// Raw value of ReaderAppearance. Empty string = not yet migrated from the
    /// legacy single readerThemeRaw (see migrateLegacyThemeIfNeeded).
    var readerAppearanceRaw: String = ""
    /// Palette used in light appearance (and system-light). Light palettes only.
    var readerLightThemeRaw: String = ReaderTheme.light.rawValue
    /// Palette used in dark appearance (and system-dark). Dark palettes only.
    var readerDarkThemeRaw: String = ReaderTheme.dark.rawValue
```

After the `readerWidth` computed property add:

```swift
    var readerAppearance: ReaderAppearance {
        get { ReaderAppearance(rawValue: readerAppearanceRaw) ?? .system }
        set { readerAppearanceRaw = newValue.rawValue }
    }

    /// Falls back to .light if the stored raw is missing or a dark palette.
    var readerLightTheme: ReaderTheme {
        get {
            guard let t = ReaderTheme(rawValue: readerLightThemeRaw),
                  ReaderTheme.lightCases.contains(t) else { return .light }
            return t
        }
        set { readerLightThemeRaw = newValue.rawValue }
    }

    /// Falls back to .dark if the stored raw is missing or a light palette.
    var readerDarkTheme: ReaderTheme {
        get {
            guard let t = ReaderTheme(rawValue: readerDarkThemeRaw),
                  ReaderTheme.darkCases.contains(t) else { return .dark }
            return t
        }
        set { readerDarkThemeRaw = newValue.rawValue }
    }

    /// The concrete palette to render given the OS appearance.
    func resolvedReaderTheme(systemIsDark: Bool) -> ReaderTheme {
        switch readerAppearance {
        case .light:  return readerLightTheme
        case .dark:   return readerDarkTheme
        case .system: return systemIsDark ? readerDarkTheme : readerLightTheme
        }
    }

    /// One-time migration from the legacy single readerThemeRaw. Sentinel:
    /// an empty readerAppearanceRaw means "not migrated yet"; the method is a
    /// no-op afterwards, so user edits are never clobbered.
    func migrateLegacyThemeIfNeeded() {
        guard readerAppearanceRaw.isEmpty else { return }
        if let old = ReaderTheme(rawValue: readerThemeRaw), ReaderTheme.lightCases.contains(old) {
            readerAppearance = .light
            readerLightTheme = old
        } else if let old = ReaderTheme(rawValue: readerThemeRaw), ReaderTheme.darkCases.contains(old) {
            readerAppearance = .dark
            readerDarkTheme = old
        } else {
            // "system", unknown, or empty → system mode with default palettes.
            readerAppearance = .system
        }
    }
```

- [ ] **Step 4: Add `ReaderAppearance` and extend `ReaderTheme`** — after the `ReaderTheme` enum in the same file add:

```swift
enum ReaderAppearance: String, Codable, CaseIterable, Identifiable {
    case light, dark, system

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}
```

Inside the `ReaderTheme` enum body (after `displayName`) add:

```swift
    /// Palettes offered for light appearance / system-light.
    static let lightCases: [ReaderTheme] = [.light, .sepia, .paper, .mediumGray]
    /// Palettes offered for dark appearance / system-dark.
    static let darkCases: [ReaderTheme] = [.dark, .darkGray, .slate, .forest]

    /// Fixed page darkness. Drives highlight compositing and palette grouping.
    var isDark: Bool {
        switch self {
        case .dark, .darkGray, .slate, .forest:
            return true
        case .light, .sepia, .paper, .mediumGray:
            return false
        case .system:
            return false // legacy case; removed in the cleanup task
        }
    }
```

- [ ] **Step 5: Run migration at the seed point** — in `ReadLater/RootView.swift`, replace the body of `seedSettingsIfNeeded()`:

```swift
    private func seedSettingsIfNeeded() {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        let existing = (try? context.fetch(descriptor)) ?? []
        if let settings = existing.first {
            // One-time split of the legacy single theme into appearance + palettes.
            if settings.readerAppearanceRaw.isEmpty {
                settings.migrateLegacyThemeIfNeeded()
                try? context.save()
            }
        } else {
            let settings = AppSettings()
            settings.migrateLegacyThemeIfNeeded()
            context.insert(settings)
            try? context.save()
        }
    }
```

- [ ] **Step 6: Run `test_sim`** — expect PASS (58 tests: 53 + 5 new).

- [ ] **Step 7: Commit** — `git add` the three files; message: `Add reader appearance mode, palette slots, and legacy-theme migration`.

---

## Task 2: Render path — resolve theme from OS color scheme

**Files:**
- Modify: `ReadLater/Features/Reader/ReaderView.swift`
- Modify: `ReadLater/Features/Reader/HighlightableTextView.swift`

No new unit tests (SwiftUI/UIKit wiring); build + existing tests must stay green.

- [ ] **Step 1: ReaderView resolves the theme** — add to the property block (near the other `@Environment` lines):

```swift
    @Environment(\.colorScheme) private var colorScheme
```

Add a computed property (near `settings`):

```swift
    /// Concrete palette for the current appearance mode + OS color scheme.
    private var resolvedTheme: ReaderTheme {
        settings.resolvedReaderTheme(systemIsDark: colorScheme == .dark)
    }
```

Replace `settings.readerTheme.background.swiftUIColor` (the ZStack background) with `resolvedTheme.background.swiftUIColor`, and the `theme: settings.readerTheme,` argument in the `HighlightableTextView(...)` call with `theme: resolvedTheme,`.

- [ ] **Step 2: HighlightableTextView keys darkness off the theme** — in `updateUIView`, replace:

```swift
        let darkBackground = theme.isDarkBackground(for: tv.traitCollection)
        let signature = renderSignature(darkBackground: darkBackground)
```

with:

```swift
        let signature = renderSignature()
```

and the `tv.attributedText = render(darkBackground: darkBackground)` call with `tv.attributedText = render()`.

Change `private func renderSignature(darkBackground: Bool) -> String` back to `private func renderSignature() -> String` and drop the trailing `|\(darkBackground)` from the returned string (the theme rawValue in the signature now fully determines darkness).

Change `private func render(darkBackground: Bool) -> NSAttributedString` back to `private func render() -> NSAttributedString` and add as its first line:

```swift
        let darkBackground = theme.isDark
```

- [ ] **Step 3: Build + tests** — `build_sim` SUCCEEDED; `test_sim` 58/58.

- [ ] **Step 4: Commit** — message: `Resolve reader theme from appearance mode and OS color scheme`.

---

## Task 3: UI — appearance control + filtered swatch grids; Settings picker

**Files:**
- Modify: `ReadLater/Features/Reader/TypographyControls.swift`
- Modify: `ReadLater/Features/Settings/SettingsView.swift`

- [ ] **Step 1: Replace the Theme section in `TypographyControls`** — replace the current `Section("Theme") { ... }` (the LazyVGrid over `ReaderTheme.allCases`) with:

```swift
                Section("Theme") {
                    Picker("Appearance", selection: .init(
                        get: { settings.readerAppearance },
                        set: { settings.readerAppearance = $0 }
                    )) {
                        ForEach(ReaderAppearance.allCases) { a in
                            Text(a.displayName).tag(a)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch settings.readerAppearance {
                    case .light:
                        swatchGrid(ReaderTheme.lightCases, selection: lightThemeBinding)
                    case .dark:
                        swatchGrid(ReaderTheme.darkCases, selection: darkThemeBinding)
                    case .system:
                        paletteLabel("Light theme")
                        swatchGrid(ReaderTheme.lightCases, selection: lightThemeBinding)
                        paletteLabel("Dark theme")
                        swatchGrid(ReaderTheme.darkCases, selection: darkThemeBinding)
                    }
                }
```

Add these helpers to `TypographyControls` (below the voice bindings):

```swift
    private var lightThemeBinding: Binding<ReaderTheme> {
        Binding(
            get: { settings.readerLightTheme },
            set: { settings.readerLightTheme = $0 }
        )
    }

    private var darkThemeBinding: Binding<ReaderTheme> {
        Binding(
            get: { settings.readerDarkTheme },
            set: { settings.readerDarkTheme = $0 }
        )
    }

    private func paletteLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func swatchGrid(_ themes: [ReaderTheme], selection: Binding<ReaderTheme>) -> some View {
        LazyVGrid(columns: swatchColumns, spacing: 12) {
            ForEach(themes) { theme in
                ThemeSwatch(
                    theme: theme,
                    selected: selection.wrappedValue == theme
                ) { selection.wrappedValue = theme }
            }
        }
        .padding(.vertical, 4)
    }
```

(`swatchColumns` and `ThemeSwatch` already exist — reuse them unchanged.)

- [ ] **Step 2: Settings tab** — in `SettingsView.swift` `Section("Reader")`, replace:

```swift
                Picker("Theme", selection: $settings.readerTheme) {
                    ForEach(ReaderTheme.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
```

with:

```swift
                Picker("Appearance", selection: .init(
                    get: { settings.readerAppearance },
                    set: { settings.readerAppearance = $0 }
                )) {
                    ForEach(ReaderAppearance.allCases) { a in
                        Text(a.displayName).tag(a)
                    }
                }
```

- [ ] **Step 3: Build + tests** — `build_sim` SUCCEEDED; `test_sim` 58/58.

- [ ] **Step 4: Commit** — message: `Appearance mode UI: segmented control with per-side palette grids`.

---

## Task 4: Cleanup — remove `.system` theme case and dead plumbing; verify

**Files:**
- Modify: `Shared/Models/AppSettings.swift`
- Modify: `Shared/Models/ReaderTheme+Colors.swift`
- Modify: `ReadLaterTests/ReaderTypographyTests.swift`

- [ ] **Step 1: Grep guard** — `grep -rn "readerTheme\b\|ReaderTheme.system\|\.system" ReadLater Shared --include=*.swift | grep -viE "readerThemeRaw|systemFont|systemBackground|systemIsDark|readerAppearance|\.systemYellow"` — confirm the only remaining `.system`-as-ReaderTheme references and `readerTheme` accessor uses are the ones this task deletes. If anything else surfaces, STOP and report.

- [ ] **Step 2: Delete legacy members** — in `AppSettings.swift`:
  - Remove the `readerTheme` computed property (the accessor over `readerThemeRaw`). Keep the stored `readerThemeRaw` field (migration input; SwiftData-friendly).
  - In `ReaderTheme`, remove `system` from the case list (line becomes `case light, dark, sepia` + the second line unchanged) and delete the `case .system: return false // legacy…` branch from `isDark`.

  In `ReaderTheme+Colors.swift`: delete the `case .system:` lines from `foreground` and `background`, and delete the whole `isDarkBackground(for:)` function (no callers after Task 2).

- [ ] **Step 3: Update tests** — in `ReaderTypographyTests.swift`:
  - Delete `testReaderThemeRawFallback` (the accessor is gone; appearance fallback is covered by `testReaderAppearanceRawFallback`).
  - Rewrite `testExplicitThemeDarkness` to use `isDark` over all cases:

```swift
    func testExplicitThemeDarkness() {
        XCTAssertTrue(ReaderTheme.dark.isDark)
        XCTAssertTrue(ReaderTheme.slate.isDark)
        XCTAssertTrue(ReaderTheme.forest.isDark)
        XCTAssertTrue(ReaderTheme.darkGray.isDark)
        XCTAssertFalse(ReaderTheme.light.isDark)
        XCTAssertFalse(ReaderTheme.sepia.isDark)
        XCTAssertFalse(ReaderTheme.paper.isDark)
        XCTAssertFalse(ReaderTheme.mediumGray.isDark)
    }
```

  - `testAllThemesHaveOpaqueColors` and `testNewThemeCasesExist` keep working (allCases now has 8 members; neither asserts a count or references `.system`). Verify by reading them; adjust only if they reference `.system`.

- [ ] **Step 4: Build + full suite** — `build_sim` SUCCEEDED; `test_sim` — expect 57/57 (58 − 1 deleted).

- [ ] **Step 5: Commit** — message: `Remove legacy .system reader theme and dead darkness plumbing`.

- [ ] **Step 6 (controller): Simulator verification** — Typography sheet: segmented Light/Dark/System; Light shows 4 light swatches, Dark shows 4 dark, System shows both labeled grids; pick Paper (light slot) + Slate (dark slot) in System mode, flip the simulator appearance (`xcrun simctl ui <udid> appearance dark|light`) and confirm the reader background AND highlight bands swap palettes live; Settings tab shows the 3-option Appearance picker.

---

## Self-Review (done during authoring)

- **Spec coverage:** model+migration (T1), resolution+render (T2), sheet+Settings UI (T3), `.system` removal (T4). Migration deliberately never references the `.system` enum case so it survives T4.
- **Compile-green sequencing:** `.system` case survives until T4; `readerTheme` accessor's last consumers (ReaderView T2, TypographyControls/Settings T3) are gone before T4 deletes it.
- **Type consistency:** `resolvedReaderTheme(systemIsDark:)`, `readerLightTheme/readerDarkTheme`, `ReaderTheme.lightCases/darkCases/isDark` used identically across tasks.
