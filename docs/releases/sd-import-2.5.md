# SD Import 2.5

## Changes

- Makes the automatic card prompt more reliable after updates, delayed app
  launches, closed or minimized windows, and background-helper registration
  problems.
- Repairs the background helper automatically with bounded retries, reducing
  the need to open SD Import twice or toggle the mount-prompt setting.
- Adds clearer background-helper status, diagnostics, and repair guidance in
  Settings.
- Adds optional portable import receipts so a source drive can remember files
  imported on another Mac without recording destination paths, usernames, or
  media contents.
- Labels files recognized through portable receipts as **Other Mac** and
  provides an explicit **Import Anyway** override.

## Notes

Portable import receipts are off by default and can be enabled in Settings.
Automatic prompting continues to require **Prompt when a card is mounted** to
be enabled.
