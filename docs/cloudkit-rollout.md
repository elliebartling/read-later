# CloudKit sync rollout

This branch wires the synced SwiftData store (`Article`, `Highlight`, `Tag`)
for CloudKit private-database mirroring, but ships it **gated off in production**
until the Apple Developer portal and CloudKit schema are ready. Debug/dev builds
attempt sync automatically once their provisioning profile grants iCloud; Release
(TestFlight/App Store) stays local-only until you deliberately flip it.

## How the runtime gate works

`SharedModelContainer.make` opens the synced store with CloudKit mirroring
**only when both** of these hold (see `Shared/ModelContainer+Shared.swift`):

1. **`CLOUDKIT_SYNC` compile condition** — defined via `project.yml` for the
   **Debug** config only, because Debug signs with `ReadLater.entitlements`
   (which carries the CloudKit entitlement). Release signs with the
   app-group-only `ReadLater.release.entitlements` and does **not** define this
   condition, so a TestFlight binary never even compiles the "attempt
   `.private(...)`" path in as reachable.
2. **Provisioning profile grants iCloud** — parsed at runtime from the app's
   embedded `embedded.mobileprovision`. This is what protects a real dev device
   *today*: the current dev profile does not yet include iCloud, so the check
   returns `false` and the app stays local-only instead of trapping.

Plus a runtime iCloud-account check (`ubiquityIdentityToken != nil`).

If mirroring can't be used, the app falls back cleanly: local persistent store →
in-memory as a last resort. It never crashes over sync availability, and the
outcome is recorded on `SyncStatus.shared`, surfaced in **Settings → iCloud
Sync**.

Why not just read our own entitlements at runtime? iOS exposes no public API for
that (`SecTask`/`SecCode` entitlement reads are macOS-only), so we AND-gate the
compile condition (reflects the app's entitlements file) with the profile parse
(reflects what the App ID actually grants).

## Remaining human portal steps (in order)

App Store Connect **API keys 401 on some of these private portal endpoints**, so
they are effectively human-only in a browser at
<https://developer.apple.com/account/resources>.

1. **Enable iCloud on the App ID.** Identifiers → `com.ellenbartling.readlater`
   → enable the **iCloud** capability (with **CloudKit**).
2. **Assign the container to the App ID.** Same screen → configure iCloud
   containers → check **`iCloud.com.ellenbartling.readlater`** (the container
   already exists in the portal; it is just not assigned yet).
3. **Regenerate provisioning profiles.** Both profiles must be regenerated so
   they carry the new iCloud capability, then downloaded/installed:
   - the development profile used for Debug device builds, and
   - **`ReadLater App Store`** (the distribution profile named in
     `project.yml`). Leave its name unchanged so signing config still matches.
   Note the extension profile names are intentionally crossed (see
   `project.yml`); do not "fix" them.
4. **Verify Development schema.** Run a Debug build on a real device signed with
   the updated development profile while signed into iCloud. SwiftData
   auto-initializes the schema in the **Development** CloudKit environment on
   first launch. Confirm the record types (`CD_Article`, `CD_Highlight`,
   `CD_Tag`) appear in CloudKit Console → Development.
5. **Deploy schema to Production.** CloudKit Console → **Deploy Schema to
   Production**. This is mandatory *before* any TestFlight/App Store build turns
   on sync — the Production environment is what TestFlight uses, and mirroring
   aborts uncatchably at launch if the schema isn't deployed there.

## Flipping Release (TestFlight/App Store) sync ON — only after step 5

Do this only once the **App Store distribution profile includes iCloud** *and*
the **schema is deployed to Production**. Order matters; getting it wrong ships a
launch crash to TestFlight.

In `project.yml`, under `targets → ReadLater → settings → configs → Release`:

1. Point Release at the CloudKit entitlements:
   ```yaml
   CODE_SIGN_ENTITLEMENTS: ReadLater/ReadLater.entitlements
   ```
   (Or copy the four iCloud keys from `ReadLater.entitlements` into
   `ReadLater.release.entitlements` and keep pointing at that file.)
2. Define the compile condition for Release too, so the mirroring path is
   reachable in the shipped binary:
   ```yaml
   SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) CLOUDKIT_SYNC"
   ```
3. `make gen`, then archive/export locally or via `ship-testflight.yml`. That
   workflow's "Verify entitlements survived signing" step will now confirm the
   iCloud entitlement is present instead of warning that it's missing.
4. Ship a TestFlight build and confirm sync across two devices signed into the
   same iCloud account.

To roll back, revert those two Release settings; Debug is unaffected either way.

## What is intentionally NOT synced

`AppSettings` lives in a separate **local-only** store
(`cloudKitDatabase: .none`) because it holds a device-specific security-scoped
Obsidian bookmark that must never travel between devices. Keep it out of the
synced schema. The Share and Safari extensions never open this container — they
hand off via `PendingSave` JSON in the App Group — so they are unaffected by the
CloudKit flip.
