#!/bin/bash
set -euo pipefail
app=${1:?Usage: scripts/notarize.sh path/to/application.app}
profile=${SCREENER_NOTARY_PROFILE:-renoir-notary}
work=$(mktemp -d "${TMPDIR:-/tmp}/screener-notary.XXXXXX")
trap 'rm -rf "$work"' EXIT
ditto -c -k --keepParent "$app" "$work/application.zip"
xcrun notarytool submit "$work/application.zip" --keychain-profile "$profile" --wait --output-format json > "$work/result.json"
python3 - "$work/result.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit(f"Apple rejected notarization: {result.get('status')}; submission {result.get('id')}")
print('Apple accepted notarization.')
PY
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose "$app"
