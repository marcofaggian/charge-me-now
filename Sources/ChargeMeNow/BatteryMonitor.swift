import Foundation
import IOKit
import IOKit.ps

struct BatteryHealth {
    var cycleCount: Int
    var designCycleCount: Int // 0 = unknown
    var designCapacity: Int   // mAh
    var maxCapacity: Int      // mAh (AppleRawMaxCapacity)
    var healthPercent: Double // maxCapacity / designCapacity, 1 decimal
    var manufactureDate: String?
}

struct BatteryInfo {
    var present = false
    var percent = 100
    var charging = false
    var plugged = false
    var minutesRemaining = -1 // negative = unknown / not applicable
    var watts: Double? // live battery power (V × I); nil = unknown
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
        timer?.tolerance = 1 // allow coalescing
        poll()
    }

    func poll() {
        onUpdate?(Self.read())
    }

    private static func read() -> BatteryInfo {
        let estimate = IOPSGetTimeRemainingEstimate()
        let minutes = (estimate.isFinite && estimate >= 0) ? Int(estimate.rounded()) : -1
        let registry = smartBatteryDictionary()
        if cachedHealth == nil {
            cachedHealth = readHealth(from: registry)
        }

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
                watts: Self.readWatts(from: registry),
                health: Self.cachedHealth
            )
        }
        return BatteryInfo()
    }

    /// Health changes ~never (cycles increment over months); parse once.
    private static var cachedHealth: BatteryHealth?

    /// The AppleSmartBattery IORegistry entry, shared by health + wattage.
    private static func smartBatteryDictionary() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = properties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return dict
    }

    /// Live battery power in watts: pack voltage × current.
    private static func readWatts(from dict: [String: Any]?) -> Double? {
        guard let dict,
              let voltage = dict["Voltage"] as? Int, voltage > 0,
              let amperage = (dict["InstantAmperage"] as? Int) ?? (dict["Amperage"] as? Int) else {
            return nil
        }
        return (Double(voltage) / 1000.0) * (Double(abs(amperage)) / 1000.0)
    }

    /// Battery health from the AppleSmartBattery IORegistry entry (what
    /// CoconutBattery reads): cycle count, design cycle life, and full
    /// charge vs design capacity.
    private static func readHealth(from dict: [String: Any]?) -> BatteryHealth? {
        guard let dict else { return nil }

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
                             healthPercent: healthPercent,
                             manufactureDate: readManufactureDate(from: dict))
    }

    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// Manufacture date. Intel Macs expose a top-level "ManufactureDate"
    /// packed as ((year-1980)<<9 | month<<5 | day). Apple Silicon Macs don't;
    /// there the SBS MfgData block inside ManufacturerData carries a vendor
    /// character followed by a YYWW production code (week granularity, so
    /// we report month-year only).
    private static func readManufactureDate(from dict: [String: Any]?) -> String? {
        guard let dict else { return nil }

        if let packed = dict["ManufactureDate"] as? Int {
            let year = 1980 + ((packed >> 9) & 0x7F)
            let month = (packed >> 5) & 0xF
            let day = packed & 0x1F
            if (1990...2100).contains(year), (1...12).contains(month), (1...31).contains(day) {
                return "\(day) \(monthNames[month - 1]) \(year)"
            }
        }

        if let data = dict["ManufacturerData"] as? Data,
           let ascii = String(data: data, encoding: .ascii) {
            let chars = Array(ascii)
            if let vendor = chars.firstIndex(where: { $0.isLetter }),
               vendor + 5 < chars.count,
               let yy = Int(String(chars[vendor + 1...vendor + 2])),
               let ww = Int(String(chars[vendor + 3...vendor + 4])) {
                let year = 2000 + yy
                let week = max(ww, 1) // week "00" is sometimes used for week 1
                if (2000...2100).contains(year), (1...53).contains(week) {
                    let month = min(12, max(1, Int((Double(week - 1) * 12.0 / 52.0).rounded()) + 1))
                    return "\(monthNames[month - 1]) \(year)"
                }
            }
        }
        return nil
    }
}
