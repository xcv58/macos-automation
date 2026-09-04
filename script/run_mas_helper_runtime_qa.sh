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
INSTALLED_APP="/Applications/SD Import for Mac Helper QA.app"
APPROVAL_RECEIPT="/private/tmp/SDImportMASHelperApprovalReceipt.plist"
PREPARE_APPROVAL="${PREPARE_MAS_HELPER_QA_APPROVAL:-0}"
RESUME_AFTER_APPROVAL="${RESUME_MAS_HELPER_QA_AFTER_APPROVAL:-0}"
PRESERVE_APPROVAL_STATE=0
if [[ "$RESUME_AFTER_APPROVAL" == "1" ]]; then
  PRESERVE_APPROVAL_STATE=1
  BUILT_APP="$INSTALLED_APP"
else
  BUILT_APP="$RUNTIME_ROOT/Build/Products/Debug/SD Import for Mac.app"
fi
BUILT_HELPER="$BUILT_APP/Contents/Library/LoginItems/SDImportAgent.app"
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

code_directory_hash() {
  /usr/bin/codesign -d --verbose=4 "$1" 2>&1 \
    | /usr/bin/awk -F= '$1 == "CDHash" { print $2; exit }'
}

file_sha256() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{ print $1 }'
}

terminate_temporary_app() {
  /usr/bin/pkill -f '^/Applications/SD Import for Mac Helper QA.app/Contents/MacOS/SD Import for Mac' \
    2>/dev/null || true
}

terminate_temporary_processes() {
  terminate_temporary_app
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
  if [[ -e "$MOUNT_POINT" ]]; then
    protocol="$(/usr/sbin/diskutil info -plist "$MOUNT_POINT" 2>/dev/null \
      | /usr/bin/plutil -extract BusProtocol raw -o - - 2>/dev/null || true)"
    if [[ "$protocol" == 'Disk Image' ]] \
      || /usr/sbin/diskutil info "$MOUNT_POINT" 2>/dev/null \
        | /usr/bin/grep -q 'Protocol:.*Disk Image'; then
      /usr/bin/hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi
  fi

  if [[ "$PRESERVE_APPROVAL_STATE" == "1" ]]; then
    terminate_temporary_app
    if [[ "$RUNTIME_ROOT" == /private/tmp/SDImportMASHelperRuntimeQA.* ]]; then
      /bin/rm -rf -- "$RUNTIME_ROOT"
    fi
    if [[ -d "$INSTALLED_APP" ]]; then
      echo "Preserved $INSTALLED_APP and its Login Items registration for explicit approval." >&2
    fi
    return
  fi

  unregister_temporary_helper
  if [[ -d "$INSTALLED_APP" ]] \
    && [[ "$(bundle_identifier "$INSTALLED_APP" 2>/dev/null || true)" == media.jenny.sdimport ]]; then
    /bin/rm -rf -- "$INSTALLED_APP"
  fi
  /bin/rm -f -- "$APPROVAL_RECEIPT"
  if [[ "$RUNTIME_ROOT" == /private/tmp/SDImportMASHelperRuntimeQA.* ]]; then
    /bin/rm -rf -- "$RUNTIME_ROOT"
  fi
}
trap cleanup EXIT

[[ "$PREPARE_APPROVAL" == "0" || "$PREPARE_APPROVAL" == "1" ]] \
  || fail 'PREPARE_MAS_HELPER_QA_APPROVAL must be 0 or 1'
[[ "$RESUME_AFTER_APPROVAL" == "0" || "$RESUME_AFTER_APPROVAL" == "1" ]] \
  || fail 'RESUME_MAS_HELPER_QA_AFTER_APPROVAL must be 0 or 1'
[[ "$PREPARE_APPROVAL" != "1" || "$RESUME_AFTER_APPROVAL" != "1" ]] \
  || fail 'prepare and resume approval modes are mutually exclusive'
[[ ! -e "$MOUNT_POINT" ]] || fail "$MOUNT_POINT already exists"

if [[ "$RESUME_AFTER_APPROVAL" == "1" ]]; then
  [[ -d "$INSTALLED_APP" ]] || fail "the preserved QA app is missing at $INSTALLED_APP"
  [[ -f "$APPROVAL_RECEIPT" ]] || fail "the approval receipt is missing; rerun prepare mode"
  [[ "$(bundle_identifier "$INSTALLED_APP" 2>/dev/null || true)" == media.jenny.sdimport ]] \
    || fail "the preserved QA app has the wrong bundle identifier"
  expected_head="$(plist_value "$APPROVAL_RECEIPT" GitHead)"
  actual_head="$(/usr/bin/git -C "$ROOT_DIR" rev-parse HEAD)"
  [[ "$actual_head" == "$expected_head" ]] \
    || fail "the checkout changed after approval preparation; rerun prepare mode"
  [[ "$(code_directory_hash "$INSTALLED_APP")" \
    == "$(plist_value "$APPROVAL_RECEIPT" AppCDHash)" ]] \
    || fail "the preserved QA app changed after approval preparation"
  [[ "$(code_directory_hash "$BUILT_HELPER")" \
    == "$(plist_value "$APPROVAL_RECEIPT" HelperCDHash)" ]] \
    || fail "the preserved QA helper changed after approval preparation"
  [[ "$(file_sha256 "$ROOT_DIR/script/mas_runtime_qa.swift")" \
    == "$(plist_value "$APPROVAL_RECEIPT" DriverSHA256)" ]] \
    || fail "the helper QA driver changed after approval preparation"
  [[ "$(file_sha256 "$ROOT_DIR/script/run_mas_helper_runtime_qa.sh")" \
    == "$(plist_value "$APPROVAL_RECEIPT" WrapperSHA256)" ]] \
    || fail "the helper QA wrapper changed after approval preparation"
elif [[ -e "$INSTALLED_APP" ]]; then
  [[ "$(bundle_identifier "$INSTALLED_APP" 2>/dev/null || true)" == media.jenny.sdimport ]] \
    || fail "refusing to replace an unrelated app at $INSTALLED_APP"
  unregister_temporary_helper
  /bin/rm -rf -- "$INSTALLED_APP"
  /bin/rm -f -- "$APPROVAL_RECEIPT"
fi

if [[ "$RESUME_AFTER_APPROVAL" != "1" ]]; then
  DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
    /usr/bin/xcodebuild build -quiet \
      -project "$PROJECT_PATH" \
      -scheme SDImportForMac \
      -configuration Debug \
      -destination 'platform=macOS,arch=arm64' \
      -derivedDataPath "$RUNTIME_ROOT" \
      MARKETING_VERSION=1.0 \
      CURRENT_PROJECT_VERSION=1
fi

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
  [[ -n "$(plist_value "$PROFILE_PLIST" 'ProvisionedDevices.0')" ]] \
    || fail "the profile in $bundle is not a device-scoped development profile"

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

if [[ "$RESUME_AFTER_APPROVAL" != "1" ]]; then
  /usr/bin/ditto "$BUILT_APP" "$INSTALLED_APP"
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"

if [[ "$PREPARE_APPROVAL" == "1" ]]; then
  [[ -z "$(/usr/bin/git -C "$ROOT_DIR" status --porcelain)" ]] \
    || fail 'approval preparation requires a clean worktree so the preserved build is reproducible'
  /usr/bin/plutil -create xml1 "$APPROVAL_RECEIPT"
  /usr/bin/plutil -insert GitHead -string \
    "$(/usr/bin/git -C "$ROOT_DIR" rev-parse HEAD)" "$APPROVAL_RECEIPT"
  /usr/bin/plutil -insert AppCDHash -string \
    "$(code_directory_hash "$INSTALLED_APP")" "$APPROVAL_RECEIPT"
  /usr/bin/plutil -insert HelperCDHash -string \
    "$(code_directory_hash "$INSTALLED_APP/Contents/Library/LoginItems/SDImportAgent.app")" \
    "$APPROVAL_RECEIPT"
  /usr/bin/plutil -insert DriverSHA256 -string \
    "$(file_sha256 "$ROOT_DIR/script/mas_runtime_qa.swift")" "$APPROVAL_RECEIPT"
  /usr/bin/plutil -insert WrapperSHA256 -string \
    "$(file_sha256 "$ROOT_DIR/script/run_mas_helper_runtime_qa.sh")" "$APPROVAL_RECEIPT"
  /usr/bin/open -na "$INSTALLED_APP" --args \
    --sdimport-helper-runtime-qa-prepare \
    -ApplePersistenceIgnoreState YES >/dev/null
  /bin/sleep 3
  terminate_temporary_app
  PRESERVE_APPROVAL_STATE=1
  printf '%s\n' \
    'Prepared the exact signed helper for approval; this is not a completed QA result.' \
    'In System Settings > General > Login Items & Extensions, allow SDImportAgent.' \
    'Then rerun with RESUME_MAS_HELPER_QA_AFTER_APPROVAL=1 and the same confirmation variable.'
  exit 0
fi

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

driver_arguments=(helper "$INSTALLED_APP" "$MOUNT_POINT")
if [[ "$RESUME_AFTER_APPROVAL" == "1" ]]; then
  driver_arguments+=(--registration-already-approved)
fi
if ! "$DRIVER_BINARY" "${driver_arguments[@]}"; then
  echo 'Current macOS Background Task Management record for the MAS helper:' >&2
  /usr/bin/sfltool dumpbtm 2>/dev/null \
    | /usr/bin/grep -B 8 -A 4 'Identifier: 4\.media\.jenny\.sdimport\.agent' >&2 \
    || true
  fail 'signed helper runtime driver did not complete; a disabled disposition requires explicit Login Items approval'
fi
PRESERVE_APPROVAL_STATE=0
echo 'The OS mount detector was intentionally bypassed after detection; a physical removable-card gate remains.'
