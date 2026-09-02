import Foundation

/// Central state machine: watches the battery, fires the alarm at <= 2%,
/// and resets when the charger is connected (or the level recovers).
final class AlarmController {
    struct State {
        var percent: Int
        var charging: Bool
        var plugged: Bool
        var alarmActive: Bool
        var testing: Bool
    }

    static let lowBatteryThreshold = 2   // fire at <= 2%
    static let resetThreshold = 5        // hysteresis: clear at >= 5%

    var onStateChange: ((State) -> Void)?

    private let battery = BatteryMonitor()
    private let media = MediaController()
    private let overlay = OverlayController()

    private var info = BatteryInfo()
    private(set) var alarmActive = false
    private(set) var testing = false
    private var pluggedAtTrigger = false

    var state: State {
        State(percent: info.percent,
              charging: info.charging,
              plugged: info.plugged,
              alarmActive: alarmActive,
              testing: testing)
    }

    func start() {
        battery.onUpdate = { [weak self] info in
            self?.handle(info)
        }
        battery.start()
    }

    private func handle(_ newInfo: BatteryInfo) {
        info = newInfo

        if !alarmActive,
           newInfo.present,
           !newInfo.plugged,
           newInfo.percent <= Self.lowBatteryThreshold {
            trigger(test: false)
        }

        if alarmActive {
            if testing {
                // A manual test also resets when the charger is connected
                // during the test (but not if it was already plugged in).
                if newInfo.plugged, !pluggedAtTrigger {
                    reset()
                }
            } else if newInfo.plugged || !newInfo.present || newInfo.percent >= Self.resetThreshold {
                reset()
            }
        }

        onStateChange?(state)
    }

    func trigger(test: Bool) {
        guard !alarmActive else { return }
        alarmActive = true
        testing = test
        pluggedAtTrigger = info.plugged
        print("[ChargeNow] ALARM \(test ? "triggered (TEST)" : "triggered — battery \(info.percent)%")")
        media.pauseNowPlaying()
        media.startAlarm()
        overlay.show(testing: test)
        onStateChange?(state)
    }

    func reset() {
        guard alarmActive else {
            onStateChange?(state)
            return
        }
        alarmActive = false
        testing = false
        print("[ChargeNow] alarm reset (battery \(info.percent)%, \(info.plugged ? "plugged in" : "on battery"))")
        media.stopAlarm()
        overlay.hide()
        onStateChange?(state)
    }
}
