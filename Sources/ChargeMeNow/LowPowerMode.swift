import Cocoa

/// Low Power Mode support backed by `pmset`.
/// Reading state is unprivileged; changing it requires root, so the setter
/// falls back to an administrator-privilege AppleScript (standard password
/// prompt) when the direct call is denied.
enum LowPowerMode {
    /// Current state, or nil if unsupported/unreadable (e.g. desktop Macs).
    static var currentState: Bool? {
        // Note: `pmset -g lpm` / `pmset -g lowpowermode` are not supported on
        // recent macOS; the full `pmset -g` dump always contains the line.
        guard let output = runPMSet(["-g"]) else { return nil }
        guard let line = output.split(separator: "\n").first(where: { $0.contains("lowpowermode") }) else {
            return nil
        }
        return line.trimmingCharacters(in: .whitespaces).hasSuffix("1")
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        if runPMSet(["lowpowermode", enabled ? "1" : "0"]) != nil {
            return true
        }

        let source = "do shell script \"/usr/bin/pmset lowpowermode \(enabled ? "1" : "0")\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            print("[ChargeMeNow] Low Power Mode toggle failed: \(error[NSAppleScript.errorNumber] ?? "unknown error")")
            return false
        }
        return true
    }

    private static func runPMSet(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
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
