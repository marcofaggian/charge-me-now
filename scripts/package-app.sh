#!/usr/bin/env bash
# Bundle the release build into a double-clickable dist/ChargeMeNow.app.
# LSUIElement is set, so it runs as a pure menu-bar app.
#
# Usage:
#   scripts/package-app.sh                              # native arch, ad-hoc signed
#   scripts/package-app.sh --universal                  # arm64 + x86_64 (needs full Xcode)
#   scripts/package-app.sh --sign="CERT NAME"           # hardened-runtime Developer ID signing
#   scripts/package-app.sh --sign="CERT NAME" --notarize  # + Apple notarization and stapling
#   Optionally: --profile=NAME   notarytool keychain profile (default: "notary")
set -eo pipefail
cd "$(dirname "$0")/.."

universal="false"
notarize="false"
sign=""
profile="notary"
for arg in "$@"; do
  case "$arg" in
    --universal)   universal="true" ;;
    --notarize)    notarize="true" ;;
    --sign=*)      sign="${arg#--sign=}" ;;
    --profile=*)   profile="${arg#--profile=}" ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [[ "$notarize" == "true" && -z "$sign" ]]; then
  echo "Error: --notarize requires --sign=\"Developer ID Application: ...\"" >&2
  exit 1
fi

if [[ "$universal" == "true" ]]; then
  swift build -c release --arch arm64 --arch x86_64
  bin="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/ChargeMeNow"
else
  swift build -c release
  bin=".build/release/ChargeMeNow"
fi

rm -rf dist
mkdir -p "dist/ChargeMeNow.app/Contents/MacOS"
cp "$bin" "dist/ChargeMeNow.app/Contents/MacOS/ChargeMeNow"

cat > "dist/ChargeMeNow.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Charge Me Now</string>
    <key>CFBundleDisplayName</key>       <string>Charge Me Now</string>
    <key>CFBundleExecutable</key>        <string>ChargeMeNow</string>
    <key>CFBundleIdentifier</key>        <string>com.marcosoft.chargemenow</string>
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

if [[ -n "$sign" ]]; then
  echo "Signing (hardened runtime) with: $sign"
  codesign --force --options runtime --sign "$sign" "dist/ChargeMeNow.app"
else
  if codesign --force --sign - "dist/ChargeMeNow.app" 2>/dev/null; then
    echo "Ad-hoc code signature applied."
  else
    echo "Warning: codesign failed, the app is unsigned." >&2
  fi
fi

if [[ "$notarize" == "true" ]]; then
  echo
  echo "Notarizing (profile: $profile)…"
  rm -f dist/ChargeMeNow.zip
  ditto -c -k --keepParent "dist/ChargeMeNow.app" dist/ChargeMeNow.zip
  xcrun notarytool submit dist/ChargeMeNow.zip --keychain-profile "$profile" --wait
  xcrun stapler staple "dist/ChargeMeNow.app"
  echo
  spctl -a -t exec -vv "dist/ChargeMeNow.app"
fi

echo
echo "Created: dist/ChargeMeNow.app"
echo "  Run it:            open dist/ChargeMeNow.app"
echo "  Start at login:    System Settings > General > Login Items > +"
