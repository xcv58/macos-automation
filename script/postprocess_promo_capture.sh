#!/usr/bin/env bash
set -euo pipefail

INPUT_PATH=""
OUTPUT_PATH=""
OUTPUT_WIDTH=1920
OUTPUT_FPS=60
CROP_TOP=67
CRF=17
KEEP_RANGES=()
CLICK_MARKERS=()

usage() {
  cat <<'USAGE'
usage: ./script/postprocess_promo_capture.sh --input RAW.mov --output PREVIEW.mp4 \
  --keep START:END[:SPEED] [--keep START:END[:SPEED] ...] \
  [--click TIME:X:Y ...]

Creates a high-quality, web-compatible promo preview from a native macOS screen
recording. Keep ranges use source-video seconds. An optional SPEED greater than
1 gently time-compresses that range while preserving every decoded frame. Click
markers use seconds in the edited output plus output-pixel coordinates.

Options:
  --input PATH          Native screen recording.
  --output PATH         MP4 preview to create.
  --keep START:END[:SPEED]
                        Source interval to retain; optionally accelerate it.
                        Repeat for additional cuts (default speed: 1).
  --click TIME:X:Y      Add a subtle click ring; repeat for each genuine click.
  --crop-top PIXELS     Remove the macOS menu bar while preserving the app
                        title bar and window controls (default: 67).
  --width PIXELS        Output width (default: 1920).
  --fps FPS             Output frame rate (default: 60).
  --crf VALUE           H.264 quality value (default: 17).
  -h, --help            Show this help.

Example:
  ./script/postprocess_promo_capture.sh \
    --input /private/tmp/sd-import-promo-raw.mov \
    --output /private/tmp/sd-import-promo-preview.mp4 \
    --keep 2.0:12.5 --keep 18.0:24.0:1.5 --keep 24.0:42.0 \
    --click 4.8:1143:615 --click 15.0:1784:42
USAGE
}

fail() {
  echo "postprocess_promo_capture: $*" >&2
  exit 1
}

is_number() {
  [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      [[ $# -ge 2 ]] || fail "--input requires a path"
      INPUT_PATH="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || fail "--output requires a path"
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --keep)
      [[ $# -ge 2 ]] || fail "--keep requires START:END"
      KEEP_RANGES+=("$2")
      shift 2
      ;;
    --click)
      [[ $# -ge 2 ]] || fail "--click requires TIME:X:Y"
      CLICK_MARKERS+=("$2")
      shift 2
      ;;
    --crop-top)
      [[ $# -ge 2 ]] || fail "--crop-top requires pixels"
      CROP_TOP="$2"
      shift 2
      ;;
    --width)
      [[ $# -ge 2 ]] || fail "--width requires pixels"
      OUTPUT_WIDTH="$2"
      shift 2
      ;;
    --fps)
      [[ $# -ge 2 ]] || fail "--fps requires a value"
      OUTPUT_FPS="$2"
      shift 2
      ;;
    --crf)
      [[ $# -ge 2 ]] || fail "--crf requires a value"
      CRF="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -n "$INPUT_PATH" ]] || fail "--input is required"
[[ -f "$INPUT_PATH" ]] || fail "input file not found: $INPUT_PATH"
[[ -n "$OUTPUT_PATH" ]] || fail "--output is required"
[[ ${#KEEP_RANGES[@]} -gt 0 ]] || fail "at least one --keep range is required"
[[ "$CROP_TOP" =~ ^[0-9]+$ ]] || fail "crop-top must be a non-negative integer"
[[ "$OUTPUT_WIDTH" =~ ^[0-9]+$ ]] || fail "width must be a positive integer"
[[ "$OUTPUT_FPS" =~ ^[0-9]+$ ]] || fail "fps must be a positive integer"
[[ "$CRF" =~ ^[0-9]+$ ]] || fail "crf must be an integer"

command -v ffmpeg >/dev/null 2>&1 || fail "ffmpeg is required"
command -v ffprobe >/dev/null 2>&1 || fail "ffprobe is required"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/sdimport-promo-post.XXXXXX")"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

filter_script="$work_dir/filter.txt"
filter=""
total_duration=0

for index in "${!KEEP_RANGES[@]}"; do
  range="${KEEP_RANGES[$index]}"
  start="${range%%:*}"
  range_tail="${range#*:}"
  end="${range_tail%%:*}"
  speed="1"
  if [[ "$range_tail" == *:* ]]; then
    speed="${range_tail#*:}"
  fi
  [[ "$start" != "$range" ]] || fail "invalid keep range: $range"
  is_number "$start" || fail "invalid keep start: $start"
  is_number "$end" || fail "invalid keep end: $end"
  is_number "$speed" || fail "invalid keep speed: $speed"
  awk -v start="$start" -v end="$end" 'BEGIN { exit !(end > start) }' \
    || fail "keep range end must be greater than start: $range"
  awk -v speed="$speed" 'BEGIN { exit !(speed > 0) }' \
    || fail "keep speed must be greater than zero: $range"
  total_duration="$(awk -v total="$total_duration" -v start="$start" -v end="$end" -v speed="$speed" 'BEGIN { printf "%.6f", total + (end - start) / speed }')"
  filter+="[0:v]trim=start=$start:end=$end,setpts=(PTS-STARTPTS)/$speed,crop=iw:ih-$CROP_TOP:0:$CROP_TOP,scale=$OUTPUT_WIDTH:-2:flags=lanczos,fps=$OUTPUT_FPS,format=yuv420p[k$index];"
done

if [[ ${#KEEP_RANGES[@]} -eq 1 ]]; then
  filter+="[k0]null[base];"
else
  for index in "${!KEEP_RANGES[@]}"; do
    filter+="[k$index]"
  done
  filter+="concat=n=${#KEEP_RANGES[@]}:v=1:a=0[base];"
fi

ffmpeg_inputs=(-i "$INPUT_PATH")
final_label="base"

if [[ ${#CLICK_MARKERS[@]} -gt 0 ]]; then
  command -v magick >/dev/null 2>&1 || fail "ImageMagick's magick command is required for click rings"
  ring_path="$work_dir/click-ring.png"
  magick -size 72x72 xc:none \
    -fill 'rgba(10,132,255,0.10)' \
    -stroke '#0A84FF' \
    -strokewidth 4 \
    -draw 'circle 36,36 36,7' \
    "$ring_path"
  ffmpeg_inputs+=(-loop 1 -i "$ring_path")

  if [[ ${#CLICK_MARKERS[@]} -eq 1 ]]; then
    filter+="[1:v]format=rgba[r0];"
  else
    filter+="[1:v]format=rgba,split=${#CLICK_MARKERS[@]}"
    for index in "${!CLICK_MARKERS[@]}"; do
      filter+="[r$index]"
    done
    filter+=";"
  fi

  previous_label="base"
  for index in "${!CLICK_MARKERS[@]}"; do
    marker="${CLICK_MARKERS[$index]}"
    marker_time="${marker%%:*}"
    remainder="${marker#*:}"
    marker_x="${remainder%%:*}"
    marker_y="${remainder#*:}"
    [[ "$marker_time" != "$marker" && "$marker_x" != "$remainder" ]] || fail "invalid click marker: $marker"
    is_number "$marker_time" || fail "invalid click time: $marker_time"
    [[ "$marker_x" =~ ^[0-9]+$ ]] || fail "invalid click x coordinate: $marker_x"
    [[ "$marker_y" =~ ^[0-9]+$ ]] || fail "invalid click y coordinate: $marker_y"
    ring_start="$(awk -v time="$marker_time" 'BEGIN { value = time - 0.15; if (value < 0) value = 0; printf "%.3f", value }')"
    ring_end="$(awk -v time="$marker_time" 'BEGIN { printf "%.3f", time + 0.40 }')"
    filter+="[$previous_label][r$index]overlay=x=$marker_x-36:y=$marker_y-36:enable='between(t,$ring_start,$ring_end)'[o$index];"
    previous_label="o$index"
  done
  final_label="$previous_label"
fi

filter="${filter%;}"
printf '%s\n' "$filter" > "$filter_script"
mkdir -p "$(dirname "$OUTPUT_PATH")"

ffmpeg -y -v error \
  "${ffmpeg_inputs[@]}" \
  -filter_complex_script "$filter_script" \
  -map "[$final_label]" \
  -an \
  -c:v libx264 \
  -preset slow \
  -crf "$CRF" \
  -profile:v high \
  -level 4.2 \
  -pix_fmt yuv420p \
  -movflags +faststart \
  -t "$total_duration" \
  "$OUTPUT_PATH"

ffmpeg -v error -i "$OUTPUT_PATH" -f null -
ffprobe -v error \
  -show_entries format=duration,size \
  -show_entries stream=codec_name,width,height,r_frame_rate,avg_frame_rate,pix_fmt \
  -of default=noprint_wrappers=1 \
  "$OUTPUT_PATH"
