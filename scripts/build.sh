#!/usr/bin/env bash
# Build ChargeNow locally.
#
# Usage:
#   scripts/build.sh                # release build (native arch)
#   scripts/build.sh debug          # debug build
#   scripts/build.sh --universal    # release build for arm64 + x86_64 (needs full Xcode)
set -eo pipefail
cd "$(dirname "$0")/.."

config="release"
universal="false"
for arg in "$@"; do
  case "$arg" in
    debug|release)  config="$arg" ;;
    --universal)    universal="true" ;;
    *) echo "Unknown option: $arg (expected: debug | release | --universal)" >&2; exit 1 ;;
  esac
done

if [[ "$universal" == "true" ]]; then
  if [[ "$config" == "debug" ]]; then
    echo "Error: --universal only makes sense for release builds" >&2
    exit 1
  fi
  swift build -c release --arch arm64 --arch x86_64
  bin="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/ChargeNow"
else
  swift build -c "$config"
  bin="$(swift build -c "$config" --show-bin-path)/ChargeNow"
fi

echo
echo "Built ($config): $bin"
