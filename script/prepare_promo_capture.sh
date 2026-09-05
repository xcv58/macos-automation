#!/usr/bin/env bash
set -euo pipefail

FIXTURE_PATH="${SDIMPORT_PROMO_FIXTURE_PATH:-${HOME}/Pictures/SD Import Capture Fixture}"
DESTINATION_PATH="${SDIMPORT_PROMO_DESTINATION_PATH:-${HOME}/Pictures/SD Import Library}"
VOLUME_PATH="/Volumes/Untitled"
RUN_ID="$(date -u '+%Y%m%d-%H%M%S')"
LOCAL_ONLY=false

usage() {
  cat <<'USAGE'
usage: ./script/prepare_promo_capture.sh [options]

Validates the reusable synthetic promo fixture and prepares one uniquely named,
isolated source folder on the mounted Untitled test card. The script never
deletes or overwrites card contents.

Options:
  --local-only          Validate the fixture and create the destination only.
  --volume PATH         Mounted test-card path (default: /Volumes/Untitled).
  --fixture PATH        Reusable synthetic fixture directory.
  --destination PATH    Realistic user-selected destination directory.
  --run-id ID           Unique suffix for this capture (letters, digits, ._-).
  -h, --help            Show this help.
USAGE
}

fail() {
  echo "prepare_promo_capture: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local-only)
      LOCAL_ONLY=true
      shift
      ;;
    --volume)
      [[ $# -ge 2 ]] || fail "--volume requires a path"
      VOLUME_PATH="$2"
      shift 2
      ;;
    --fixture)
      [[ $# -ge 2 ]] || fail "--fixture requires a path"
      FIXTURE_PATH="$2"
      shift 2
      ;;
    --destination)
      [[ $# -ge 2 ]] || fail "--destination requires a path"
      DESTINATION_PATH="$2"
      shift 2
      ;;
    --run-id)
      [[ $# -ge 2 ]] || fail "--run-id requires a value"
      RUN_ID="$2"
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

[[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]] || fail "run id may contain only letters, digits, period, underscore, and hyphen"

require_command find
require_command shasum
require_command stat

[[ -d "$FIXTURE_PATH" ]] || fail "fixture directory not found: $FIXTURE_PATH"
[[ -f "$FIXTURE_PATH/.sdimport-promo-fixture" ]] || fail "fixture marker missing: $FIXTURE_PATH/.sdimport-promo-fixture"
[[ -d "$FIXTURE_PATH/Photos" ]] || fail "fixture Photos directory missing"
[[ -d "$FIXTURE_PATH/Videos" ]] || fail "fixture Videos directory missing"

photo_count="$(find "$FIXTURE_PATH/Photos" -type f ! -name '.*' | wc -l | tr -d ' ')"
video_count="$(find "$FIXTURE_PATH/Videos" -type f ! -name '.*' | wc -l | tr -d ' ')"
[[ "$photo_count" -gt 0 ]] || fail "fixture contains no photos"
[[ "$video_count" -gt 0 ]] || fail "fixture contains no videos"

mkdir -p "$DESTINATION_PATH"

if [[ "$LOCAL_ONLY" == true ]]; then
  printf 'Synthetic fixture ready: %s photos, %s videos\n' "$photo_count" "$video_count"
  printf 'Capture destination ready: %s\n' "$DESTINATION_PATH"
  exit 0
fi

require_command diskutil
require_command dot_clean

[[ "$VOLUME_PATH" == /Volumes/* ]] || fail "volume must be an explicit path directly under /Volumes"
[[ "$(basename "$VOLUME_PATH")" != "Sandisk 4T" ]] || fail "refusing to use Sandisk 4T"
[[ "$(basename "$VOLUME_PATH")" == "Untitled" ]] || fail "this capture workflow requires the dedicated Untitled test card"
[[ -d "$VOLUME_PATH" ]] || fail "test card is not mounted: $VOLUME_PATH"

diskutil_info="$(diskutil info "$VOLUME_PATH")"
printf '%s\n' "$diskutil_info" | grep -Eq 'Removable Media:[[:space:]]+(Yes|Removable)' \
  || fail "volume is not reported as removable media"

source_root="$VOLUME_PATH/SDImport-Promo-$RUN_ID"
media_root="$source_root/DCIM/100PROMO"
[[ ! -e "$source_root" ]] || fail "capture source already exists; choose a new run id: $source_root"

mkdir -p "$media_root"

shopt -s nullglob
photo_index=1
for source_file in "$FIXTURE_PATH/Photos"/*; do
  [[ -f "$source_file" ]] || continue
  extension="${source_file##*.}"
  extension="$(printf '%s' "$extension" | tr '[:lower:]' '[:upper:]')"
  printf -v target_name 'SAMPLE_%s_%04d.%s' "$RUN_ID" "$photo_index" "$extension"
  COPYFILE_DISABLE=1 COPY_EXTENDED_ATTRIBUTES_DISABLE=1 cp -p "$source_file" "$media_root/$target_name"
  photo_index=$((photo_index + 1))
done

video_index=1
for source_file in "$FIXTURE_PATH/Videos"/*; do
  [[ -f "$source_file" ]] || continue
  extension="${source_file##*.}"
  extension="$(printf '%s' "$extension" | tr '[:lower:]' '[:upper:]')"
  printf -v target_name 'SAMPLE_%s_%04d.%s' "$RUN_ID" "$video_index" "$extension"
  COPYFILE_DISABLE=1 COPY_EXTENDED_ATTRIBUTES_DISABLE=1 cp -p "$source_file" "$media_root/$target_name"
  video_index=$((video_index + 1))
done
shopt -u nullglob

dot_clean -m "$source_root"

appledouble_count="$(find "$source_root" -type f -name '._*' | wc -l | tr -d ' ')"
[[ "$appledouble_count" -eq 0 ]] || fail "AppleDouble sidecars remain after cleanup: $appledouble_count"

copied_count="$(find "$media_root" -type f ! -name '._*' | wc -l | tr -d ' ')"
expected_count=$((photo_count + video_count))
[[ "$copied_count" -eq "$expected_count" ]] || fail "copied $copied_count files; expected $expected_count"

manifest_dir="${TMPDIR:-/tmp}/SDImport-Promo-$RUN_ID"
mkdir -p "$manifest_dir"
manifest_path="$manifest_dir/source-sha256.txt"
(
  cd "$media_root"
  find . -type f ! -name '._*' -print | LC_ALL=C sort | xargs shasum -a 256
) > "$manifest_path"

total_bytes="$(find "$media_root" -type f ! -name '._*' -exec stat -f '%z' {} \; | awk '{ total += $1 } END { print total + 0 }')"

printf 'Promo source ready: %s\n' "$source_root"
printf 'Synthetic media: %s files (%s photos, %s videos), %s bytes\n' "$copied_count" "$photo_count" "$video_count" "$total_bytes"
printf 'Capture destination: %s\n' "$DESTINATION_PATH"
printf 'Shoot name: Sample Shoot\n'
printf 'SHA-256 manifest: %s\n' "$manifest_path"
