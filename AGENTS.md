# AGENTS.md

macOS menu-bar (tray) app written in Swift/AppKit. SwiftPM executable target, no Xcode project, no tests, no linter. `swift build` is the only correctness gate — run it after every change.

## Commands

```bash
scripts/build.sh                  # release build (debug | --universal also valid)
scripts/run.sh [debug|release] [--test …]   # build + run in foreground; extra args pass to the binary
scripts/package-app.sh [--universal] [--sign="CERT NAME"] [--notarize] [--profile=notary]
                                   # dist/ChargeMeNow.app + ChargeMeNow.zip
scripts/publish.sh                # universal + Developer ID sign + notarize + staple (full pipeline)
swift build                       # quick typecheck gate
```

Install for real use (established flow, replaces in place):

```bash
pkill -f "/Applications/ChargeMeNow.app"; sleep 1
rm -rf /Applications/ChargeMeNow.app && cp -R dist/ChargeMeNow.app /Applications/ && open /Applications/ChargeMeNow.app
```

`--test` launches the alarm ~0.5 s after launch (sound plays). Run under a PTY (`script -q /dev/null <bin>`) to see stdout logs; piped stdout is block-buffered and lost on SIGTERM.

## Structure

```
Sources/ChargeMeNow/
  main.swift            NSApplication bootstrap, accessory activation policy, --test flag
  AppDelegate.swift     NSStatusItem + menu construction/rendering, view-based header row
  AlarmController.swift Central state machine: BatteryInfo -> State, trigger/reset logic
  BatteryMonitor.swift  IOKit IOPS (percent/charging/time-remaining) + AppleSmartBattery
                        IORegistry (health/cycles/wattage/manufacture date), run-loop
                        notification + 5 s polling fallback
  BatteryIcon.swift     Pure-CoreGraphics SoC icon drawing (also reused standalone for tests)
  EnergyMonitor.swift   top(1) power sampling -> per-app attribution, background queue
  LowPowerMode.swift    pmset read/write with admin-privilege AppleScript fallback
  MediaController.swift MediaRemote (private framework, dlopen'd) pause + looping NSSound alarm
  OverlayController.swift Full-screen click-through red overlay windows
scripts/               build/run/package/publish wrappers
.developer-id/         gitignored CSR + private key for the Developer ID cert
dist/                  gitignored output
```

## Architecture

- One-way data flow: `BatteryMonitor` → `AlarmController.handle(_:)` (single decision point: trigger at ≤2 % discharging, reset on charger/≥5 %, test-mode variants) → `State` → `AppDelegate.render(_:)`. All callbacks arrive on the main thread (IOPS run-loop source + Timer on main; EnergyMonitor hops to global queue then back to main).
- `AlarmController.State` is the only data crossing into UI. Extend it (not ad-hoc properties) when adding battery-derived info.
- Menu is built once; dynamic sections mutate in place. Never mutate while visible — guard with `menuIsOpen` (`menuWillOpen`/`menuDidClose`), apply cached values in `menuNeedsUpdate`.

## Non-obvious conventions

- No code comments unless asked; log lines use the `[ChargeMeNow]` prefix via `print`.
- Icon layout is verified by pixel analysis, not screenshots: compile `BatteryIcon.swift` together with a `main.swift` harness via `swiftc`, render levels to a PNG, sample with `NSBitmapImageRep.colorAt` (mind the 2× retina scale factor).
- macOS-version API traps observed in this codebase: `IOPSCopyTimeRemainingEstimate` → `IOPSGetTimeRemainingEstimate`; `MaxCapacity` is percentage-like (use `AppleRawMaxCapacity` for mAh); `pmset -g lpm` unsupported (parse `lowpowermode` from full `pmset -g`); `xcrun notarytool staple` → `xcrun stapler staple`.
- MediaRemote symbols are `dlsym`'d (no linkage); never call getters beyond `MRMediaRemoteSendCommand` — other signatures changed on modern macOS and segfault.
- Naming: bundle/executable `ChargeMeNow`, display name "Charge Me Now", bundle ID `com.marcosoft.chargemenow`.
- Signing identity: `Developer ID Application: Marco Faggian (Y8R6G46AQ6)`; notary keychain profile `notary`.

## Testing requirements

- No unit test target. After any change: `swift build`, then a short live run (`.build/debug/ChargeMeNow & sleep 3; kill %1`) to check for crashes/exit code.
- Battery-info changes: verify against `ioreg -rn AppleSmartBattery` / `pmset -g` raw values on this machine before shipping.
- Icon changes: rerun the PNG + pixel-analysis harness.
- Release/distribution changes: `scripts/publish.sh` must end with `spctl -a -t exec -vv dist/ChargeMeNow.app` → `accepted / Notarized Developer ID`.
