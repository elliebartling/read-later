# Read Later

Native iOS Read Later app with Readwise-style highlighting, Apple + OpenAI text-to-speech, and Obsidian export.

## Status

Very early v0.1 scaffold. What's here:

- SwiftUI + SwiftData + CloudKit private-DB sync
- Share Extension + Safari Web Extension save flows
- Reader with a `UITextView`-backed custom highlight menu (4 colors, optional note)
- Apple `AVSpeechSynthesizer` TTS + OpenAI `/v1/audio/speech` TTS (BYO API key, stored in Keychain)
- Obsidian export to any user-picked folder in Files (security-scoped bookmark)
- Full-text search across saved articles
- XcodeGen-driven project (no `.xcodeproj` in the repo — regenerate with `make gen`)

Not here yet: YouTube, RSS, Shortcuts, Pocket import (see the plan doc).

## Requirements

- macOS with Xcode 15.3+
- iOS 17+ target device or Simulator
- Apple Developer account (needed for CloudKit + TestFlight)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## First-run setup

```sh
make gen        # generates ReadLater.xcodeproj from project.yml
make open       # opens the project in Xcode
```

Before it builds:

1. **Signing team.** In Xcode, set your Team on the three targets (or fill in `DEVELOPMENT_TEAM` in `project.yml` and re-run `make gen`).
2. **iCloud container.** In the CloudKit dashboard, create a container named `iCloud.com.ellenbartling.readlater` (or edit `ReadLater/ReadLater.entitlements` and `Shared/AppGroup.swift` to match your prefix). Enable CloudKit capability + iCloud entitlement on the main target.
3. **App Group.** Enable App Groups capability on the main target and both extensions, and add `group.com.ellenbartling.readlater` to all three.
4. **Bundle Readability.js.** Download the latest [Readability.js](https://raw.githubusercontent.com/mozilla/readability/main/Readability.js) into `ReadLater/Resources/readability.js`. Without it, the article parser falls back to a minimal `<article>`/`<main>` extractor.

## Run

```sh
make build      # xcodebuild against the iPhone 15 simulator
make test       # unit tests (HighlightAnchor, MarkdownFormatter)
```

Then Cmd-R in Xcode to launch the app.

## Repo layout

```
project.yml               XcodeGen spec — source of truth for targets
Makefile                  gen / build / test / lint
Shared/                   SwiftData models + App Group helpers (used by app + share ext)
ReadLater/                Main iOS app (SwiftUI, Reader, Settings, TTS, export)
ShareExtension/           iOS Share Sheet extension → writes PendingSave JSON
SafariWebExtension/       MV3 Safari web extension → same PendingSave path
ReadLaterTests/           XCTest unit tests
```

## Design notes

- **Highlight anchoring.** A highlight persists both `(startOffset, endOffset)` into `Article.plainText` AND the `quotedText` itself. On render, offsets are tried first; on miss we search for the quoted text (with a whitespace-collapsed fallback) and update. This keeps highlights stable across re-parses. See `ReadLater/Services/Highlighting/HighlightAnchor.swift`.
- **Article extraction.** Runs Readability.js in an off-screen `WKWebView`. The extracted plain text becomes the offset space for highlights; the extracted HTML is retained for future rich rendering.
- **Save pipeline.** The Share Extension does NOT touch the CloudKit sync channel. It writes a `PendingSave` JSON into the App Group container; the main app drains this on foreground.
- **CloudKit constraints.** All SwiftData `@Model`s use optional relationships and non-required uniqueness where CloudKit requires it.
- **Obsidian export.** Deterministic markdown render → idempotent writes → doesn't churn file watchers.

## Roadmap

See the plan doc at `/root/.claude/plans/repository-i-want-to-inherited-honey.md` for the full plan. MVP is items 1-9 there; YouTube, RSS, Shortcuts, and Pocket import are v2.

## License

MIT — see `LICENSE`.
