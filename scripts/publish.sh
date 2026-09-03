#!/usr/bin/env bash
# Build, sign, notarize and staple the universal release app.
# Requires the Developer ID certificate in the keychain and the "notary"
# notarytool keychain profile (see README).
set -eo pipefail
cd "$(dirname "$0")/.."

exec scripts/package-app.sh --universal \
  --sign="Developer ID Application: Marco Faggian (Y8R6G46AQ6)" \
  --notarize
