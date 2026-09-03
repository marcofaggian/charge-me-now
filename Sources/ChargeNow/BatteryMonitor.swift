import Foundation
import IOKit
import IOKit.ps

struct BatteryHealth {
    var cycleCount: Int
    var designCycleCount: Int // 0 = unknown
    var designCapacity: Int   // mAh
    var maxCapacity: Int      // mAh (AppleRawMaxCapacity)
    var healthPercent: Double // maxCapacity / designCapacity, 1 decimal
}

struct BatteryInfo {
    var present = false
    var percent = 100
    var charging = false
    var plugged = false
    var minutesRemaining = -1 // negative = unknown / not applicable
    var health: BatteryHealth?
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
        let estimate = IOPSGetTimeRemainingEstimate()
        let minutes = (estimate.isFinite && estimate >= 0) ? Int(estimate.rounded()) : -1

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
                plugged: powerSource == "AC Power", // kIOPSACPowerKey
                minutesRemaining: minutes,
                health: readHealth()
            )
        }
        return BatteryInfo()
    }

    /// Battery health from the AppleSmartBattery IORegistry entry (what
    /// CoconutBattery reads): cycle count, design cycle life, and full
    /// charge vs design capacity.
    private static func readHealth() -> BatteryHealth? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = properties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        let cycleCount = dict["CycleCount"] as? Int ?? 0
        let designCycleCount = dict["DesignCycleCount9C"] as? Int ?? 0
        let designCapacity = dict["DesignCapacity"] as? Int ?? 0
        // On modern macOS "MaxCapacity" is percentage-like; the raw value
        // holds the real mAh full-charge capacity.
        let maxCapacity = (dict["AppleRawMaxCapacity"] as? Int) ?? (dict["MaxCapacity"] as? Int ?? 0)
        guard cycleCount > 0 || designCapacity > 0 else { return nil }

        let healthPercent = designCapacity > 0
            ? ((Double(maxCapacity) / Double(designCapacity) * 1000).rounded() / 10)
            : 0
        return BatteryHealth(cycleCount: cycleCount,
                             designCycleCount: designCycleCount,
                             designCapacity: designCapacity,
                             maxCapacity: maxCapacity,
                             healthPercent: healthPercent)
    }
}
