# SD Import Manual QA Matrix

Use this checklist before major public releases and whenever scanner/import
behavior changes.

A focused physical-card pass is available for source ejection from a built-in
SD reader. Broader camera and failure-path coverage still relies on fixtures and
the remaining hardware matrix below.

Release decision for this pass:

- TestFlight Build 5 closes the Build 4 release blocker. On 2026-09-04, two
  physical `Untitled` reinsertion cycles woke the exact `/Applications`
  TestFlight app, presented the no-scan consent sheet, and completed without
  the former Swift exclusivity crash. The second cycle continuously recorded
  consent, scan, review, a 996.3 MB import, rescan, and eject.
- Focused built-in-reader passes are complete for manual ejection after an
  error-free import and after a zero-copy scan.
- Physical Sony/Canon/Fujifilm/Nikon compatibility QA remains unavailable.
- Fixture coverage exists for common RAW extensions, RAW/JPEG pairing, sidecar
  handling, duplicate filename planning, and card-removal failure paths.
- Broad camera-compatibility claims should wait until the hardware matrix below
  is actually run.
- The capture script is ready for future physical-card evidence.

Use the capture script for each mounted card before filling in the manual app
results:

```bash
./script/capture_manual_card_qa.sh \
  --volume /Volumes/CARD \
  --scenario "Canon photo card" \
  --output /tmp/sdimport-canon-photo-card-qa.md
```

The capture report omits filenames and full paths. Review it before sharing or
committing any excerpt.

## Mac App Store Runtime Passes

| Scenario | Expected Result | Status |
| --- | --- | --- |
| Public App Store support and privacy pages | The canonical marketing, support, and privacy URLs load over HTTPS and contain the current App Store disclosures; legacy URLs embedded in Build 4 remain usable | Passed 2026-09-04. Production deployment `dpl_4AKHwD2jY6EqXHNcr6MmwQR1kWCz` is Ready on the existing Vercel project and is aliased to `https://sd.jenny.media/`. The home page now serves five distinct exact-TestFlight-Build-5 states: insertion consent, review-ready plan, genuine copy progress, successful receipt with named eject, and a `Nothing New` rescan. Its continuous 126.516667-second H.264/yuv420p video is 1920 x 1156 at a constant 60 fps, retains the real system pointer and click highlights, and removes only pre-workflow waiting time plus the macOS menu/title strip. The owner-visible originals are opaque 3024 x 1820 RGB PNGs with 640, 1200, and 1920-pixel WebP variants. Browser verification showed the new images without an embedded black canvas, loaded the video at its expected dimensions and duration, and confirmed the Build 5 and `Nothing New` copy. Home, privacy, support, sampled responsive images, and the MP4 returned HTTP 200 with the expected content types; the video response was 5,689,399 bytes. The canonical Privacy and Support pages both contain `sd@jenny.media`. Preview deployment `dpl_EcUfKLJHnkrorVAVzRpHHSqkxYd9` was Ready and content-verified before production promotion. The legacy aliases remain attached, preserving Build 4's embedded support and privacy links. |
| App Store screenshot asset capture | Produce accepted-size images without personal media or the prohibited source, including a purchase image with localized price and a clean completed-import receipt | Passed for capture and App Store Connect upload 2026-09-03. Five opaque 2560 x 1600 PNGs were uploaded in this order: exact-TestFlight-Build-4 synthetic file preview, destination plan, lifetime purchase sheet, successful receipt reporting 2 copied, 0 skipped, and 0 failed, and Settings showing `Background helper: Running` plus `Lifetime access unlocked`. The Build 4 plan, file, receipt, and Settings images were captured window-only, so they contain neither the remote-control indicator nor a black canvas. The purchase capture was reframed to 16:10 and only the external remote-control indicator in the otherwise blank titlebar area was removed; product UI was not altered. The IAP review screenshot was also replaced with an opaque JPEG re-encoding of that same purchase capture and visually verified without black framing. Both imported synthetic JPEGs matched their sources byte-for-byte by SHA-256. The purchase sheet is not a processed-TestFlight purchase capture because the TestFlight account already owns the product. A later physical Build 4 run supplied the missing consent-prompt and named-eject marketing images; the already-submitted App Store gallery was not changed. `Sandisk 4T` was not used. |
| App Store Connect 1.0 submission and compliance | Save the required app-version, privacy, pricing, review, IAP, and EU trader information, then submit the explicitly authorized app/IAP pair | Passed and corrected 2026-09-04. The saved metadata, five App Store screenshots, `sd@jenny.media` review contact, manual release, Photo & Video plus Utilities categories, 4+ age rating, trader status, Data Not Collected privacy answer, 175-country availability, and worldwide Family Sharing-enabled non-consumable remain unchanged. After the Build 4 insertion crash, the original submission `adc08664-db2c-4d3b-93bb-d77d1caf6284` was removed, Build 5 was selected, and the app plus `SD Import Unlimited` were resubmitted under `2f1632a6-a99f-4fba-99ff-3c443bd68523`. Both items report `Waiting for Review`. |
| Development-provisioned sandbox import | With no temporary exceptions, authorize a synthetic card and destination through real macOS folder panels, scan one JPEG, complete the import, and verify the copied output | Passed 2026-08-31 with `media.jenny.sdimport`: App Sandbox, user-selected read/write, and App Group entitlements were present; source scan, destination selection, import completion, and output verification passed |
| Source bookmark relaunch | Relaunch the same sandboxed app without another folder panel, restore the synthetic source bookmark, and scan again | Passed 2026-08-31; the persisted source path returned, Scan Card was enabled, no open panel appeared, and the second scan reached review |
| TestFlight lifetime purchase persistence | Complete the no-charge TestFlight purchase, verify unlimited access, quit and relaunch, then verify the entitlement is restored without waiting for product metadata; Restore Purchases must return promptly and must not authenticate when the verified entitlement is already available | Passed on TestFlight Builds 2 through 5. Build 2 first proved the existing Build 1 purchase appeared immediately, Restore Purchases returned in about 1.4 seconds without authentication, and cold-relaunch recovery took about 1.1 seconds. Build 3 returned restore in 689 ms and recovered the unlock by 2.090 seconds including navigation. Build 4 returned restore in 715 ms and recovered the unlock by 2.200 seconds including navigation. Exact installed Build 5 showed `Lifetime access unlocked` and `Background helper: Running` immediately; Restore Purchases returned in 241 ms without an authentication sheet, and a cold reopen showed both states in Settings within 1.188 seconds including navigation. Builds 3 through 5 were compiled with accepted Xcode 26.6, distribution-signed with the exact profiles, strictly verified, uploaded, processed, and assigned to `IQ Internal QA`. Seven deterministic commerce tests and six app-hosted StoreKit tests pass. These active-entitlement passes did not put the live transaction into a revoked state; live sandbox Family Sharing grant/revoke QA remains. |
| Family-shared lifetime unlock | Enable Family Sharing for the production non-consumable, share it through a StoreKit sandbox family, and verify a family member gains and loses unlimited-import access as the verified shared entitlement changes | Strong non-live evidence completed 2026-09-01; live sandbox-family grant/revoke remains untested and must not be called passed. Source review confirms verified `Transaction.currentEntitlements` grants the product without excluding `.familyShared` ownership, checks `revocationDate`, observes verified transaction updates, re-resolves the complete entitlement set on revocation, and prevents a stale `Transaction.latest` snapshot from regranting access after a running manager loses its current entitlement. Seven focused orchestration tests and six app-hosted StoreKit tests passed, including Family Sharing metadata, purchase, restore, refund/revocation, pending, failed verification, and stale-latest protection. If suitable sandbox-family accounts remain impractical, ship only by explicitly accepting the residual risk that Apple's live family-shared delivery and revoke propagation, including a fresh launch after revoke, were not exercised. |
| App Store destination defaults | Start without saved destination bookmarks, scan media, and verify the app presents a clear authorization step instead of treating a sandbox-container path as a usable media destination | Failed in TestFlight Build 3 on 2026-09-01. The video fallback resolved to `/Users/yihong/Library/Containers/media.jenny.sdimport/Data/Downloads`; Review displayed `Permission needed` and disabled import until a destination was selected. Passed in exact TestFlight Build 4 on 2026-09-01. On first launch, both Settings defaults were empty and displayed `Choose a folder`; scanning an isolated 71,349-byte synthetic JPEG reached Review with an empty photo destination, a clear `Choose a destination folder` prompt, and Import disabled. Selecting a separate temporary destination through `NSOpenPanel` enabled Import. `Use as Defaults` persisted that security-scoped destination; after a cold relaunch, Settings restored it as `Ready` by 2.200 seconds without another panel while the unselected video destination correctly remained empty. The import reported 1 copied, 0 skipped, and 0 failed; source and copy SHA-256 values both equaled `f9acd8b029aa526537ac260b526043f9344840788ad3fc41474e753c16f631ef`, and the rescan reported `Nothing New`. The edition-policy test, all 235 core tests, 7 commerce orchestration tests, and 6 hosted StoreKit tests also pass. |
| Synthetic helper handoff and decline | Register the real embedded helper, inject one event after removable-volume eligibility, persist it through the App Group mailbox, wake the containing app, verify the explicit no-scan consent sheet, choose `Don't Scan`, and observe no folder or review UI | Passed through Build 5. Exact installed Build 5 Settings reported `Background helper: Running`; `sfltool dumpbtm` showed enabled/allowed/notified sandboxed login item `media.jenny.sdimport.agent`, parent identifier `media.jenny.sdimport`, and parent URL `/Applications/SD Import for Mac.app`. The installed app and helper both report build 5, Team `5736QK4NZX`, `TestFlight Beta Distribution`, and strict deep-signature validity. Physical reinsertion independently proved the helper woke that exact path and presented the no-scan consent sheet. Earlier Builds 2 through 4 supplied the synthetic mailbox and stale-registration coverage. |
| Physical App Store card and helper | Quit the main app, insert a removable card, verify the helper wakes it without enumeration, decline consent with no scan, then accept consent and reuse or refresh folder authorization | Passed on exact TestFlight Build 5 on 2026-09-04, extending the Build 3 and Build 4 passes. With the app quit, physical `Untitled` insertion launched `/Applications/SD Import for Mac.app/Contents/MacOS/SD Import for Mac` and presented `SD Import detected this removable volume but has not scanned its contents.` No scan or review occurred before consent. `Don't Scan` returned to the authorized source without enumeration; a later reinsertion plus `Allow Scan` automatically selected only `/Volumes/Untitled/SDImport-Build5-Demo`. Only isolated synthetic media was used, and `Sandisk 4T` was not used or unmounted. |
| Physical insertion re-entrancy | Deliver overlapping foreground-app and helper occurrences for one physical mount | Passed on exact TestFlight Build 5 on 2026-09-04. Two physical `Untitled` reinsertion cycles woke the quit app and reached the consent sheet without a crash; the second continued through scan, import, rescan, and eject. This closes the Build 4 `Fatal access conflict detected` incident `FE0C0C60-536D-42DC-A883-16C25F337C32`. The reference-type delivery controller and nested-delivery regression test remain the source-level guard. |
| Physical App Store source eject | In the exact signed sandboxed MAS build, verify the named eject action before scan, after scan, and on a successful receipt, then invoke it from the receipt | Passed on exact TestFlight Build 5 on 2026-09-04, extending the prior signed-build passes. Eject was available before scanning, on Review before import, on the successful receipt, and after the zero-copy rescan. The first Build 5 run copied 27/27 synthetic files totaling 996.2 MB with zero failures; the continuous take copied another 27 new synthetic files totaling 996.3 MB while recognizing 27 known files. Both destination sets matched their respective sources byte-for-byte with zero SHA-256 mismatches. Rescan reported `Nothing New`; the final Eject action unmounted `/Volumes/Untitled` while `/Volumes/Sandisk 4T` remained mounted. The owner-observed Insta360 pass remains the evidence for multi-volume same-device ejection. |
| Bookmark revocation and stale refresh | Revoke folder permission or exercise a stale bookmark, relaunch, and confirm a controlled repair panel with no preauthorization scan | Deterministic policy coverage proves the MAS edition refuses stale bookmarks while the direct edition retains refresh behavior; clean-account UI validation remains required before App Store submission |

## Required Hardware Passes

| Scenario | Card Contents | Expected Result | Status |
| --- | --- | --- | --- |
| Sony video card | `PRIVATE/M4ROOT`, MP4/MOV clips, `MEDIAPRO.XML`, `DATABASE.BIN`, sidecars | Index files ignored; footage backup recommended; sidecars visible and opt-in | Accepted risk: hardware unavailable; fixture coverage exists for index-file ignore and sidecar behavior |
| Canon photo card | JPEG plus CR2 and CR3 files | Photo import recommended; CR2/CR3 classified as photos; RAW/JPEG pairs summarized when basenames match | Accepted risk: hardware unavailable; fixture coverage exists |
| Fujifilm photo card | RAF plus JPEG files | Photo import recommended; RAF classified as photo; known files skipped on rescan | Accepted risk: hardware unavailable; fixture coverage exists |
| Nikon photo card | NEF plus JPEG files | Photo import recommended; NEF classified as photo; known files skipped on rescan | Accepted risk: hardware unavailable; fixture coverage exists |
| Mixed RAW/JPEG | Matching RAW and JPEG basenames in the same folder | RAW+JPEG pair count appears; both files remain importable | Fixture coverage exists; hardware unavailable |
| Video sidecars | Video clips with XML/metadata/proxy files | Footage Backup shows sidecar count; sidecars stay skipped unless kept | Fixture coverage exists; hardware unavailable |
| Duplicate filenames | Two camera folders containing the same clip filename | Destination plan suffixes later copies and avoids overwrites | Fixture coverage exists; hardware unavailable |
| Card removal during scan | Remove card after scan starts | User-facing failure; no duplicate job loop | Fixture coverage exists; hardware unavailable |
| Card removal during import | Remove card during copy | Failed file recorded; retry remains available | Fixture coverage exists; hardware unavailable |
| Manual source eject | Complete an error-free import, then choose the named eject action on the receipt | The whole source volume unmounts; the receipt says `Ejected — Safe to Remove`; destination files remain accessible | Direct pass 2026-07-22: 11 of 11 files (200.1 MB) copied, then the built-in-reader source ejected. Exact signed sandboxed MAS pass 2026-08-31: 1 JPEG copied byte-for-byte, then `SD Card` ejected. |
| Automatic source eject | Enable `Eject source device after a successful import`, then complete an error-free import | The verified removable source device ejects only after the receipt and report are finalized | Passed in TestFlight Build 3 on 2026-09-01 with `Untitled`. A second isolated 126,799-byte synthetic JPEG was the only new file; the receipt finalized as 1 copied, 1 skipped, and 0 failed, then showed `Untitled ejected. Safe to remove.` The destination SHA-256 `97e7b5930e4fc3137c1d720fd26c50b09a681d1088ffb120835f56c3fc3683b6` matched the pre-import source hash exactly. The opt-in setting was restored to off after the test. |
| Multi-volume camera detection | Connect a camera that exposes internal storage and a memory card as separate disks | Both volumes are direct, one-click source choices labeled with the same physical device | Topology confirmed 2026-07-25 with DJI Pocket hardware: `Untitled` on one whole disk and `Pocket4` on a second whole disk share one DJI USB-device registry identity |
| Multi-volume camera eject | Import from either storage volume, then choose the device eject action | Every whole disk belonging to the verified physical device unmounts before the UI says the camera is safe to disconnect | Passed on TestFlight Build 3 on 2026-09-01 in an owner-observed Insta360 hardware run. The selected `Internal` source presented a device-level Eject action; the import copied 15 videos totaling 6.7 GB, skipped 17 support files, and failed 0. The receipt reported `Insta360 Luna Ultra Ejected — Safe to Remove`, and the owner confirmed that the multiple card volumes belonging to that physical device were ejected. Screenshots document the review and receipt; the agent did not independently enumerate the device's disks before and after this run. |
| Partial multi-volume eject failure | Keep one camera volume busy, then eject the grouped device | No force-eject occurs; the app identifies any volume already ejected and the volume that remains mounted | Fixture coverage required; confirm with hardware when practical |
| Eject blocked by another app | Keep a source file open in another app, then request ejection | macOS refusal is shown in SD Import; the source remains mounted; no force-eject occurs | Passed in TestFlight Build 3 on 2026-09-01 using an independent process whose working directory was the isolated synthetic source folder on `Untitled`. Build 3 reported `Could not eject source: Untitled remains mounted` with OSStatus error `-47`, offered Retry and Back to Source, and did not force-eject. `/dev/disk10s1` remained mounted at `/Volumes/Untitled` as removable Secure Digital media. The temporary hold was then released and the app returned to the ready source screen with Eject still available. |
| Import completed with errors | Enable automatic ejection, then produce a retryable copy failure | The source remains mounted and retry stays available | Fixture policy coverage exists; confirm with hardware before release |
| Source subfolder | Select a folder inside the mounted card as the source, import, then eject | SD Import ejects the card's volume root rather than only the selected folder | Passed on exact TestFlight Build 4 on 2026-09-03. The selected source was `/Volumes/Untitled/SDImport-Website-Demo`; after the 27-file import, the receipt's named device action unmounted `/Volumes/Untitled` and reported `Untitled Ejected — Safe to Remove`. |
| Built-in card reader | Import from a card that macOS reports as both internal-location and removable | The verified removable card remains eligible and ejects normally | Passed 2026-07-22 with a removable Secure Digital source reported at an internal device location |
| Ejection completion UI | Complete a clean import, then eject from the copy receipt | The named source has a prominent eject action; success changes to a green `Ejected — Safe to Remove` confirmation | Passed 2026-07-22 with direct source `Untitled`; passed 2026-08-31 in the exact signed sandboxed MAS build with source `SD Card` |
| Zero-copy scan ejection | Scan a verified removable card whose files are all known or excluded | The Source panel offers manual ejection; automatic ejection does not run | Passed 2026-07-22: user confirmed the manual zero-copy eject flow; automatic ejection was not exercised |
| Skip-copy scan ejection | Scan a verified removable source with files available to copy, then choose eject instead of import | The Source panel keeps manual ejection available beside `Scan Again`, copies no files, and automatic ejection does not run | Passed 2026-07-25 with DJI Pocket hardware: user confirmed the persistent Source-panel eject action worked without starting the copy |
| Clean Mac user | Fresh user account, no prior settings | Onboarding appears; folders can be selected; Sparkle menu appears in release build | Accepted risk: clean-user manual pass unavailable |
| Old-to-new update (2.6 UI candidate) | Install 2.5 (41), update through Sparkle, and confirm the app relaunches as 2.6 (42) | Sparkle downloads, verifies, installs, and relaunches the signed app; the bundled helper remains build 42 | Passed 2026-08-13: the installed 2.5 (41) app found 2.6, displayed the published release notes, downloaded the update, installed it, and relaunched as 2.6 (42). The bundled helper is build 42, Settings reports `Background helper: Running`, and the installed app's deep code signature verifies. |
| Auto-prompt upgrade | Enable mount prompting in the previous public release, update through Sparkle, then mount one importable card while the app is closed | The updated helper build matches the app, Settings reports Running without toggling, and one visible prompt appears without opening the app manually | Accepted risk for the 2.5 (41) candidate on 2026-08-02: the original field failure cannot be reproduced locally and a physical old-to-new pass is unavailable. Automated coverage verifies helper identity/build repair, scheduled missing/nonlaunching-helper retries, stale-agent rejection, durable occurrence-identified handoff retry, causal health errors, atomic stale-copy preference preservation, and process-lifetime closed-window presentation. Ask the affected user to confirm after release; retain this as a required gate for future background-prompt releases when suitable hardware is available. |
| Auto-prompt hidden app | Hide or minimize SD Import, then mount one importable card | The existing main window activates and presents exactly one prompt | Required before releasing background-prompt changes |
| Auto-prompt closed window | Close the last SD Import main window without quitting, then mount one importable card | SD Import creates a new main window and presents exactly one prompt without a second manual launch | Required before releasing background-prompt changes |
| Auto-prompt approval repair | Disable SD Import in System Settings Login Items while the saved preference remains enabled | Settings shows Needs approval and opens the correct Login Items pane; reapproval restores Running without toggling twice | Required before releasing background-prompt changes |
| Auto-prompt missing registration | Leave the saved preference enabled, unregister the helper, then relaunch SD Import | The bundled helper is registered again once for the current build; Settings returns to Running without toggling the preference | Required before releasing background-prompt changes |
| Auto-prompt active retry | Leave the installed app active with the saved preference enabled, force the helper into missing or nonlaunching state, and do not close/reopen the app | Registration or helper repair retries after the bounded cooldown and returns to Running without another activation or preference toggle | Automated retry scheduler and causal policy coverage exists; physical validation required for a future background-prompt release |
| Auto-prompt same-build re-enable | Disable and re-enable mount prompting without changing the app build, then prevent the newly registered helper from launching | Settings does not reuse the earlier launch record as proof of health; the nonlaunching-helper repair starts after the bounded health timeout | Automated precise launch-epoch coverage includes a pre-attempt launch in the same wall-clock second; physical validation required for a future background-prompt release |
| Auto-prompt retry cooldown across activation | Force `.notFound` or `.notRegistered`, let an explicit enable, manual repair, or reconciliation registration attempt fail, then repeatedly reactivate the app during the cooldown | No entry point or activation bypasses the persisted cooldown; one retry is attempted when the bounded delay expires | Automated missing-registration policy coverage exists; physical validation required for a future background-prompt release |
| Auto-prompt same-path card swap | Keep an import or prompt active, mount one card at `/Volumes/CARD`, replace it with another card that reuses that path, then finish the blocking work | The durable mailbox retains two occurrence IDs; the current mounted card receives a prompt and cross-origin observations are coalesced only when their volume UUID matches | Automated durable-queue, one-to-one cross-origin correlation, and post-media-probe UUID revalidation coverage exists; physical validation required for a future background-prompt release |
| Auto-prompt multiple app copies | Keep an older same-build or previous-build copy running outside `/Applications`, install the current copy in `/Applications`, then try the toggle and mount one importable card | The uninstalled copy says `Managed by installed copy`, cannot mutate the helper, and only the authoritative installed copy activates with exactly one prompt | Required before releasing background-prompt changes |
| Auto-prompt stale-copy settings save | Open an uninstalled copy before enabling prompting in the installed copy, then change an unrelated path or theme in the stale copy | The unrelated setting saves, but the installed copy's shared auto-prompt preference remains enabled | Automated atomic two-writer repository coverage exists; physical validation required for a future background-prompt release |
| Auto-prompt installation authority | Test copies in `/Applications`, `~/Applications`, Downloads, and a mounted DMG, including a renamed installed copy | `/Applications/SD Import.app` wins deterministically, then another matching app in `/Applications`, then `~/Applications`; an uninstalled-only copy says `Install required` | Required before releasing background-prompt changes |
| Auto-prompt causal errors | Queue an older successful handoff, then force a newer helper launch or mailbox failure before the old event is acknowledged | The newer error remains visible until a later event succeeds; the older acknowledgement does not erase it | Required before releasing background-prompt changes |

## Recorded Ejection Evidence

- Date: 2026-07-22.
- Build: SD Import 2.2 (31), local ad-hoc test build.
- Reader: built-in Secure Digital reader; macOS reported the removable card at
  an internal device location.
- Source: `Untitled`, 512.64 GB capacity.
- Successful-import pass: 11 of 11 files copied, 200.1 MB total, zero failures;
  the named manual eject action unmounted the source and showed the safe-removal
  confirmation.
- Date: 2026-07-25.
- Build: SD Import 2.3 (39), local ad-hoc test build.
- Device: DJI Pocket camera exposing `Pocket4` and `Untitled` as separate whole
  disks under one USB-device identity.
- Multi-volume manual pass: both storage volumes appeared as direct source
  choices; the grouped source action ejected the physical device without
  starting the available copy. The post-import receipt path was not separately
  exercised on this hardware.
- Zero-copy pass: the user confirmed that a completed scan with zero files
  planned for copying offered manual ejection and successfully ejected the
  source.
- Not recorded for the 2026-07-25 pass: macOS version, Mac model, card brand,
  filesystem, automatic ejection, blocked ejection, copy-failure behavior, and
  source subfolder behavior.
- Date: 2026-08-31.
- Build: exact signed development-provisioned Mac App Store Debug build with
  production sandbox, user-selected read/write, and App Group entitlements and
  no temporary exceptions.
- Reader: built-in Secure Digital reader; source `SD Card`, removable ExFAT.
- App Store pass: the named eject control appeared before scan, after scan, and
  on the successful receipt. One synthetic JPEG copied byte-for-byte, two
  support files were skipped, and zero files failed. The receipt action
  unmounted the source and changed to `SD Card ejected. Safe to remove.`
- Not recorded for the App Store pass: macOS version, Mac model, card brand,
  automatic ejection, blocked ejection, copy-failure behavior, and source
  subfolder behavior.

## Evidence To Record

For each hardware pass, record:

- SD Import version and build.
- macOS version and Mac model.
- Camera/card brand and reader type.
- Filesystem, usually exFAT or FAT32.
- Whether import was automatic or manual.
- Preview counts: new, known, sidecars, conflicts.
- Final result: imported, skipped, failed.
- Any diagnostics export or crash report path, if relevant.
- The redacted output from `script/capture_manual_card_qa.sh`, if useful.

Do not commit private media, full card dumps, private filenames, or unredacted
diagnostics.
