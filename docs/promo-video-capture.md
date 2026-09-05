# SD Import Promo Video Capture

This runbook keeps website demo recordings repeatable across app builds while
preserving a genuine macOS interaction: one native pointer, real pointer motion,
real progress, and click rings added only at genuine clicks.

## Fixed creative direction

- Target: SD Import website.
- Length: about 30-40 seconds.
- Output: H.264 MP4, 1920 pixels wide, 60 fps, `yuv420p`, fast-start enabled.
- Source card: the dedicated removable volume named `Untitled` only.
- Never use `Sandisk 4T`.
- Source media: the isolated synthetic fixture only.
- Destination: `~/Pictures/SD Import Library`, authorized through the macOS
  folder picker.
- Shoot name: `Sample Shoot`.
- Pointer: record the real macOS pointer and its complete movement. Keep any UI
  automation pointer outside the retained crop.
- Click treatment: a subtle Apple-blue ring around each genuine click, added in
  post-production.

## Storyboard and pacing

| Target time | Story beat | Maximum static hold |
| --- | --- | ---: |
| 0-3s | Fresh app/desktop state; inserting the card wakes SD Import | 2s |
| 3-7s | Permission prompt; pointer moves to **Allow Scan** | 2s |
| 7-11s | Genuine scan progress | none |
| 11-15s | Review shows `Sample Shoot`, 27 files, size, and destination | 3s |
| 15-28s | Pointer clicks Import; genuine copy progress remains continuous | none |
| 28-34s | Successful receipt | 3s |
| 34-40s | Pointer moves to Eject, clicks it, and successful ejection appears | 3s |

Remove idle waits longer than three seconds. Do not replace real scan/copy
progress with checkpoint stills, and do not cut backward from a receipt to a
previous review state.

## One-time local preparation

The large reusable fixture intentionally lives outside Git:

```text
~/Pictures/SD Import Capture Fixture/
  .sdimport-promo-fixture
  Photos/
  Videos/
```

Validate it and create the realistic destination before inserting the card:

```bash
./script/prepare_promo_capture.sh --local-only
```

The fixture currently contains 24 synthetic photos and 3 synthetic videos,
about 1 GB total. It is separate from the import destination.

## Prepare a fresh card source

After mounting the dedicated test card, create a new run-specific source:

```bash
./script/prepare_promo_capture.sh \
  --volume "/Volumes/Untitled" \
  --run-id "build-N-take-1"
```

The script:

- refuses `Sandisk 4T` and any volume not named `Untitled`;
- requires the volume to be reported as removable;
- creates a new `SDImport-Promo-RUN_ID/DCIM/100PROMO` directory;
- never deletes or overwrites existing card contents;
- copies and uniquely renames the 27 synthetic files;
- writes a SHA-256 source manifest under the system temporary directory.

Use the printed `SDImport-Promo-RUN_ID` directory as the app's source. A new run
ID is required for every retake so the preview starts with new files even when
the app's import history is retained.

## App preflight before recording

1. Verify the installed app build and quit any other SD Import copy.
2. Select `~/Pictures/SD Import Library` through the macOS folder picker. Do not
   type or inject the path directly; the Mac App Store build needs a real
   security-scoped bookmark.
3. Set **Photos + Videos**, **Same Library**, **By Capture Date**, and
   `Sample Shoot`, then choose **Use as Defaults**.
4. Select the new run-specific source without scanning it.
5. Return to a clean source-ready state, safely eject `Untitled`, and quit the
   main app. Do not clear import history or other user data.
6. Confirm the background helper is running so physical insertion can wake the
   app.

This preflight may require one setup insertion followed by a physical
remove/reinsert for the final recording.

## Native recording

### Select the capture display

Display numbers can change when a monitor is connected, disconnected, or made
the main display. Calibrate immediately before every take:

```bash
screencapture -D 1 /private/tmp/sd-import-display-1.png
screencapture -D 2 /private/tmp/sd-import-display-2.png
sips -g pixelWidth -g pixelHeight /private/tmp/sd-import-display-*.png
```

Open the calibration images and identify the display containing the SD Import
window. Pass that display number explicitly with `-D`; do not rely on whichever
display macOS currently considers the main display. Recalibrate after any
display-arrangement change.

If an external display causes the helper-launched app to reopen on a different
display, either move the app and verify its restored placement after a complete
quit/relaunch or disconnect the external display for the take. The known-good
Build 5 capture used the built-in Retina display as the sole display
(`3024 x 1964`), which macOS numbered as display 1:

Use a bounded native capture and include the hardware insertion, app wake,
permission prompt, scan, review, copy, receipt, and eject in one continuous raw
take whenever possible:

```bash
screencapture -v -C -D 1 -V 120 /private/tmp/sd-import-promo-raw.mov
```

Record pointer movement at a natural pace. Pause briefly over each target before
clicking. Keep the native pointer on the recorded display before capture begins.
Do not use simulated pointer artwork or checkpoint screenshots.

## Post-production

First inspect the raw take and note the source ranges worth retaining. A keep
range may optionally end with a playback-speed multiplier, such as
`18.0:24.0:1.5`; this time-compresses slow pointer travel while retaining the
decoded frames. Specify click markers in the edited-output timeline and
output-pixel coordinates:

```bash
./script/postprocess_promo_capture.sh \
  --input /private/tmp/sd-import-promo-raw.mov \
  --output /private/tmp/sd-import-promo-preview.mp4 \
  --keep 2.0:15.0 \
  --keep 18.0:24.0:1.5 \
  --keep 24.0:46.0 \
  --click 4.8:1143:615 \
  --click 16.2:1784:42 \
  --click 36.0:1710:149
```

The example times are illustrative; measure every new raw take. The processor
crops 67 Retina pixels from the top by default, removing the macOS menu bar
while preserving the app title bar and window controls. It scales with Lanczos,
preserves 60 fps, overlays 72-pixel click rings, decodes the complete result to
detect errors, and prints final stream metadata.

The known-good Build 5 take used these source ranges after trimming the opening
hold to 1.5 seconds:

```bash
./script/postprocess_promo_capture.sh \
  --input /private/tmp/sd-import-promo-raw-take5.mov \
  --output /private/tmp/sd-import-promo-preview-take5.mp4 \
  --keep 2767.3:2775 \
  --keep 2818:2823.5:1.5 \
  --keep 2823.5:2837:1.25 \
  --keep 2864.5:2869:1.5 \
  --keep 2869:2873 \
  --click 1.5:1142:666 \
  --click 11.3:1795:91 \
  --click 24.8:516:416
```

## Review gate

Before touching website assets:

1. Inspect a full-resolution frame from every story beat.
2. Inspect frames immediately before, during, and after every click ring.
3. Confirm there is exactly one pointer throughout.
4. Confirm `Sample Shoot` and the realistic destination are visible.
5. Confirm scan and copy progress are continuous rather than still-frame jumps.
6. Confirm the receipt transitions forward into the eject action.
7. Show the `/private/tmp` preview to the user and wait for approval.

Only after approval should the preview replace website media or be committed.
