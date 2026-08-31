# Mac App Store Release Track

This repository supports two macOS editions from the same Swift sources:

| Concern | Direct download | Mac App Store |
| --- | --- | --- |
| App identifier | `com.xcv58.SDImport` | `media.jenny.sdimport` |
| Helper identifier | `com.xcv58.SDImport.Agent` | `media.jenny.sdimport.agent` |
| Shared container | Native app support directory | `group.media.jenny.sdimport` |
| Updates | Sparkle | App Store |
| Access | Unlimited | One completed import free, then lifetime IAP |
| Source access | Normal filesystem access | User-approved security-scoped access |
| Source ejection | Available | Available after source authorization |

The App Store lifetime product is the non-consumable
`media.jenny.sdimport.unlimited`. Keep these identifiers stable after the first
release; changing one creates a different app, helper, group, or purchase.

## Source And Project Layout

- `SDImport/Packages/SDImportCore` remains the shared source of truth.
- `SDImport/project.yml` is the canonical App Store XcodeGen specification.
- `SDImport/SDImportMacAppStore.xcodeproj` is checked in so an archive does not
  require XcodeGen on the release Mac.
- `SDImport/Packaging/MacAppStore` owns App Store plists, entitlements, privacy
  manifests, and the local StoreKit configuration.
- `script/build_and_run.sh` owns only the direct-download staging path.
- `script/build_app_store.sh` builds the App Store staging bundle from the same
  Xcode project used for archives, preventing a second packaging definition
  from drifting away from the submitted product.
- `script/verify_app_store_bundle.sh` fails closed on identifier, sandbox,
  helper-placement, privacy-manifest, StoreKit, signature, or Sparkle drift.
- Debug configurations use manual Apple Development signing with
  `SD Import for Mac Development` and `SD Import Agent Development`. Release
  configurations use manual Apple Distribution signing with `SD Import for Mac
  App Store` and `SD Import Agent App Store`. Both configurations therefore
  fail instead of silently falling back to wildcard profiles.

Regenerate the checked-in Xcode project after changing `project.yml`:

```bash
cd SDImport
xcodegen -s project.yml
```

The post-generation hook adds the StoreKit configuration to the scheme's test
action. Do not edit the generated project by hand.

## Compatibility Audit

The App Store edition uses the same core and UI with the distribution policy as
the capability boundary. The current audit is:

| Area | App Store behavior | Evidence or remaining gate |
| --- | --- | --- |
| Detection | `NSWorkspace.didMountNotification` and volume metadata identify a removable mount. The MAS policy omits capacity and media probing before consent. | Policy, helper, foreground observer, mailbox tests, and physical insertion pass. |
| Helper | `SMAppService` runs the embedded sandboxed login item and an App Group mailbox carries occurrence-identified mount events. | Structural and deterministic tests pass. Both exact development profiles are installed, the login item is explicitly allowed, and signed synthetic plus physical handoffs pass. |
| Bookmarks | Source and destination access comes only from user-selected read/write security scopes. Fresh bookmarks restore across relaunch; stale bookmarks are rejected until a new selection. | Synthetic signed import/relaunch passed; revoked and stale repair UI remains a clean-account gate. |
| `/Volumes` assumptions | `/Volumes` is only a mount-root discovery/default placeholder and a verified ejection-target boundary. It is not treated as App Store content authorization. | Source enumeration is downstream of `ensureSourceAccessForScan`; the MAS archive has no filesystem exception entitlement. |
| Ejection | Offered only for a selected, verified removable source after user authorization. The MAS edition reuses the existing `NSWorkspace` path and the same conservative identity, destination-device, busy-volume, and error checks as the direct edition. | Passed 2026-08-31 with an exact signed sandboxed MAS Debug build and a physical removable Secure Digital card. Controls appeared before scan, after scan, and on the successful receipt; the receipt action unmounted the card and reported it safe to remove. No additional entitlement was added. |
| Diagnostics | App-owned redacted diagnostics remain available. Browsing system crash-report directories is not offered in the MAS edition. | Edition policy and diagnostics redaction tests pass. |
| Quick Look | Thumbnails and previews use URLs below the already authorized source while `AppModel` retains the matching security-scope object. | No additional entitlement or subprocess is used; confirm previewing from a physical card in final QA. |
| Legacy importer | Unsandboxed legacy-state discovery runs only in the direct edition. | Central distribution policy and tests pass. |
| Portable receipts | The optional ledger uses the source's user-selected read/write scope. Read-only or locking failures produce warnings and do not block normal local history/import behavior. | Ledger safety/concurrency tests pass; confirm a read-only physical card in final QA. |
| Subprocesses | The shipped Swift app/helper launch no command-line subprocesses. Process use is confined to repository tooling. | Source audit passes. |
| Privileged operations | The MAS app/helper contain no privilege escalation or temporary exception entitlement. Source ejection uses the public `NSWorkspace` API only after the user authorizes the selected source. | Entitlement verification and exact signed physical MAS ejection passed without a temporary exception. |
| Updates | Sparkle remains a direct-edition dependency and is absent from the MAS app target and archive. | Direct packaging and MAS archive verifiers pass. |

## Local Verification

Run the shared tests from `SDImport/Packages/SDImportCore`:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
```

Run the signed, app-hosted StoreKit tests from `SDImport`:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild test \
  -project SDImportMacAppStore.xcodeproj \
  -scheme SDImportForMac \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:SDImportStoreKitTests
```

The StoreKit suite covers the exact product metadata, successful purchase,
refund and revocation, restore, Ask to Buy pending state, and failed
verification using the local Xcode StoreKit configuration. The deterministic
core policy tests separately cover the free allowance and cancellation. These
tests validate commerce behavior; they are not evidence of valid production
provisioning or a working sandbox container. The provisioned archive verifier
and manual QA matrix are separate release gates.

The core suite also locks down the edition boundary: exact identifiers, the
pre-consent mount privacy policy, App Group mailbox location and fail-closed
behavior, balanced security-scope start/stop lifetime, and direct-edition
capabilities. It also proves that the App Store edition rejects stale bookmarks
until the user selects the folder again, while the direct edition preserves its
existing stale-bookmark refresh behavior.

Build and audit a local App Store-shaped bundle from the repository root:

```bash
BUILD_CONFIGURATION=release APP_VERSION=1.0 APP_BUILD=1 \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
./script/build_app_store.sh build
```

Create the actual Xcode archive only after the exact App IDs, App Group, signing
certificate, and provisioning profiles exist:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild archive \
  -project SDImportMacAppStore.xcodeproj \
  -scheme SDImportForMac \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath /tmp/SDImportMacAppStore.xcarchive

REQUIRE_PROVISIONED_SIGNATURE=1 ./script/verify_app_store_bundle.sh \
  '/tmp/SDImportMacAppStore.xcarchive/Products/Applications/SD Import for Mac.app'
```

`REQUIRE_PROVISIONED_SIGNATURE=1` additionally requires embedded profiles with
the exact App IDs, team, and App Group entitlements, and rejects development
`get-task-allow`. The normal audit also requires universal app/helper binaries,
the exact lifetime product identifier in the compiled app, and no StoreKit test
artifacts. This is the release gate; the ad-hoc staged bundle is only a local
structure and behavior audit.

Run the development-provisioned sandbox runtime gate from a clean macOS QA
account:

```bash
CONFIRM_CLEAN_MAS_QA_ACCOUNT=1 \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
./script/run_mas_runtime_qa.sh
```

The wrapper builds a fresh Debug MAS app, verifies its signature and production
App Sandbox, user-selected-folder, and App Group entitlements, and rejects any
XCTest temporary exception. A standalone Accessibility driver then uses real
macOS folder panels to authorize a synthetic card and destination, scans and
imports one JPEG, verifies the copied output, relaunches the same app, and scans
again through the persisted source bookmark without reopening the folder panel.
The fixture, app, driver, and DerivedData are removed after the run.

Run the signed login-item/App Group/consent gate from the same clean QA
account:

```bash
CONFIRM_CLEAN_MAS_QA_ACCOUNT=1 \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
./script/run_mas_helper_runtime_qa.sh
```

This second wrapper requires exact Apple Development profiles for both
`media.jenny.sdimport` and `media.jenny.sdimport.agent`, with
`group.media.jenny.sdimport` enabled. It rejects Xcode's wildcard
`Mac Team Provisioning Profile: *` before installing or registering anything.
The MAS Debug targets intentionally use manual signing with the stable profile
names `SD Import for Mac Development` and `SD Import Agent Development` so
Xcode cannot silently fall back to a wildcard profile. Renew or regenerate the
profiles under the same names to avoid a project-file change.
It installs a clearly named temporary app below `/Applications`, registers its
real embedded `SMAppService` login item, and mounts an isolated disk image. A
Debug-only adapter injects one `MountedVolume` only after the production volume
eligibility boundary because production deliberately rejects disk images. From
there, the signed helper, App Group mailbox, containing-app launch, consent
sheet, and `Don't Scan` path are production code. The driver requires the
explicit no-scan message, proves no folder panel or review appears before
consent, declines, and again proves no scan UI appears. The helper is
unregistered and all exact temporary processes, app files, image, mount, and
DerivedData are removed after the run.

If macOS retains a disabled historical Login Items record, use the explicit
two-stage path instead of trying to automate approval:

```bash
PREPARE_MAS_HELPER_QA_APPROVAL=1 \
CONFIRM_CLEAN_MAS_QA_ACCOUNT=1 \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
./script/run_mas_helper_runtime_qa.sh

# Manually allow SDImportAgent in System Settings > General >
# Login Items & Extensions, then:
RESUME_MAS_HELPER_QA_AFTER_APPROVAL=1 \
CONFIRM_CLEAN_MAS_QA_ACCOUNT=1 \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
./script/run_mas_helper_runtime_qa.sh
```

Prepare mode keeps only the exact signed temporary app, its registration, and
a receipt containing the current Git commit, both code-directory hashes, and
the driver/wrapper hashes. Resume mode refuses a changed checkout, app, or QA
tool, revalidates both embedded profiles and signatures, and then runs the same
mailbox/consent driver without re-registering the approved item. A successful
resume unregisters and removes everything. A failed resume preserves the
approval state for diagnosis and retry. Neither mode can grant or bypass Login
Items approval.

This gate does not prove that macOS reports a physical card as removable or
that `NSWorkspace.didMountNotification` reaches the helper. Keep physical
insertion/reinsertion as a distinct pre-submission gate.

This gate requires Accessibility permission for the terminal or automation host.
It deliberately uses `media.jenny.sdimport`, so it can update that account's MAS
sandbox preferences, bookmarks, history, and dedupe state. The confirmation
variable is an intentional guard: do not run it in an account containing real
MAS user data. It does not simulate removable-media insertion, login-item wake,
bookmark revocation, StoreKit sandbox, or TestFlight.

Never use `ALLOW_UNTRUSTED_DEVELOPMENT_SIGNATURE=1` as release evidence. It is
only a diagnostic option for inspecting other bundle properties while a local
development certificate trust problem is being repaired.

## Current Validation Status

Snapshot from 2026-08-31:

| Goal gate | Current evidence | Remaining evidence |
| --- | --- | --- |
| Sandboxed manual import | A standalone, development-provisioned MAS Debug app passed the synthetic runtime gate with App Sandbox, user-selected read/write, and the App Group entitlement, with no temporary exceptions. A separate physical removable-card pass scanned one synthetic JPEG, authorized a destination through `NSOpenPanel`, completed the copy with 1 imported, 2 support files skipped, and 0 failed, and verified the source and copy byte-for-byte. A rescan reported Nothing New. The App Store-shaped Release bundle and trusted Apple Distribution archive also pass their structural and strict signature verifiers. | Repeat the import on the processed TestFlight build before submission. |
| Bookmark persistence and revocation | The runtime gate relaunched the independently signed app, restored the selected synthetic source through its security-scoped bookmark without another folder panel, and completed a second scan. The physical card also remained selectable and scannable across app relaunches without another source panel. Core tests prove exact group-path selection, fail-closed missing-group behavior, one-for-one security-scope lifetime, and that the App Store edition refuses stale bookmarks until a new user selection while the direct edition retains refresh behavior. | Stale-bookmark and revoked-permission repair UI in a clean provisioned QA account. |
| No scan before consent | The shared mount policy test proves the App Store edition reads no capacity, performs no media probe, and sends no distributed-notification handoff before consent. Both helper and observer use that policy. The exact signed helper-consent gate passed after explicit Login Items approval. Physical insertion then woke the app and presented per-scan consent; declining produced no scan, while allowing selected the physical card and enabled the later import pass. | Repeat on the processed TestFlight build in a clean account. |
| Sandboxed helper mailbox | Mailbox/causality tests and App Group path tests pass. Both App IDs are assigned to the registered App Group, and exact device-scoped development profiles are installed. The signed helper registered, launched, persisted the injected handoff through the App Group mailbox, and woke the app. A later physical Secure Digital insertion independently woke the app and presented the consent sheet. | Recheck helper launch after login/reboot and on the processed TestFlight build. |
| Source ejection | The exact signed sandboxed MAS Debug build exposed the named eject control for the selected physical card before scan, after scan, and on an error-free import receipt. The receipt action unmounted the removable Secure Digital card, changed to a safe-removal confirmation, and left the imported copy accessible. The app and helper retained only their production sandbox, user-selected-folder, and App Group entitlements, with no temporary exception. | Repeat on the processed TestFlight build. Exercise automatic ejection and macOS refusal while the source is busy before release. |
| StoreKit | Six app-hosted local StoreKit tests pass with no skips; purchase/refund and restore each passed 10 repeated focused runs. Core policy covers free allowance and cancellation. Restore checks current entitlements first and falls back only to Apple's verified, non-revoked latest transaction for the exact product after an explicit sync; verification failure remains fail-closed. | Sandbox/TestFlight purchase and restore after the IAP exists in App Store Connect. |
| Both editions | 233 tests in 35 suites pass; direct and App Store Release builds succeed; direct Sparkle packaging and identifiers remain intact. | None locally. |
| Archive inspection | A fresh current-HEAD Apple Distribution archive after enabling MAS source ejection passed the strict verifier: exact app/helper identifiers and profiles, team and App Group, universal binaries, sandbox entitlements with no temporary exception, privacy manifests, lifetime product ID, helper placement, test-artifact exclusion, and no Sparkle. | Repeat with the final version/build numbers immediately before upload. |

The standalone synthetic runtime gate is counted only for manual folder
authorization, copying, and same-folder bookmark relaunch. The distinct
physical pass covers removable-media delivery, app-level consent, a completed
copy, and known-file rescan. It does not cover permission revocation or
StoreKit. App-hosted StoreKit simulation is likewise not counted as sandboxed
file or helper evidence. Those remaining flows still require the manual
provisioned-build matrix.

An earlier outside-sandbox archive on 2026-08-30, before Release-only manual
signing and the matching private key were installed, completed with exit status
zero but used Apple Development and wildcard team profiles. The strict verifier
correctly rejected it. After installing the private key and pinning the two
Release profiles, a fresh post-StoreKit-fix archive used Apple Distribution and
passed `REQUIRE_PROVISIONED_SIGNATURE=1`. A successful `xcodebuild archive`
alone is therefore still insufficient; the verifier result is the evidence.

## Apple Account Setup

Completed in the Apple Developer account through 2026-08-31:

- Registered explicit App IDs `media.jenny.sdimport` and
  `media.jenny.sdimport.agent`.
- Registered `group.media.jenny.sdimport`, enabled App Groups for both App IDs,
  and assigned the exact group to both.
- Created and installed `SD Import for Mac App Store` and
  `SD Import Agent App Store` distribution profiles. Both expire 2027-07-03
  and contain the expected application identifier and App Group entitlements.
- Restored the matching `YTAJ6D4BV2` Apple Distribution identity and private
  key to this Mac's login Keychain, verified it with a disposable signing probe,
  and used it for a successful strict archive.
- Created and installed `SD Import for Mac Development` and
  `SD Import Agent Development` for this Mac. They expire 2027-08-31, embed the
  usable Apple Development identity, authorize the exact app identifiers, and
  contain `group.media.jenny.sdimport`.

The two distribution profiles cannot be used for local runtime QA because macOS
does not launch App Store distribution builds outside App Store/TestFlight.

These owner actions remain and are intentionally not performed by build
scripts:

1. Create the macOS app record in App Store Connect with
   `media.jenny.sdimport`.
2. Create the non-consumable IAP `media.jenny.sdimport.unlimited`, including
   price, localization, review screenshot, and review notes.
3. Complete paid-app agreements, tax, and banking requirements before testing
   or selling the IAP.
4. Complete App Privacy, age rating, category, support URL, privacy URL,
   screenshots, description, and review contact fields from the shipped build's
   behavior.
5. Attach the IAP to the first app-version submission when App Store Connect
   requires it.
6. Publish the updated `docs/privacy.html` and `docs/support.html` before
   submission. The production URLs respond, but as of 2026-08-30 they still
   serve the pre-App-Store disclosures from 2026-07-31.

The local archive gate now passes without overrides. The remaining release gates
are App Store Connect validation, sandbox/TestFlight commerce testing, and the
manual matrix below.

## App Store Assets And Metadata

Prepare these items before creating the first submission:

- App name `SD Import for Mac`, free app price, primary category Photography,
  age rating, content-rights answer, availability, copyright, and release mode.
- Subtitle, description, keywords, support URL, and privacy policy URL. The
  current in-app links are `https://macos-automation.vercel.app/support.html`
  and `https://macos-automation.vercel.app/privacy.html`; recheck both from the
  production build before submission.
- Between one and ten Mac screenshots, all without transparency, at one
  accepted 16:10 size: 1280 x 800, 1440 x 900, 2560 x 1600, or 2880 x 1800.
  Include the scan-consent prompt, preview, destination planning, purchase
  screen, and completed-import report without personal filenames or volumes.
- App Review contact details and notes that describe the background helper,
  the two-step scan consent, the first completed import being free, where to
  purchase or restore, and how to exercise the flow with synthetic media.
- Export-compliance determination and the App Privacy answer matching the
  shipped behavior: no developer analytics or server collection, with Apple
  processing StoreKit transactions.
- For `media.jenny.sdimport.unlimited`: Non-Consumable type, reference name,
  price, at least one localization, review notes, and a review-only screenshot
  showing the purchase UI. Make an explicit final decision about Family
  Sharing before creating the App Store Connect product.
- Add the first non-consumable to the same draft submission as the first app
  version; Apple requires the first item of that purchase type to accompany a
  new app version.

Current Apple references: [Mac screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/),
[required app properties](https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties),
[IAP information](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information),
and [first-IAP submission](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase).

## Manual App Store QA

Use a clean macOS account or reset container permissions. Use synthetic test
media unless the owner explicitly authorizes a personal card.

- Launch with no prior bookmarks; select destination folders and relaunch to
  prove bookmark persistence.
- Enable the login item, quit the main app, and insert a card. Confirm the
  helper wakes the app without enumerating the card.
- Decline the app's scan prompt and confirm no media is enumerated.
- Accept the scan prompt, decline the macOS folder panel, and confirm no scan.
- Accept both prompts, scan, preview, and complete one import.
- Confirm previews and failed/empty imports do not consume the free allowance.
- Confirm a second completed import requires the lifetime purchase.
- Exercise purchase, cancellation, pending approval, restore, refund, and
  revocation with StoreKit sandbox/TestFlight accounts.
- Confirm the App Store edition has no Sparkle UI, legacy-state import, or
  system crash-report browser. Confirm source-eject controls appear only for a
  selected, verified removable source and never while scanning or copying.
- Reinsert the same card and confirm a new consent prompt appears before a new
  scan while the retained security-scoped permission still resolves correctly.
- Export and review redacted diagnostics; confirm no filenames or full paths
  are included.

Do not submit, upload, or publish until the owner explicitly authorizes that
external action.
