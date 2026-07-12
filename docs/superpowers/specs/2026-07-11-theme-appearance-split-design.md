# Theme Appearance Split — Design

**Date:** 2026-07-11
**Status:** Approved (chat, post-PR#4)
**Builds on:** 2026-07-11-reader-typography-settings-design.md (shipped in PR #4)

## Problem

Theming conflates two choices in one 9-way picker: *appearance mode* and
*palette*. "System" is a palette pretending to be a mode — it uses
`.label`/`.systemBackground` instead of any of the designed palettes, so a
system-mode reader never gets Sepia-by-day / Slate-by-night behavior.

## Model

Split into appearance × palette:

- **`ReaderAppearance`** — `light` / `dark` / `system` (default `system`).
- **`readerLightTheme`** — one of the 4 light palettes: Light, Sepia, Paper,
  Medium Gray (default Light).
- **`readerDarkTheme`** — one of the 4 dark palettes: Dark, Dark Gray, Slate,
  Forest (default Dark).
- **`ReaderTheme` drops `.system`.** The 8 concrete palettes remain; each has a
  static `isDark` (no trait collection needed anywhere).

**Resolution:** `resolvedReaderTheme(systemIsDark:)` — light → lightTheme;
dark → darkTheme; system → OS dark ? darkTheme : lightTheme. `ReaderView`
reads `@Environment(\.colorScheme)` and passes the resolved concrete theme
down. `renderSignature` already contains `theme.rawValue`, so appearance flips
re-render automatically; the `tv.traitCollection` plumbing and
`isDarkBackground(for:)` parameter are deleted.

**Migration:** one-time, at RootView's settings seed point. Sentinel: new
`readerAppearanceRaw` defaults to `""` (= unmigrated). Mapping from old
`readerThemeRaw`: "system"/unknown → system + palette defaults; a light
palette → appearance light + that palette; a dark palette → appearance dark +
that palette. Old `readerThemeRaw` field stays on the model (SwiftData-
friendly) but is no longer read after migration.

## UI

- **Typography sheet Theme section:** Appearance segmented control (Light /
  Dark / System) on top. Light or Dark selected → one 4-swatch grid for that
  side. System selected → both grids stacked, labeled "Light theme" and
  "Dark theme". Same `ThemeSwatch` component.
- **Settings tab:** the 9-theme picker becomes a 3-option Appearance picker.
  Palette choices live only in the reader sheet.

## Out of scope

Highlight compositing, spacing, width, fonts — untouched (compositing already
keys off theme darkness). Bundled OFL fonts remain a separate follow-up.

## Decisions log

| Decision | Choice |
|----------|--------|
| System-mode UI | Both grids stacked, labeled |
| Explicit-mode UI | Only that side's 4 palettes |
| Settings tab | Appearance picker only |
| System defaults | Light + Dark (not Paper/Slate) |
| Migration | One-time at seed point, sentinel empty appearanceRaw |
