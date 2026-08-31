#!/usr/bin/env bash
set -euo pipefail

if [[ "${CONFIRM_CLEAN_MAS_QA_ACCOUNT:-0}" != "1" ]]; then
  printf '%s\n' \
    'Runtime QA uses the production MAS bundle identifier and updates its local sandbox state.' \
    'Run it only from a clean macOS QA account, with CONFIRM_CLEAN_MAS_QA_ACCOUNT=1.' >&2
  exit 64
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/SDImport/SDImportMacAppStore.xcodeproj"
RUNTIME_DERIVED_DATA="$(mktemp -d /private/tmp/SDImportMASRuntimeQA.XXXXXX)"
APP_BUNDLE="$RUNTIME_DERIVED_DATA/Build/Products/Debug/SD Import for Mac.app"
HELPER_BUNDLE="$APP_BUNDLE/Contents/Library/LoginItems/SDImportAgent.app"
DRIVER_BINARY="$RUNTIME_DERIVED_DATA/mas-runtime-qa-driver"

cleanup() {
  if [[ "$RUNTIME_DERIVED_DATA" == /private/tmp/SDImportMASRuntimeQA.* ]]; then
    rm -rf -- "$RUNTIME_DERIVED_DATA"
  fi
}
trap cleanup EXIT

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
  xcodebuild build -quiet \
    -project "$PROJECT_PATH" \
    -scheme SDImportForMac \
    -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$RUNTIME_DERIVED_DATA" \
    MARKETING_VERSION=1.0 \
    CURRENT_PROJECT_VERSION=1

test -d "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
[[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$APP_BUNDLE/Contents/Info.plist")" == "media.jenny.sdimport" ]]
[[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$HELPER_BUNDLE/Contents/Info.plist")" == "media.jenny.sdimport.agent" ]]

entitlements="$(/usr/bin/codesign -d --entitlements - "$APP_BUNDLE" 2>&1)"
[[ "$entitlements" == *"com.apple.security.app-sandbox"* ]]
[[ "$entitlements" == *"com.apple.security.files.user-selected.read-write"* ]]
[[ "$entitlements" == *"group.media.jenny.sdimport"* ]]
if [[ "$entitlements" == *"temporary-exception"* ]]; then
  echo "Runtime QA refused an app with XCTest temporary exception entitlements" >&2
  exit 1
fi

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
  xcrun swiftc \
    -parse-as-library \
    -module-cache-path "$RUNTIME_DERIVED_DATA/ModuleCache" \
    "$ROOT_DIR/script/mas_runtime_qa.swift" \
    -o "$DRIVER_BINARY"

"$DRIVER_BINARY" "$APP_BUNDLE"
