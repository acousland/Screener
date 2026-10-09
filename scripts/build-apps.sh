#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-env.sh
version=$(tr -d '[:space:]' < VERSION)
build=${SCREENER_BUILD_NUMBER:-$(date +%s)}
configuration=${SCREENER_CONFIGURATION:-release}
repo=${SCREENER_REPO:-acousland/Screener}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && $build =~ ^[0-9]+$ ]] || { echo 'Invalid version/build number' >&2; exit 1; }
[[ -f Assets/update-public-key ]] || { echo 'Run swift scripts/init-update-key.swift once before building.' >&2; exit 1; }
identity=${SCREENER_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p' | head -1)}
identity=${identity:--}
if [[ ${SCREENER_RELEASE:-0} == 1 && $identity == - ]]; then
  echo 'Release builds require a Developer ID Application identity. No release was built.' >&2; exit 1
fi
swift build -c "$configuration" --arch arm64 --disable-sandbox --cache-path .build/cache -debug-info-format none
bin=$(swift build -c "$configuration" --arch arm64 --show-bin-path --disable-sandbox --cache-path .build/cache -debug-info-format none)
[[ -f Assets/ScreenerClient.icns ]] || scripts/make-icons.sh
for role in Server Client; do
  app="dist/Screener $role.app"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
  cp "$bin/Screener$role" "$app/Contents/MacOS/Screener$role"
  sdk=$(xcrun --sdk macosx --show-sdk-version)
  xcrun vtool -set-build-version macos 15.0 "$sdk" -replace -output "$app/Contents/MacOS/Screener$role" "$app/Contents/MacOS/Screener$role"
  ditto "$bin/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
  cp "Assets/Screener$role.icns" "$app/Contents/Resources/"
  cp LICENSE "$app/Contents/Resources/Screener-LICENSE.txt"
  if [[ ${SCREENER_LOCAL_SPARKLE:-0} == 1 ]]; then
    license=${SCREENER_SPARKLE_LICENSE:-Vendor/Sparkle-LICENSE}
  else license=.build/checkouts/Sparkle/LICENSE; fi
  cp "$license" "$app/Contents/Resources/Sparkle-LICENSE.txt"
  python3 scripts/write-plist.py "$role" "$app/Contents/Info.plist" "$version" "$build" "$repo"
  chmod 755 "$app/Contents/MacOS/Screener$role"
  if [[ $identity == - ]]; then
    codesign --force --deep --sign - "$app"
  else
    sign=(codesign --force --options runtime --timestamp --sign "$identity")
    framework="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
    "${sign[@]}" "$framework/XPCServices/Installer.xpc"
    "${sign[@]}" --preserve-metadata=entitlements "$framework/XPCServices/Downloader.xpc"
    "${sign[@]}" "$framework/Autoupdate" "$framework/Updater.app"
    "${sign[@]}" "$app/Contents/Frameworks/Sparkle.framework"
    "${sign[@]}" "$app"
  fi
  codesign --verify --deep --strict "$app"
done
cp "$bin/ScreenerDiagnostics" dist/ScreenerDiagnostics
echo "Built Server and Client ($version, build $build). Signing identity: $identity"
