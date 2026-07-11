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

- **Highlight anchoring.** A highlight persists both `(startOffset, endOffset)` into `Article.plainText` AND the `quotedText` itself. Offsets are **UTF-16 code units** (they originate from `UITextView.selectedRange`); interpreting them as `Character` offsets misplaces highlights in emoji-bearing articles. On render, offsets are tried first; on miss we search for the quoted text (with a whitespace-collapsed fallback) and update. This keeps highlights stable across re-parses. See `ReadLater/Services/Highlighting/HighlightAnchor.swift`.
- **Article extraction.** Runs Readability.js in an off-screen `WKWebView`. The extracted plain text becomes the offset space for highlights; the extracted HTML is retained for future rich rendering.
- **Save pipeline.** The Share Extension does NOT touch the CloudKit sync channel. It writes a `PendingSave` JSON into the App Group container; the main app drains this on foreground. After writing the pending save, the extension deep-links back into the app (`readlater://open?id=<uuid>`) via the responder-chain `openURL:` trick so the user lands directly on the reader.
- **CloudKit constraints.** Every synced `@Model` attribute is optional or carries an inline default, and every relationship is optional — CloudKit-backed SwiftData throws at container creation otherwise. Keep that invariant when adding properties.
- **Two stores.** Articles/highlights/tags sync via the CloudKit private DB; `AppSettings` lives in a separate local-only store because it holds a security-scoped bookmark, which is device-specific and must never sync.
- **Obsidian export.** Managed-section writes: the app only rewrites the region between `%% readlater:start %%` and `%% readlater:end %%`, so your own edits in exported notes survive every export. Highlight colors use Dataview inline fields (`(color:: yellow)`), never wikilinks. Deterministic rendering → idempotent writes → doesn't churn file watchers.
- **CI.** `.github/workflows/ci.yml` runs xcodegen + build + unit tests on a macOS runner per push — the compile loop for changes authored off-Mac. Heads-up: macOS minutes bill at 10x on private repos.

## Roadmap

See the plan doc at `/root/.claude/plans/repository-i-want-to-inherited-honey.md` for the full plan. MVP is items 1-9 there.

**v2 backlog**

- YouTube (transcript fetch + rendering; Whisper fallback)
- Native RSS reader
- Shortcuts intents (Save URL, Export Highlights, Read Aloud)
- Pocket / Instapaper import
- macOS Catalyst / visionOS
- **Apple on-device intelligence.** Use Writing Tools (iOS 18+) or the Foundation Models framework (iOS 26+) to (a) auto-summarize a freshly-parsed article into a 2–3 sentence tl;dr shown above the reader body and (b) suggest tags by prompting the on-device model with the article title + first N paragraphs and matching against the user's existing `Tag` set. Both are on-device and free of API cost, so they can run automatically on every save. Requires bumping the deployment target to iOS 18 (Writing Tools) or 26 (Foundation Models) and gating with `#available`.

## License

MIT — see `LICENSE`.
