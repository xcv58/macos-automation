# SD Import Privacy Policy

Last updated: 2026-08-30

SD Import is a local macOS utility for copying photos and videos from SD cards
or selected source folders into user-selected destinations.

## Data SD Import Stores Locally

SD Import stores app settings, security-scoped folder bookmarks, import history,
and dedupe records on your Mac. The direct-download edition stores its database
under:

```text
~/Library/Application Support/SD Import/state.sqlite
```

It may also store ordinary app preferences through macOS `UserDefaults`. The
Mac App Store edition stores the same local data inside its macOS app container.
Its background helper and main app share only a sandboxed App Group mailbox used
to hand off mounted-volume events and helper health state.

The stored data can include:

- Source, photo destination, and video destination folder paths.
- Security-scoped bookmarks for selected folders.
- Import job history, counts, timestamps, and file-level records used to avoid
  duplicate imports.
- Workflow preferences such as history retention, theme, prompt-on-mount, and
  last-used import organization choices.

Imported photos and videos are copied to the destination folders you choose.
SD Import does not delete files from the source card.

If you enable `Store portable import receipts on source drives`, SD Import also
creates or appends a hidden `.sd-import/imported-v1.jsonl` file on writable
sources. It stores versioned file fingerprints, relative source paths, sizes,
modification timestamps, import timestamps, and validation checksums so another
Mac can avoid duplicate imports. It does not store destination paths, usernames,
or media contents in this portable ledger. The option is disabled by default,
and read-only sources continue without writing portable history. Ledger access
refuses symbolic-link redirection outside the selected source.

## Network Use

The direct-download edition uses the network for Sparkle update checks when
updates are configured. Those checks contact the GitHub Release-hosted appcast
for this repository. Sparkle is not included in the Mac App Store edition;
updates for that edition are delivered by the App Store.

The Mac App Store edition uses Apple's StoreKit service to load, purchase, and
restore the optional lifetime unlock. Apple processes the transaction. SD
Import does not operate an account or purchase server and does not receive your
payment details.

SD Import does not currently send analytics, telemetry, import history, media
files, folder listings, or crash reports to the maintainer. Diagnostics export
is opt-in and redacted.

## Removable Media Permission

The Mac App Store background helper may detect that a removable volume was
mounted, but it does not enumerate or scan the volume. The main app asks before
each newly detected card scan. If access has not already been granted, macOS
then presents a folder-access panel. Media enumeration begins only after both
steps are accepted. Folder access is retained locally as a security-scoped
bookmark and can be revoked through macOS privacy controls.

## Diagnostics And Crash Reports

SD Import does not include automatic crash-report upload. macOS may keep local
diagnostic or crash logs according to your system settings. If you report a bug,
you may choose what diagnostic details to share. The direct-download edition's
Diagnostics screen can reveal the local crash-report folder or export the
latest local SD Import crash report. The sandboxed Mac App Store edition does
not browse that system directory. Neither edition uploads crash reports for
you.

When sharing diagnostics, redact private folder names, filenames, camera serial
numbers, account names, and any media metadata you do not want public.

## Support Requests

Public GitHub issues are visible to everyone. Do not attach private photos,
videos, full card dumps, credentials, or unredacted logs to public issues.

Support email: [i@xcv58.com](mailto:i@xcv58.com)

## Changes

Privacy-impacting changes should be documented in this file before release.
