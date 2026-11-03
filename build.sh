#!/bin/bash
# Builds build/ScaleneFirewall.app (menu bar app, ad-hoc signed, no developer account needed).
set -euo pipefail
cd "$(dirname "$0")"

ARCHS="${ARCHS:-arm64 x86_64}"
SDK="$(xcrun --show-sdk-path)"
APP=build/ScaleneFirewall.app

rm -rf build
mkdir -p "$APP/Contents/MacOS" build/tmp

slices=()
for arch in $ARCHS; do
  swiftc -O -swift-version 5 -sdk "$SDK" -target "$arch-apple-macos14.0" -module-name ScaleneFirewall \
    -lsqlite3 Sources/App/*.swift Sources/Shared/*.swift -o "build/tmp/$arch"
  slices+=("build/tmp/$arch")
done
lipo -create "${slices[@]}" -output "$APP/Contents/MacOS/ScaleneFirewall"
cp Resources/App-Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --force --sign - "$APP"
rm -rf build/tmp
echo "Built $APP"
