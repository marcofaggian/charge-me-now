#!/usr/bin/env bash
# Bundle the release build into a double-clickable, ad-hoc signed
# dist/ChargeNow.app. LSUIElement is set, so it runs as a pure menu-bar app.
#
# Usage:
#   scripts/package-app.sh                # native arch
#   scripts/package-app.sh --universal    # arm64 + x86_64 (needs full Xcode)
set -eo pipefail
cd "$(dirname "$0")/.."

universal="false"
[[ "${1:-}" == "--universal" ]] && universal="true"

if [[ "$universal" == "true" ]]; then
  swift build -c release --arch arm64 --arch x86_64
  bin="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/ChargeNow"
else
  swift build -c release
  bin=".build/release/ChargeNow"
fi

rm -rf dist
mkdir -p "dist/ChargeNow.app/Contents/MacOS"
cp "$bin" "dist/ChargeNow.app/Contents/MacOS/ChargeNow"

cat > "dist/ChargeNow.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Charge Now</string>
    <key>CFBundleDisplayName</key>       <string>Charge Now</string>
    <key>CFBundleExecutable</key>        <string>ChargeNow</string>
    <key>CFBundleIdentifier</key>        <string>com.marcofaggian.chargenow</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>LSUIElement</key>               <true/>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
</dict>
</plist>
PLIST

if codesign --force --sign - "dist/ChargeNow.app" 2>/dev/null; then
  echo "Ad-hoc code signature applied."
else
  echo "Warning: codesign failed, the app is unsigned." >&2
fi

echo
echo "Created: dist/ChargeNow.app"
echo "  Run it:            open dist/ChargeNow.app"
echo "  Start at login:    System Settings > General > Login Items > +"
