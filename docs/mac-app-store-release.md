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
| Source ejection | Available | Not offered |

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

Regenerate the checked-in Xcode project after changing `project.yml`:

```bash
cd SDImport
xcodegen -s project.yml
```

The post-generation hook adds the StoreKit configuration to the scheme's test
action. Do not edit the generated project by hand.

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
capabilities.

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

Never use `ALLOW_UNTRUSTED_DEVELOPMENT_SIGNATURE=1` as release evidence. It is
only a diagnostic option for inspecting other bundle properties while a local
development certificate trust problem is being repaired.

## Current Validation Status

Snapshot from 2026-08-30:

| Goal gate | Current evidence | Remaining evidence |
| --- | --- | --- |
| Sandboxed manual import | App Store-shaped Release bundle builds and passes the structural verifier. Exact Apple distribution profiles are registered and installed. | Install the matching Apple Distribution private key, produce a trusted archive, then run a user-selected synthetic card import in the sandbox. |
| Bookmark persistence and revocation | Core tests prove exact group-path selection, fail-closed missing-group behavior, and one-for-one security-scope lifetime. | Relaunch, reinsertion, stale bookmark, and revoked-permission checks in a genuinely provisioned sandbox. |
| No scan before consent | The shared mount policy test proves the App Store edition reads no capacity, performs no media probe, and sends no distributed-notification handoff before consent. Both helper and observer use that policy. | Observe the helper/app flow with a synthetic card under the provisioned sandbox. |
| Sandboxed helper mailbox | Existing mailbox/causality tests plus App Group path tests pass. Both App IDs are assigned to the registered App Group. | End-to-end login-item wake and mailbox delivery from a trusted provisioned build. |
| StoreKit | Four app-hosted local StoreKit tests pass with no skips; core policy covers free allowance and cancellation. | Sandbox/TestFlight purchase and restore after the IAP exists in App Store Connect. |
| Both editions | 226 tests in 34 suites pass; direct and App Store Release builds succeed; direct Sparkle packaging and identifiers remain intact. | None locally. |
| Archive inspection | Local ad-hoc App Store bundle passes identifiers, universal binaries, sandbox entitlements, privacy manifests, product ID, helper placement, test-artifact exclusion, and no-Sparkle checks. The exact app/helper profiles are installed and contain the expected App IDs and App Group. | A trusted distribution archive. Xcode reports the selected Apple Distribution certificate as `Not in Keychain` on this Mac. |

The local Xcode Debug host used for StoreKit simulation currently reports an
invalid signed-entitlements blob, so it is deliberately not counted as sandbox
evidence. `REQUIRE_PROVISIONED_SIGNATURE=1` is the authoritative signing gate.

## Apple Account Setup

Completed in the Apple Developer account on 2026-08-30:

- Registered explicit App IDs `media.jenny.sdimport` and
  `media.jenny.sdimport.agent`.
- Registered `group.media.jenny.sdimport`, enabled App Groups for both App IDs,
  and assigned the exact group to both.
- Created and installed `SD Import for Mac App Store` and
  `SD Import Agent App Store` distribution profiles. Both expire 2027-07-03
  and contain the expected application identifier and App Group entitlements.

These owner actions remain and are intentionally not performed by build
scripts:

1. Install the private key for Apple Distribution certificate `YTAJ6D4BV2`,
   or explicitly authorize creation of a replacement Apple Distribution
   certificate and regenerate both profiles against it.
2. Create the macOS app record in App Store Connect with
   `media.jenny.sdimport`.
3. Create the non-consumable IAP `media.jenny.sdimport.unlimited`, including
   price, localization, review screenshot, and review notes.
4. Complete paid-app agreements, tax, and banking requirements before testing
   or selling the IAP.
5. Complete App Privacy, age rating, category, support URL, privacy URL,
   screenshots, description, and review contact fields from the shipped build's
   behavior.
6. Attach the IAP to the first app-version submission when App Store Connect
   requires it.
7. Publish the updated `docs/privacy.html` and `docs/support.html` before
   submission. The production URLs respond, but as of 2026-08-30 they still
   serve the pre-App-Store disclosures from 2026-07-31.

The release gate is an archive that passes the verifier without overrides, then
App Store Connect validation/TestFlight or sandbox testing, and finally the
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
- Confirm the App Store edition has no Sparkle UI, no source-eject controls, no
  legacy-state import, and no system crash-report browser.
- Reinsert the same card and confirm a new consent prompt appears before a new
  scan while the retained security-scoped permission still resolves correctly.
- Export and review redacted diagnostics; confirm no filenames or full paths
  are included.

Do not submit, upload, or publish until the owner explicitly authorizes that
external action.
