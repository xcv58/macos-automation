#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/SDImport"
PROJECT_PATH="$PROJECT_DIR/SDImportMacAppStore.xcodeproj"
SCHEME="SDImportForMac"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PROJECT_DIR/.derived-data-app-store}"
DIST_DIR="$ROOT_DIR/dist/app-store"
APP_NAME="SD Import for Mac"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
PACKAGING_DIR="$PROJECT_DIR/Packaging/MacAppStore"
APP_ENTITLEMENTS="$PACKAGING_DIR/SDImport.entitlements"
AGENT_ENTITLEMENTS="$PACKAGING_DIR/SDImportAgent.entitlements"
MODE="${1:-build}"
APP_VERSION="${APP_VERSION:-1.0}"
APP_BUILD="${APP_BUILD:-1}"

case "${BUILD_CONFIGURATION:-release}" in
  debug|Debug)
    CONFIGURATION="Debug"
    ;;
  release|Release)
    CONFIGURATION="Release"
    ;;
  *)
    echo "Unsupported BUILD_CONFIGURATION: ${BUILD_CONFIGURATION}" >&2
    exit 2
    ;;
esac

usage() {
  cat >&2 <<'EOF'
usage: ./script/build_app_store.sh [build|test]
EOF
}

build_staged_app() {
  DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
    xcodebuild build -quiet \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -configuration "$CONFIGURATION" \
      -destination 'platform=macOS' \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
      MARKETING_VERSION="$APP_VERSION" \
      CURRENT_PROJECT_VERSION="$APP_BUILD"

  local built_app="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
  local helper_bundle="$APP_BUNDLE/Contents/Library/LoginItems/SDImportAgent.app"
  test -d "$built_app"

  mkdir -p "$DIST_DIR"
  rm -rf "$APP_BUNDLE"
  /usr/bin/ditto "$built_app" "$APP_BUNDLE"

  /usr/bin/codesign --force --options runtime --sign - \
    --entitlements "$AGENT_ENTITLEMENTS" "$helper_bundle"
  /usr/bin/codesign --force --options runtime --sign - \
    --entitlements "$APP_ENTITLEMENTS" "$APP_BUNDLE"

  "$ROOT_DIR/script/verify_app_store_bundle.sh" "$APP_BUNDLE"
}

run_storekit_tests() {
  DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
    xcodebuild test -quiet \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -destination 'platform=macOS,arch=arm64' \
      -only-testing:SDImportStoreKitTests \
      -derivedDataPath "$DERIVED_DATA_PATH"
}

case "$MODE" in
  build)
    build_staged_app
    ;;
  test)
    run_storekit_tests
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
