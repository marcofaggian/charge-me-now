#!/usr/bin/env bash
# Build and run ChargeMeNow in the foreground (Ctrl-C to quit).
# stdout logging ([ChargeMeNow] ...) is visible in the terminal.
#
# Usage:
#   scripts/run.sh                  # debug build, run
#   scripts/run.sh release          # release build, run
#   scripts/run.sh release --test   # any extra args are passed to the app
set -eo pipefail
cd "$(dirname "$0")/.."

config="debug"
args=()
for arg in "$@"; do
  case "$arg" in
    debug|release) config="$arg" ;;
    *) args+=("$arg") ;;
  esac
done

swift build -c "$config"

echo "Running ChargeMeNow ($config). Ctrl-C to quit."
exec ".build/$config/ChargeMeNow" ${args[@]+"${args[@]}"}
