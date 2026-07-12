# Audio Player & Bottom Toolbar UX Revamp

**Date:** 2026-07-11
**Figma:** `gAIwNTwi5XmW0l8eSR5XXP`, node `2-396` (Toolbars – Bottom)

## Goal

Replace the reader's full-width bottom toolbar and the translucent glass audio
player with a single **floating pink capsule** that changes shape between an
*idle* and a *playing* state, plus a classy new "silk ribbon" waveform.

## Visual language

- **Accent:** `#ff2d55` (Figma `Accents/Pink`, iOS system pink). White glyphs.
- **Capsule treatment:** iOS 26 → liquid glass with a *prominent* pink tint
  (glassy but clearly pink, both light & dark). Pre-26 fallback → solid
  `#ff2d55` with a soft pink drop shadow.
- **Placement:** centered, floating above the home indicator, replacing the
  `.bottomBar` toolbar. Appears with reader chrome (tap-to-reveal); hidden in
  immersive reading. Idle ↔ playing is a cross-fade so it reads as one object
  reshaping.

## Idle bar

`•••` overflow · share · tag · play

- **Share:** iOS share sheet for the article URL (SwiftUI `ShareLink`).
- **Overflow (`•••`):** Export to Obsidian, Mark as Read/Unread, Open Original
  (unchanged contents).
- **Tag:** opens the existing tag sheet.
- **Play:** starts TTS → swaps to the playing bar.

## Playing bar

`[ silk waveform ]` · speed · ⏮ · ⏯ · ⏭

- **Waveform (flex, left):** silk ribbon; also a progress readout (played
  fraction bright, upcoming fraction faded). Tapping it **stops** and collapses
  the player (keeps today's gesture; add a subtle affordance for discovery).
- **Speed:** cycles `1.0 → 1.25 → 1.5 → 2.0 → 0.75` (unchanged logic).
- **Transport cluster:** skip-back / play-pause / skip-forward. Skips call the
  existing `TTSController.skipBackward()` / `skipForward()` — **previous/next
  paragraph**, not ±30s (engine is paragraph-based; Apple voices have no time
  seek). Plain chevron/backward glyphs, not "30".
- **Buffering:** transport button shows the spinner-ring cancel (unchanged).

## Silk waveform

Continuous smooth waveform line with a soft filled body, undulating via layered
sine motion (stylized, not amplitude-driven — Apple's engine gives no
amplitude, so a real meter would sit flat for Apple voices). White on pink.
Animates while playing; freezes to a gentle static curve when paused. Played
vs. upcoming fraction differentiated by opacity for at-a-glance position.

## Voice picker relocation

Voice selection leaves the player bar and moves into the reading-settings sheet
(`TypographyControls`, the `AA` sheet) as a "Read Aloud" section (provider +
voice), mirroring `SettingsView`. Changing voice while playing applies live via
`TTSController.setVoice` (sheet receives an optional controller).

## Files

- `ReadLater/Features/Reader/AudioPlayerBar.swift` — rewrite: pink capsule,
  new playing layout, silk `WaveformView`, wire skip transport. House both the
  playing bar and the new idle bar here (shared capsule styling).
- `ReadLater/Features/Reader/ReaderView.swift` — replace `.bottomBar` toolbar
  with the floating idle capsule; add `ShareLink`; cross-fade idle ↔ playing.
- `ReadLater/Features/Reader/TypographyControls.swift` — add the voice section.

## Out of scope

- True time-based (±30s) seeking.
- Real audio-reactive amplitude visualization.
- Changing the global `SettingsView` Read Aloud section.
