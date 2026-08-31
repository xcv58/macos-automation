#!/usr/bin/env bash
set -euo pipefail

if [[ "${CONFIRM_CLEAN_MAS_QA_ACCOUNT:-0}" != "1" ]]; then
  printf '%s\n' \
    'Helper QA registers the production MAS login item and updates its App Group state.' \
    'Run it only from a clean macOS QA account, with CONFIRM_CLEAN_MAS_QA_ACCOUNT=1.' >&2
  exit 64
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/SDImport/SDImportMacAppStore.xcodeproj"
RUNTIME_ROOT="$(mktemp -d /private/tmp/SDImportMASHelperRuntimeQA.XXXXXX)"
BUILT_APP="$RUNTIME_ROOT/Build/Products/Debug/SD Import for Mac.app"
BUILT_HELPER="$BUILT_APP/Contents/Library/LoginItems/SDImportAgent.app"
INSTALLED_APP="/Applications/SD Import for Mac Helper QA.app"
MOUNT_POINT="/Volumes/SDIMPORT_QA_CARD_CODEX"
DISK_IMAGE="$RUNTIME_ROOT/SDImportHelperQA.dmg"
DRIVER_BINARY="$RUNTIME_ROOT/mas-runtime-qa-driver"
PROFILE_PLIST="$RUNTIME_ROOT/profile.plist"
SIGNED_ENTITLEMENTS_PLIST="$RUNTIME_ROOT/signed-entitlements.plist"

fail() {
  echo "MAS helper runtime QA failed: $*" >&2
  exit 1
}

plist_value() {
  /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null
}

bundle_identifier() {
  plist_value "$1/Contents/Info.plist" CFBundleIdentifier
}

terminate_temporary_processes() {
  /usr/bin/pkill -f '^/Applications/SD Import for Mac Helper QA.app/Contents/MacOS/SD Import for Mac' \
    2>/dev/null || true
  /usr/bin/pkill -f '^media.jenny.sdimport.agent' 2>/dev/null || true
}

unregister_temporary_helper() {
  if [[ -d "$INSTALLED_APP" ]] \
    && [[ "$(bundle_identifier "$INSTALLED_APP" 2>/dev/null || true)" == media.jenny.sdimport ]]; then
    /usr/bin/open -W -na "$INSTALLED_APP" --args \
      --sdimport-helper-runtime-qa-unregister \
      -ApplePersistenceIgnoreState YES >/dev/null 2>&1 || true
  fi
  terminate_temporary_processes
}

cleanup() {
  unregister_temporary_helper

  if [[ -e "$MOUNT_POINT" ]]; then
    protocol="$(/usr/sbin/diskutil info -plist "$MOUNT_POINT" 2>/dev/null \
      | /usr/bin/plutil -extract BusProtocol raw -o - - 2>/dev/null || true)"
    if [[ "$protocol" == 'Disk Image' ]] \
      || /usr/sbin/diskutil info "$MOUNT_POINT" 2>/dev/null \
        | /usr/bin/grep -q 'Protocol:.*Disk Image'; then
      /usr/bin/hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi
  fi

  if [[ -d "$INSTALLED_APP" ]] \
    && [[ "$(bundle_identifier "$INSTALLED_APP" 2>/dev/null || true)" == media.jenny.sdimport ]]; then
    /bin/rm -rf -- "$INSTALLED_APP"
  fi
  if [[ "$RUNTIME_ROOT" == /private/tmp/SDImportMASHelperRuntimeQA.* ]]; then
    /bin/rm -rf -- "$RUNTIME_ROOT"
  fi
}
trap cleanup EXIT

[[ ! -e "$MOUNT_POINT" ]] || fail "$MOUNT_POINT already exists"
if [[ -e "$INSTALLED_APP" ]]; then
  [[ "$(bundle_identifier "$INSTALLED_APP" 2>/dev/null || true)" == media.jenny.sdimport ]] \
    || fail "refusing to replace an unrelated app at $INSTALLED_APP"
  unregister_temporary_helper
  /bin/rm -rf -- "$INSTALLED_APP"
fi

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
  /usr/bin/xcodebuild build -quiet \
    -project "$PROJECT_PATH" \
    -scheme SDImportForMac \
    -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$RUNTIME_ROOT" \
    MARKETING_VERSION=1.0 \
    CURRENT_PROJECT_VERSION=1

[[ -d "$BUILT_APP" ]] || fail "the Debug MAS app was not built"
[[ -d "$BUILT_HELPER" ]] || fail "the Debug MAS helper was not embedded"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$BUILT_APP"
[[ "$(bundle_identifier "$BUILT_APP")" == media.jenny.sdimport ]]
[[ "$(bundle_identifier "$BUILT_HELPER")" == media.jenny.sdimport.agent ]]

verify_development_profile() {
  local bundle="$1"
  local expected_application_identifier="$2"
  local profile="$bundle/Contents/embedded.provisionprofile"
  local signature_details

  [[ -f "$profile" ]] || fail "missing development profile in $bundle"
  /usr/bin/security cms -D -i "$profile" >"$PROFILE_PLIST" 2>/dev/null \
    || fail "could not decode the profile in $bundle"

  [[ "$(plist_value "$PROFILE_PLIST" 'Entitlements.com\.apple\.application-identifier')" \
    == "$expected_application_identifier" ]] \
    || fail "the profile in $bundle does not authorize $expected_application_identifier"
  [[ "$(plist_value "$PROFILE_PLIST" 'Entitlements.com\.apple\.security\.application-groups.0')" \
    == group.media.jenny.sdimport ]] \
    || fail "the profile in $bundle does not authorize group.media.jenny.sdimport"
  [[ "$(plist_value "$PROFILE_PLIST" 'Entitlements.com\.apple\.security\.get-task-allow')" \
    == true ]] \
    || fail "the profile in $bundle is not a runnable development profile"

  /usr/bin/codesign -d --entitlements - --xml "$bundle" >"$SIGNED_ENTITLEMENTS_PLIST" 2>/dev/null
  [[ "$(plist_value "$SIGNED_ENTITLEMENTS_PLIST" \
    'com\.apple\.security\.application-groups.0')" == group.media.jenny.sdimport ]] \
    || fail "$bundle is not signed for group.media.jenny.sdimport"
  [[ "$(plist_value "$SIGNED_ENTITLEMENTS_PLIST" \
    'com\.apple\.security\.get-task-allow')" == true ]] \
    || fail "$bundle is not signed as a runnable development build"
  signature_details="$(/usr/bin/codesign -d --verbose=4 "$bundle" 2>&1)"
  [[ "$signature_details" == *'Authority=Apple Development:'* ]] \
    || fail "$bundle is not signed by an Apple Development identity"
}

verify_development_profile "$BUILT_APP" 5736QK4NZX.media.jenny.sdimport
verify_development_profile "$BUILT_HELPER" 5736QK4NZX.media.jenny.sdimport.agent

/usr/bin/ditto "$BUILT_APP" "$INSTALLED_APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"

/usr/bin/hdiutil create \
  -size 8m \
  -fs HFS+ \
  -volname SDIMPORT_QA_CARD_CODEX \
  -ov "$DISK_IMAGE" >/dev/null
/usr/bin/hdiutil attach \
  -nobrowse \
  -mountpoint "$MOUNT_POINT" \
  "$DISK_IMAGE" >/dev/null
[[ -d "$MOUNT_POINT" ]] || fail "the isolated QA disk image did not mount"
/usr/bin/touch "$MOUNT_POINT/QA_PLACEHOLDER.JPG"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
  /usr/bin/xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$RUNTIME_ROOT/ModuleCache" \
    "$ROOT_DIR/script/mas_runtime_qa.swift" \
    -o "$DRIVER_BINARY"

"$DRIVER_BINARY" helper "$INSTALLED_APP" "$MOUNT_POINT"
echo 'The OS mount detector was intentionally bypassed after detection; a physical removable-card gate remains.'
