import Foundation
import IOKit.ps

struct BatteryInfo {
    var present = false
    var percent = 100
    var charging = false
    var plugged = false
}

final class BatteryMonitor {
    var onUpdate: ((BatteryInfo) -> Void)?

    private var timer: Timer?

    func start() {
        // Immediate, event-driven updates whenever power state changes.
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.poll()
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        // Polling safety net in case a notification is missed.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    func poll() {
        onUpdate?(Self.read())
    }

    private static func read() -> BatteryInfo {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatteryInfo()
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let powerSource = description[kIOPSPowerSourceStateKey] as? String ?? ""
            return BatteryInfo(
                present: true,
                percent: Int((Double(current) / Double(maximum) * 100).rounded()),
                charging: charging,
                plugged: powerSource == "AC Power" // kIOPSACPowerKey
            )
        }
        return BatteryInfo()
    }
}
