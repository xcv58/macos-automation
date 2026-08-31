#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/dist/app-store/SD Import for Mac.app}"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_INFO="$APP_CONTENTS/Info.plist"
APP_PRIVACY="$APP_CONTENTS/Resources/PrivacyInfo.xcprivacy"
AGENT_BUNDLE="$APP_CONTENTS/Library/LoginItems/SDImportAgent.app"
AGENT_CONTENTS="$AGENT_BUNDLE/Contents"
AGENT_INFO="$AGENT_CONTENTS/Info.plist"
AGENT_PRIVACY="$AGENT_CONTENTS/Resources/PrivacyInfo.xcprivacy"
PACKAGING_DIR="$ROOT_DIR/SDImport/Packaging/MacAppStore"
STOREKIT_CONFIG="$PACKAGING_DIR/SDImport.storekit"

fail() {
  echo "App Store bundle verification failed: $*" >&2
  exit 1
}

expect_file() {
  [[ -f "$1" ]] || fail "missing $1"
}

expect_directory() {
  [[ -d "$1" ]] || fail "missing $1"
}

plist_value() {
  /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null
}

expect_plist_value() {
  local file="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual="$(plist_value "$file" "$key")" || fail "missing $key in $file"
  [[ "$actual" == "$expected" ]] || fail "$key in $file is '$actual', expected '$expected'"
}

expect_absent_plist_key() {
  local file="$1"
  local key="$2"
  if /usr/bin/plutil -extract "$key" raw -o - "$file" >/dev/null 2>&1; then
    fail "$key must not be present in $file"
  fi
}

expect_universal_binary() {
  local binary="$1"
  local architectures
  architectures="$(/usr/bin/lipo -archs "$binary")" || fail "could not read architectures from $binary"
  [[ " $architectures " == *" arm64 "* ]] || fail "$binary is missing arm64"
  [[ " $architectures " == *" x86_64 "* ]] || fail "$binary is missing x86_64"
}

expect_file "$APP_INFO"
expect_file "$APP_PRIVACY"
expect_directory "$AGENT_BUNDLE"
expect_file "$AGENT_INFO"
expect_file "$AGENT_PRIVACY"
expect_file "$STOREKIT_CONFIG"
[[ ! -f "$AGENT_CONTENTS/Resources/SDImportAgentPrivacyInfo.xcprivacy" ]] \
  || fail "the helper privacy manifest has a nonstandard filename"

APP_BINARY="$APP_CONTENTS/MacOS/$(plist_value "$APP_INFO" CFBundleExecutable)"
AGENT_BINARY="$AGENT_CONTENTS/MacOS/$(plist_value "$AGENT_INFO" CFBundleExecutable)"
expect_file "$APP_BINARY"
expect_file "$AGENT_BINARY"
expect_universal_binary "$APP_BINARY"
expect_universal_binary "$AGENT_BINARY"

/usr/bin/plutil -lint "$APP_INFO" "$AGENT_INFO" "$APP_PRIVACY" "$AGENT_PRIVACY" >/dev/null
signature_output="$(/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1)" \
  || signature_status=$?
signature_status="${signature_status:-0}"
if [[ "$signature_status" != "0" ]]; then
  if
    [[ "${ALLOW_UNTRUSTED_DEVELOPMENT_SIGNATURE:-0}" == "1" ]] \
      && [[ "$signature_output" == *CSSMERR_TP_NOT_TRUSTED* ]]
  then
    echo "Warning: auditing an archive whose development signing certificate is not trusted." >&2
  else
    fail "code signature is invalid: $signature_output"
  fi
fi

expect_plist_value "$APP_INFO" CFBundleIdentifier media.jenny.sdimport
expect_plist_value "$APP_INFO" CFBundleDisplayName 'SD Import for Mac'
expect_plist_value "$APP_INFO" SDImportDistribution app-store
expect_plist_value "$APP_INFO" SDImportAppGroupIdentifier group.media.jenny.sdimport
expect_plist_value "$APP_INFO" LSApplicationCategoryType public.app-category.photography
expect_plist_value "$AGENT_INFO" CFBundleIdentifier media.jenny.sdimport.agent
expect_plist_value "$AGENT_INFO" SDImportDistribution app-store
expect_plist_value "$AGENT_INFO" SDImportMainBundleIdentifier media.jenny.sdimport
expect_plist_value "$AGENT_INFO" SDImportAppGroupIdentifier group.media.jenny.sdimport

for key in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks SUAllowsAutomaticUpdates; do
  expect_absent_plist_key "$APP_INFO" "$key"
done

if /usr/bin/find "$APP_BUNDLE" -iname '*sparkle*' -print -quit | /usr/bin/grep . >/dev/null; then
  fail "Sparkle content is present"
fi
if /usr/bin/find "$APP_BUNDLE" \( -name '*.storekit' -o -name '*.xctest' \) \
  -print -quit | /usr/bin/grep . >/dev/null; then
  fail "StoreKit development or test artifacts are present"
fi
if [[ -d "$APP_CONTENTS/Resources/SDImportAgent.app" ]]; then
  fail "the background helper is embedded outside Library/LoginItems"
fi
if /usr/bin/otool -L "$APP_BINARY" "$AGENT_BINARY" | /usr/bin/grep 'Sparkle.framework' >/dev/null; then
  fail "an executable links Sparkle"
fi
if /usr/bin/strings "$APP_BINARY" "$AGENT_BINARY" \
  | /usr/bin/grep -E 'SUFeedURL|SUPublicEDKey|Sparkle\.framework|SPUStandardUpdater' >/dev/null; then
  fail "an executable contains direct-edition Sparkle keys or symbols"
fi
if ! /usr/bin/strings "$APP_BINARY" | /usr/bin/grep -Fx 'media.jenny.sdimport.unlimited' >/dev/null; then
  fail "the main executable does not reference the reviewed lifetime product identifier"
fi

app_entitlements="$(mktemp /tmp/sdimport-app-entitlements.XXXXXX)"
agent_entitlements="$(mktemp /tmp/sdimport-agent-entitlements.XXXXXX)"
trap '/bin/rm -f "$app_entitlements" "$agent_entitlements"' EXIT

/usr/bin/codesign -d --entitlements - --xml "$APP_BUNDLE" >"$app_entitlements" 2>/dev/null
/usr/bin/codesign -d --entitlements - --xml "$AGENT_BUNDLE" >"$agent_entitlements" 2>/dev/null
[[ -s "$app_entitlements" ]] || fail "the main app has no readable signed entitlements"
[[ -s "$agent_entitlements" ]] || fail "the helper has no readable signed entitlements"
/usr/bin/plutil -lint "$app_entitlements" "$agent_entitlements" >/dev/null

expect_plist_value "$app_entitlements" 'com\.apple\.security\.app-sandbox' true
expect_plist_value "$app_entitlements" 'com\.apple\.security\.files\.user-selected\.read-write' true
expect_plist_value "$app_entitlements" 'com\.apple\.security\.application-groups.0' group.media.jenny.sdimport
expect_plist_value "$agent_entitlements" 'com\.apple\.security\.app-sandbox' true
expect_plist_value "$agent_entitlements" 'com\.apple\.security\.application-groups.0' group.media.jenny.sdimport
expect_absent_plist_key "$agent_entitlements" 'com\.apple\.security\.files\.user-selected\.read-write'

if /usr/bin/plutil -p "$app_entitlements" "$agent_entitlements" \
  | /usr/bin/grep 'temporary-exception' >/dev/null; then
  fail "temporary sandbox exceptions are present"
fi

if [[ "${REQUIRE_PROVISIONED_SIGNATURE:-0}" == "1" ]]; then
  app_profile="$APP_CONTENTS/embedded.provisionprofile"
  agent_profile="$AGENT_CONTENTS/embedded.provisionprofile"
  expect_file "$app_profile"
  expect_file "$agent_profile"

  app_profile_plist="$(mktemp /tmp/sdimport-app-profile.XXXXXX)"
  agent_profile_plist="$(mktemp /tmp/sdimport-agent-profile.XXXXXX)"
  trap '/bin/rm -f "$app_entitlements" "$agent_entitlements" "$app_profile_plist" "$agent_profile_plist"' EXIT
  /usr/bin/security cms -D -i "$app_profile" >"$app_profile_plist"
  /usr/bin/security cms -D -i "$agent_profile" >"$agent_profile_plist"

  expect_plist_value "$app_entitlements" 'com\.apple\.application-identifier' 5736QK4NZX.media.jenny.sdimport
  expect_plist_value "$app_entitlements" 'com\.apple\.developer\.team-identifier' 5736QK4NZX
  expect_plist_value "$agent_entitlements" 'com\.apple\.application-identifier' 5736QK4NZX.media.jenny.sdimport.agent
  expect_plist_value "$agent_entitlements" 'com\.apple\.developer\.team-identifier' 5736QK4NZX
  expect_plist_value "$app_profile_plist" 'Entitlements.com\.apple\.application-identifier' 5736QK4NZX.media.jenny.sdimport
  expect_plist_value "$agent_profile_plist" 'Entitlements.com\.apple\.application-identifier' 5736QK4NZX.media.jenny.sdimport.agent
  expect_plist_value "$app_profile_plist" 'Entitlements.com\.apple\.security\.application-groups.0' group.media.jenny.sdimport
  expect_plist_value "$agent_profile_plist" 'Entitlements.com\.apple\.security\.application-groups.0' group.media.jenny.sdimport

  if [[ "$(plist_value "$app_entitlements" 'com\.apple\.security\.get-task-allow' || true)" == "true" ]]; then
    fail "the main app has the development get-task-allow entitlement"
  fi
  if [[ "$(plist_value "$agent_entitlements" 'com\.apple\.security\.get-task-allow' || true)" == "true" ]]; then
    fail "the helper has the development get-task-allow entitlement"
  fi
fi

/usr/bin/cmp -s "$PACKAGING_DIR/PrivacyInfo.xcprivacy" "$APP_PRIVACY" \
  || fail "main privacy manifest differs from the reviewed source"
/usr/bin/cmp -s "$PACKAGING_DIR/SDImportAgentPrivacyInfo.xcprivacy" "$AGENT_PRIVACY" \
  || fail "helper privacy manifest differs from the reviewed source"

expect_plist_value "$STOREKIT_CONFIG" products.0.productID media.jenny.sdimport.unlimited
expect_plist_value "$STOREKIT_CONFIG" products.0.type NonConsumable
expect_plist_value "$STOREKIT_CONFIG" settings._developerTeamID 5736QK4NZX

echo "Verified Mac App Store bundle: $APP_BUNDLE"
