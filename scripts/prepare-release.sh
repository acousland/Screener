#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-env.sh
mode=${1:-release}
[[ $mode == release || $mode == --development ]] || { echo 'Usage: scripts/prepare-release.sh [--development]' >&2; exit 1; }
export SCREENER_RELEASE=1
if [[ $mode == --development ]]; then export SCREENER_RELEASE=0; fi
export SCREENER_BUILD_NUMBER=${SCREENER_BUILD_NUMBER:-$(date +%s)}
repo=${SCREENER_REPO:-acousland/Screener}
version=$(tr -d '[:space:]' < VERSION)
key=${SCREENER_SPARKLE_KEY_FILE:-.secrets/sparkle-private-key}
[[ -r $key ]] || { echo 'The Sparkle private key is required; restore it to .secrets/sparkle-private-key.' >&2; exit 1; }
swift scripts/verify-update-key.swift "$key"
scripts/build-apps.sh
if [[ ${SCREENER_LOCAL_SPARKLE:-0} == 1 ]]; then
  signer=${SCREENER_SPARKLE_BIN:-Vendor/sparkle-bin}/sign_update
else signer=.build/artifacts/sparkle/Sparkle/bin/sign_update; fi
[[ -x $signer ]] || { echo 'Sparkle sign_update is missing.' >&2; exit 1; }
mkdir -p dist/feeds
for role in Server Client; do
  app="dist/Screener $role.app"
  if [[ $mode == release ]]; then scripts/notarize.sh "$app"; fi
  archive="dist/Screener-$role-$version.zip"
  rm -f "$archive"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
  signature=$("$signer" --ed-key-file "$key" -p "$archive")
  "$signer" --verify --ed-key-file "$key" "$archive" "$signature"
  python3 scripts/appcast.py "$role" "$archive" "$version" "$SCREENER_BUILD_NUMBER" "$repo" "$signature"
  lower=$(tr '[:upper:]' '[:lower:]' <<< "$role")
  "$signer" --ed-key-file "$key" "dist/feeds/$lower.xml"
  "$signer" --verify --ed-key-file "$key" "dist/feeds/$lower.xml"
done
python3 scripts/release-manifest.py "$mode" "$version" "$SCREENER_BUILD_NUMBER" "$repo"
(cd dist && shasum -a 256 "Screener-Server-$version.zip" "Screener-Client-$version.zip" > SHA256SUMS)
echo "Prepared $mode archives. Publishing is a separate step: scripts/publish.sh"
