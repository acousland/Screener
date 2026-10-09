#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-env.sh
repo=${SCREENER_REPO:-acousland/Screener}
version=$(tr -d '[:space:]' < VERSION)
key=${SCREENER_SPARKLE_KEY_FILE:-.secrets/sparkle-private-key}
if [[ ${SCREENER_LOCAL_SPARKLE:-0} == 1 ]]; then signer=${SCREENER_SPARKLE_BIN:-Vendor/sparkle-bin}/sign_update;
else signer=.build/artifacts/sparkle/Sparkle/bin/sign_update; fi
# All checks run before creating or changing any GitHub objects.
python3 - "$repo" "$version" <<'PY'
import json, sys
from pathlib import Path
manifest = json.loads(Path('dist/release.json').read_text())
if manifest['repository'] != sys.argv[1] or manifest['version'] != sys.argv[2]:
    raise SystemExit('Prepared artifacts do not match the requested repository/version.')
if not manifest['developerIDSignedAndNotarized']:
    raise SystemExit('Development archives cannot be published as a release. Run scripts/prepare-release.sh with Developer ID signing first.')
PY
swift scripts/verify-update-key.swift "$key"
for role in Server Client; do
  codesign --verify --deep --strict "dist/Screener $role.app"
  xcrun stapler validate "dist/Screener $role.app"
  spctl --assess --type execute "dist/Screener $role.app"
  lower=$(tr '[:upper:]' '[:lower:]' <<< "$role")
  "$signer" --verify --ed-key-file "$key" "dist/feeds/$lower.xml"
  signature=$(python3 - "$lower" <<'PY'
import sys
import xml.etree.ElementTree as ET
enclosure = ET.parse(f'dist/feeds/{sys.argv[1]}.xml').find('channel/item/enclosure')
print(enclosure.attrib['{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'])
PY
)
  "$signer" --verify --ed-key-file "$key" "dist/Screener-$role-$version.zip" "$signature"
done
(cd dist && shasum -a 256 -c SHA256SUMS)
gh auth status
gh api user --jq .login >/dev/null
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  git init -b main
  git add .
  git commit -m 'Build Screener server and client with 4K HiDPI streaming and Sparkle updates'
fi
[[ $(git branch --show-current) == main ]] || { echo 'Publish from the main branch.' >&2; exit 1; }
[[ -z $(git status --porcelain) ]] || { echo 'Commit source changes before publishing.' >&2; exit 1; }
if git ls-files .github/workflows | grep -q .; then
  echo 'Remove GitHub Actions workflows; all builds must run locally.' >&2; exit 1
fi
if ! gh repo view "$repo" >/dev/null 2>&1; then
  gh repo create "$repo" --public --description 'Native 4K remote desktop for Apple silicon Macs, with headless HiDPI displays and Sparkle updates.'
fi
# Builds, tests, signing and notarization run locally, never in GitHub Actions.
gh api --method PUT "repos/$repo/actions/permissions" -F enabled=false >/dev/null
if ! git remote get-url origin >/dev/null 2>&1; then git remote add origin "https://github.com/$repo.git"; fi
remote=$(git remote get-url origin)
[[ $remote == "https://github.com/$repo.git" || $remote == "git@github.com:$repo.git" ]] || { echo 'Origin does not match the release repository.' >&2; exit 1; }
git push -u origin main
if gh release view "v$version" --repo "$repo" >/dev/null 2>&1; then echo 'This release already exists; increase VERSION.' >&2; exit 1; fi
gh release create "v$version" "dist/Screener-Server-$version.zip" "dist/Screener-Client-$version.zip" dist/SHA256SUMS \
  --repo "$repo" --target main --draft --prerelease --title "Screener $version — Preview" --notes-file docs/release-notes.md
gh release edit "v$version" --repo "$repo" --draft=false
# Update feeds only after the signed downloads are available.
cp dist/feeds/*.xml feeds/
git add feeds/server.xml feeds/client.xml
git commit -m "Publish Sparkle feeds for $version"
git push origin main
gh release view "v$version" --repo "$repo" --json url --jq .url
