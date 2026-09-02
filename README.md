# Charge Now!

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

## Menu bar

The app lives as a ⚡ bolt icon in the menu bar:

- **Battery: N % (on battery / charging)** — live status
- **Trigger Alarm (Test)** — fires the full alarm manually (`⌘T` while the menu is open); becomes **Stop Alarm** while active
- **Quit Charge Now** — closes the app

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

scripts/package-app.sh            # dist/ChargeNow.app — double-clickable, ad-hoc signed
scripts/package-app.sh --universal
```

Or plain SwiftPM:

```sh
swift build -c release
.build/release/ChargeNow          # add --test for a ~0.5 s delayed demo alarm
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
- Log lines are printed to stdout (`[ChargeNow] …`) if you run it from a
  terminal.
