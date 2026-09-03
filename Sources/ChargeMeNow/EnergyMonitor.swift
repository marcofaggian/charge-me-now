import Cocoa

/// Lists apps currently using a significant amount of energy, like the
/// system battery menu does. Samples process power via `top` (two samples,
/// sorted by power) and maps the hot processes onto running GUI apps for
/// friendly names — system daemons and helpers that don't resolve to an
/// app are filtered out.
final class EnergyMonitor {
    struct EnergyApp: Equatable {
        let name: String
        let power: Double // top power score, summed across the app's processes
        let share: Double // fraction of the sampled system-wide power
    }

    private(set) var significantApps: [EnergyApp] = []
    var onUpdate: (([EnergyApp]) -> Void)?

    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        // NSWorkspace must be touched on the main thread.
        let appNameTable = Self.runningAppNameTable()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let apps = Self.sampleSignificantApps(appNameTable: appNameTable)
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.significantApps != apps else { return }
                self.significantApps = apps
                let detail = apps.map { String(format: "%@ (%.0f, %.0f%%)", $0.name, $0.power, $0.share * 100) }.joined(separator: ", ")
                print("[ChargeMeNow] apps using significant energy: \(apps.isEmpty ? "none" : detail)")
                self.onUpdate?(apps)
            }
        }
    }

    // MARK: - Sampling

    private static func sampleSignificantApps(appNameTable: [String: String],
                                              powerThreshold: Double = 15,
                                              limit: Int = 5) -> [EnergyApp] {
        let rows = topPowerProcesses()
        let total = rows.reduce(0) { $0 + $1.power }
        guard total > 0 else { return [] }
        let candidates = rows.filter { $0.power >= powerThreshold }
        guard !candidates.isEmpty else { return [] }

        let commands = resolveCommands(pids: candidates.map { String($0.pid) })

        // Accumulate power per friendly app name (helpers collapse into
        // their parent app, e.g. Chromium renderers -> Chromium).
        var byApp: [String: Double] = [:]
        var needsParent: [(pid: Int, ppid: Int, power: Double)] = []

        for candidate in candidates {
            guard let info = commands[candidate.pid] else { continue }
            let executable = (info.command as NSString).lastPathComponent
            if let appName = matchAppName(executable, table: appNameTable) {
                byApp[appName, default: 0] += candidate.power
            } else {
                needsParent.append((candidate.pid, info.ppid, candidate.power))
            }
        }

        // Attribute hot CLI processes to their parent GUI app, like the
        // system battery menu does (e.g. work in Terminal shows as Terminal).
        if !needsParent.isEmpty {
            let parents = resolveCommands(pids: needsParent.map { String($0.ppid) })
            for need in needsParent {
                guard let parent = parents[need.ppid] else { continue }
                let executable = (parent.command as NSString).lastPathComponent
                if let appName = matchAppName(executable, table: appNameTable) {
                    byApp[appName, default: 0] += need.power
                }
            }
        }

        return byApp
            .map { EnergyApp(name: $0.key, power: $0.value, share: min($0.value / total, 0.95)) }
            .sorted { $0.power > $1.power }
            .prefix(limit)
            .map { $0 }
    }

    /// `top -l 2` produces two samples; power values only exist in the last.
    /// Samples the top 30 processes so their sum approximates the total
    /// active system load.
    private static func topPowerProcesses() -> [(pid: Int, power: Double)] {
        guard let output = run("/usr/bin/top", ["-l", "2", "-s", "1", "-o", "power", "-n", "30", "-stats", "pid,power"]) else {
            return []
        }

        var lines = output.split(separator: "\n").map(String.init)
        if let headerIndex = lines.lastIndex(where: { $0.contains("PID") && $0.contains("POWER") }) {
            lines = Array(lines[(headerIndex + 1)...])
        }

        var result: [(pid: Int, power: Double)] = []
        for line in lines {
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard tokens.count == 2,
                  let pid = Int(tokens[0]),
                  let power = Double(tokens[1]) else { continue }
            result.append((pid, power))
        }
        return result.sorted { $0.power > $1.power }
    }

    private static func resolveCommands(pids: [String]) -> [Int: (command: String, ppid: Int)] {
        guard !pids.isEmpty,
              let output = run("/bin/ps", ["-o", "pid=,ppid=,comm=", "-p", pids.joined(separator: ",")]) else {
            return [:]
        }
        var commands: [Int: (String, Int)] = [:]
        for line in output.split(separator: "\n") {
            let tokens = line.split(separator: " ", maxSplits: 2).map(String.init)
            guard tokens.count == 3,
                  let pid = Int(tokens[0]),
                  let ppid = Int(tokens[1]) else { continue }
            commands[pid] = (tokens[2], ppid)
        }
        return commands
    }

    /// Map a process executable name (possibly a "… Helper (Renderer)"
    /// variant) to the friendly name of a running GUI app, if any.
    private static func matchAppName(_ executable: String, table: [String: String]) -> String? {
        var base = executable
        if let range = base.range(of: " Helper") {
            base = String(base[..<range.lowerBound])
        }
        let lowered = base.lowercased()
        if let exact = table[lowered] { return exact }
        for (key, name) in table where key.hasPrefix(lowered) || lowered.hasPrefix(key) {
            return name
        }
        return nil
    }

    /// exec-name and localizedName (lowercased) → localizedName for all
    /// running GUI apps. Must be called on the main thread.
    private static func runningAppNameTable() -> [String: String] {
        var table: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let name = app.localizedName, !name.isEmpty else { continue }
            if let exec = app.executableURL?.lastPathComponent, !exec.isEmpty {
                table[exec.lowercased()] = name
            }
            table[name.lowercased()] = name
        }
        return table
    }

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
