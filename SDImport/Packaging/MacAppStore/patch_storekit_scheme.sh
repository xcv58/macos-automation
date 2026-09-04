#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCHEME="$ROOT_DIR/SDImportMacAppStore.xcodeproj/xcshareddata/xcschemes/SDImportForMac.xcscheme"

test -f "$SCHEME"

if sed -n '/<TestAction/,/<\/TestAction>/p' "$SCHEME" | grep -q StoreKitConfigurationFileReference; then
  exit 0
fi

perl -0pi -e '
  s{(<TestAction\b.*?)(\s*</TestAction>)}
   {$1\n      <StoreKitConfigurationFileReference identifier="../../Packaging/MacAppStore/SDImport.storekit">\n      </StoreKitConfigurationFileReference>$2}s
' "$SCHEME"

sed -n '/<TestAction/,/<\/TestAction>/p' "$SCHEME" | grep -q StoreKitConfigurationFileReference
