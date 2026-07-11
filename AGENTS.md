# AGENTS.md

## Cursor Cloud specific instructions

### Repo layout note

- The `main` branch contains only `README.md` and `LICENSE`. The actual
  application lives on the unmerged branch
  `claude/ios-read-later-app-jb9gyy`: a native iOS "Read Later" app
  (SwiftUI + SwiftData + CloudKit private-DB sync, plus a Share Extension and a
  Safari Web Extension). That branch's `README.md` is the authoritative setup
  guide.

### This is an iOS / Apple-only project — it cannot be built on the Cloud Agent VM

- Cursor Cloud Agent VMs run **Linux (Ubuntu)**. This project targets iOS 17+
  and can only be built, run, and tested on **macOS with Xcode 15.3+** using the
  iOS Simulator.
- The toolchain is Apple-only: project generation uses **XcodeGen**
  (`brew install xcodegen` → `make gen`), builds/tests use **`xcodebuild`**
  against the **iOS Simulator**, and lint uses **`swiftformat`**. None of these
  exist on Linux, and `swift`/`xcodebuild`/`xcrun`/`xcodegen`/`brew` are not
  installed here.
- Every Swift source imports Apple-only frameworks (`SwiftUI`, `SwiftData`,
  `UIKit`, `AVFoundation`, `SafariServices`, `Social`, `Security`,
  `UniformTypeIdentifiers`). Installing the open-source Swift-on-Linux toolchain
  does **not** help — those frameworks ship only with Apple SDKs, so nothing
  here will compile on Linux.

### How to build / test / lint (on macOS only)

- See the app branch's `README.md` and `Makefile`. Standard commands:
  `make gen` (regenerate `ReadLater.xcodeproj` from `project.yml`),
  `make build`, `make test` (XCTest unit tests), `make lint` (`swiftformat --lint`).
- CI is the practical build environment for changes authored off-Mac:
  `.github/workflows/ci.yml` runs on a **`macos-15`** GitHub runner
  (xcodegen generate → xcodebuild build → xcodebuild test on the iOS Simulator).

### Cloud Agent update script

- There are **no Linux-installable dependencies**, so the startup update script
  is intentionally a no-op. Do not add Swift/Xcode/brew installation to it —
  those cannot run on the Linux VM.
