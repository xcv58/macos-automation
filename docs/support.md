# SD Import Support

Support email: [i@xcv58.com](mailto:i@xcv58.com)

Public bugs and feature requests should use GitHub Issues:

https://github.com/xcv58/sd-import/issues

Do not attach private photos, videos, full card dumps, credentials, or
unredacted logs to public issues.

## What To Include

- SD Import version and build.
- macOS version and Mac model.
- Camera/card brand, filesystem, and reader type.
- Whether import was automatic or manually started.
- What the preview showed before import.
- What happened after import.
- A redacted diagnostics export when useful.

## Diagnostics Export

Diagnostics export is opt-in from `Diagnostics > Export Diagnostics` or
`Diagnostics > Copy Diagnostics`.

The export includes app version, macOS version, settings status, recent job
counts, and selected-job file statuses. It excludes media files, file names, and
full source/destination paths.

Review the export before sharing it.

## Card Mount Prompt Troubleshooting

Settings shows the current macOS background-helper state next to `Prompt when a
card is mounted`.

In the Mac App Store edition, the helper detects the mount without scanning the
card. The main app asks whether to scan and, when needed, macOS separately asks
you to allow folder access. Cancelling either prompt leaves the card unscanned.

- `Running`: the helper is registered, matches the installed app, and has
  launched since the latest enable or repair attempt.
- `Install required`: move SD Import into `/Applications` or
  `~/Applications`. Copies launched from Downloads, a mounted DMG, or another
  folder cannot own the background helper.
- `Managed by installed copy`: choose `Open Installed Copy`. The copy in
  `/Applications` takes precedence over `~/Applications`; within either folder,
  the canonical `SD Import.app` name takes precedence over renamed copies.
- `Needs attention`: read the detail shown below the status, then choose
  `Repair`. Runtime launch and handoff failures stay visible until a later
  card handoff succeeds.
- `Needs approval`: choose `Open Login Items`, then allow SD Import under
  System Settings > General > Login Items & Extensions.
- `Not registered` or `Helper update needed`: leave the installed app running
  while it retries registration and helper launch with a bounded cooldown. If
  the state remains after the retry window, choose `Repair`.
- `Helper missing`: install the latest SD Import in `/Applications` and remove
  older copies or mounted installer-disk copies.

If the state does not return to `Running`, export diagnostics before changing
the setting so support can see the actual macOS helper status, ownership, build,
last launch, last handoff, and last runtime error. Closing the last main window
is supported: a later card mount should create a new main window and present the
prompt without requiring a second manual launch. Mounts observed while an
import or another prompt is active are kept in a durable queue. Card swaps that
reuse the same `/Volumes/...` path remain separate queue entries.

## Purchase And Restore

The Mac App Store edition includes one successfully completed import for free.
Previewing a card does not consume it. Use `Settings > Purchase > Restore
Purchases` to restore the lifetime unlock for the current Apple ID. Pending,
cancelled, unverified, refunded, or revoked transactions do not unlock imports.

## Crash Reports

SD Import does not upload crash reports automatically.

If the app crashes, macOS may store a local crash report under:

```text
~/Library/Logs/DiagnosticReports/
```

In the direct-download edition, use `Diagnostics > Reveal Crash Reports` to
open the folder, or `Diagnostics > Export Latest Crash Report` to save the
newest local SD Import report for support. The sandboxed Mac App Store edition
does not browse the system crash-report directory; open the path manually in
Finder if support asks for a report.

Only share crash reports you have reviewed. Redact private folder names,
filenames, card names, serial numbers, and any media metadata you do not want to
share.
