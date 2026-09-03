import Cocoa

// MediaRemote is the private framework that powers Now Playing.
// We dlopen it instead of linking, so the build works everywhere and the
// binary needs no special entitlements to pause whatever is playing.
private let mediaRemoteHandle: UnsafeMutableRawPointer? = {
    dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
}()

private let mrSendCommand: (@convention(c) (UInt32, UnsafeRawPointer?) -> Void)? = {
    guard let handle = mediaRemoteHandle,
          let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else { return nil }
    return unsafeBitCast(symbol, to: (@convention(c) (UInt32, UnsafeRawPointer?) -> Void).self)
}()

private let mrCommandPause: UInt32 = 1 // MRCommandPause (a plain pause, not a toggle)
private let nxKeyPlayPause: CGKeyCode = 16 // NX_KEYTYPE_PLAY

final class MediaController: NSObject, NSSoundDelegate {
    private var alarmSound: NSSound?
    private var replayTimer: Timer?
    private var alarmRunning = false

    /// Pause whatever app is currently playing audio. MRCommandPause is a
    /// plain pause (not a toggle): if nothing is playing it is a no-op, and
    /// a paused track is never accidentally resumed.
    func pauseNowPlaying() {
        if let sendCommand = mrSendCommand {
            sendCommand(mrCommandPause, nil)
        } else {
            // Fallback: synthesize the hardware play/pause media key.
            postMediaPlayPauseKey()
        }
    }

    private func postMediaPlayPauseKey() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: nxKeyPlayPause, keyDown: keyDown) else { continue }
            event.flags = [.maskSecondaryFn, .maskNonCoalesced]
            event.post(tap: .cghidEventTap)
        }
    }

    /// Loop an alarm tone at full gain through the current output device,
    /// i.e. at the same audio level the user was just hearing
    /// (the system volume is left untouched).
    func startAlarm() {
        stopAlarm()
        guard let sound = NSSound(named: "Basso") ?? NSSound(named: "Sosumi") else {
            NSSound.beep()
            return
        }
        sound.volume = 1.0
        sound.delegate = self
        alarmSound = sound
        alarmRunning = true
        sound.play()
    }

    func stopAlarm() {
        alarmRunning = false
        replayTimer?.invalidate()
        replayTimer = nil
        alarmSound?.stop()
        alarmSound?.delegate = nil
        alarmSound = nil
    }

    // MARK: - NSSoundDelegate

    func sound(_ sound: NSSound, didFinishPlaying successfully: Bool) {
        guard alarmRunning, sound === alarmSound else { return }
        replayTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: false) { [weak self] _ in
            guard let self, self.alarmRunning, let sound = self.alarmSound else { return }
            sound.currentTime = 0
            sound.play()
        }
    }
}
