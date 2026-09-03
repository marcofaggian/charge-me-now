# Charge Me Now!

A tiny macOS menu-bar (tray) app that screams at you when your battery is about to die.

When the battery hits **2 % or less** and you're not plugged in, it:

1. **Pauses** whatever audio is currently playing (via the same MediaRemote
   channel the Now Playing controls use — a plain pause, so a paused track
   is never resumed, and it's a no-op if nothing is playing).
2. **Plays a looping alarm tone** through the current output device at the
   current system volume — i.e. exactly the audio level you were just
   hearing (system volume is never touched).
3. **Overlays every screen** with a pulsing red tint and **"CHARGE ME NOW!"**
   in huge block letters. The overlay is click-through, so your Mac stays
   usable and the menu-bar item is still reachable.

It **resets automatically** the moment you plug in the charger (or the level
recovers to ≥ 5 % — a small hysteresis so it doesn't flap).

## Install

**Homebrew** (recommended):

```sh
brew install --cask marcofaggian/tap/charge-me-now
```

**Direct download** — grab `ChargeMeNow.zip` from the
[latest release](https://github.com/marcofaggian/charge-me-now/releases/latest),
unzip, and drop `ChargeMeNow.app` into `/Applications`.

The release build is universal (arm64 + x86_64), Developer ID signed,
notarized and stapled — Gatekeeper accepts it out of the box. Requires
macOS 13+.

## Menu bar

The app lives in the menu bar with a **custom battery SoC icon + percentage**:

- fill advances in **10 % increments** (rounded to the nearest 10 %)
- fill is drawn over the bezel, hiding the border under the color —
  a full battery reads as one solid green shape
- `< 10 %` → red fill while discharging; green at any level while charging
- charging → white bolt overlay (dark halo) that extends past the battery's
  top and bottom edges
- unfilled bezel strokes are drawn at 50 % transparency

The icon is drawn with CoreGraphics (`BatteryIcon.swift`) and adapts its
outline to light/dark menu bars. Menu contents:

- bold percentage header with time-remaining / charging subtitle
- **Battery Health: N % (max/design mAh)** and **Cycles: n / m** — read
  straight from the `AppleSmartBattery` IORegistry entry (same source as
  CoconutBattery); hidden on Macs without a battery
- **Apps Using Significant Energy** (section, only when non-empty)
- **Low Power Mode** — checkbox toggling the real system setting via
  `pmset`. Toggling needs admin rights, so macOS will prompt for your
  password the first time; the checkbox refreshes every time the menu
  opens. Hidden on Macs that don't support it.
- **Show Percentage** — toggles the `N%` next to the battery icon
  (remembered across launches).
- **Stop Alarm** — appears only while the alarm is active.
- **Quit Charge Me Now** — closes the app.

The menu mirrors the system battery layout: a bold percentage header with a
time-remaining / charging subtitle, followed by an **Apps Using Significant
Energy** section when applicable. Each row is annotated with its estimated
battery impact: **−N min** (extra runtime you'd gain by quitting it, derived
from the current time-remaining estimate and the app's share of sampled
system load) on battery power, or **N% of load** while plugged in; hovering
shows the raw `top` power score. The list is sampled every 60 s (and each
time the menu opens) via `top`'s power column, and hot processes are mapped
to friendly names of running GUI apps — helpers like
`Chromium Helper (Renderer)` collapse to `Chromium`, and system daemons are
filtered out.

A manual test also resets when you plug the charger in mid-test (unless it
was already plugged when you started the test).

## Build & run

Requires macOS 13+ and the Xcode command-line tools.

The `scripts/` helpers wrap everything for local use:

```sh
scripts/build.sh                  # release build (native arch)
scripts/build.sh debug            # debug build
scripts/build.sh --universal      # universal arm64 + x86_64 (needs full Xcode)

scripts/run.sh                    # build (debug) + run in the foreground, Ctrl-C to quit
scripts/run.sh release --test     # any extra args go to the app (--test fires a demo alarm)

scripts/package-app.sh            # dist/ChargeMeNow.app — double-clickable, ad-hoc signed
scripts/package-app.sh --universal
```

Or plain SwiftPM:

```sh
swift build -c release
.build/release/ChargeMeNow          # add --test for a ~0.5 s delayed demo alarm
```

## How it works

| Piece | Mechanism |
|---|---|
| Battery monitoring | `IOKit` power sources (`IOPSCopyPowerSources…`) with a run-loop notification plus a 5 s polling safety net |
| Pausing audio | `MRMediaRemoteSendCommand` (private `MediaRemote` framework, `dlopen`'d — no special permissions needed) |
| Alarm tone | `NSSound` ("Basso") looping via its `NSSoundDelegate` |
| Overlay | Borderless, click-through `NSWindow`s at screen-saver level on every `NSScreen`, drawn with a custom pulsing view |

## Notes

- Runs as a pure accessory app: no Dock icon, no main window, nothing in
  `Cmd+Tab`.
- If `MediaRemote` is ever unavailable, it falls back to synthesizing the
  hardware play/pause media key, which may prompt for Accessibility
  permission.
- Log lines are printed to stdout (`[ChargeMeNow] …`) if you run it from a
  terminal.
