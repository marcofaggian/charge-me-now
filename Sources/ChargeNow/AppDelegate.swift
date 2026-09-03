import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var headerView: NSView?
    private var titleField: NSTextField?
    private var statusField: NSTextField?
    private var healthItem: NSMenuItem?
    private var cyclesItem: NSMenuItem?
    private var energySeparator: NSMenuItem?
    private var energyHeader: NSMenuItem?
    private var energyAppItems: [NSMenuItem] = []
    private var lowPowerItem: NSMenuItem?
    private var showPercentageItem: NSMenuItem?
    private var stopAlarmItem: NSMenuItem?
    private var lastState: AlarmController.State?
    private var menuIsOpen = false

    private let alarm = AlarmController()
    private let energy = EnergyMonitor()
    private let testAlarmOnLaunch: Bool
    private var appearanceObserver: NSKeyValueObservation?

    private static let showPercentageKey = "ShowPercentage"

    private var showPercentage: Bool {
        get { UserDefaults.standard.object(forKey: Self.showPercentageKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.showPercentageKey) }
    }

    init(testAlarmOnLaunch: Bool) {
        self.testAlarmOnLaunch = testAlarmOnLaunch
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        alarm.onStateChange = { [weak self] state in
            self?.render(state)
        }
        energy.onUpdate = { [weak self] _ in
            self?.renderEnergySection()
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        // Header row: big percentage on the left, status string
        // right-aligned on the far end. View-based so the percentage renders
        // in full color (disabled menu items would be drawn dimmed gray) and
        // never highlights. The wide view defines the menu width.
        let headerView = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 38))
        let field = NSTextField(labelWithString: "…")
        field.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        field.textColor = .labelColor
        field.frame = NSRect(x: 15, y: 3, width: 60, height: 22)
        headerView.addSubview(field)
        titleField = field

        let status = NSTextField(labelWithString: "…")
        status.font = NSFont.systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.alignment = .right
        status.frame = NSRect(x: 93, y: 5, width: 132, height: 18)
        headerView.addSubview(status)
        statusField = status

        let title = NSMenuItem()
        title.view = headerView
        menu.addItem(title)
        self.headerView = headerView

        // Battery health (CoconutBattery-style), hidden when unavailable.
        let health = NSMenuItem(title: "…", action: nil, keyEquivalent: "")
        health.isEnabled = false
        health.isHidden = true
        menu.addItem(health)
        healthItem = health

        let cycles = NSMenuItem(title: "…", action: nil, keyEquivalent: "")
        cycles.isEnabled = false
        cycles.isHidden = true
        menu.addItem(cycles)
        cyclesItem = cycles

        // Apps Using Significant Energy (hidden while the list is empty).
        let energySep = NSMenuItem.separator()
        menu.addItem(energySep)
        energySeparator = energySep

        let header = NSMenuItem(title: "Apps Using Significant Energy", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        energyHeader = header

        menu.addItem(.separator())

        let lowPower = NSMenuItem(title: "Low Power Mode", action: #selector(toggleLowPowerMode(_:)), keyEquivalent: "")
        lowPower.target = self
        menu.addItem(lowPower)
        lowPowerItem = lowPower

        let showPercentage = NSMenuItem(title: "Show Percentage", action: #selector(toggleShowPercentage(_:)), keyEquivalent: "")
        showPercentage.target = self
        showPercentage.state = self.showPercentage ? .on : .off
        menu.addItem(showPercentage)
        showPercentageItem = showPercentage

        let stopAlarm = NSMenuItem(title: "Stop Alarm", action: #selector(stopAlarm(_:)), keyEquivalent: "")
        stopAlarm.target = self
        stopAlarm.isHidden = true
        menu.addItem(stopAlarm)
        stopAlarmItem = stopAlarm

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Charge Now", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        item.menu = menu

        // Re-render the custom battery icon when light/dark mode flips
        // (its outline color adapts to the menu-bar appearance).
        appearanceObserver = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self, let lastState = self.lastState else { return }
                self.render(lastState)
            }
        }

        alarm.start()
        energy.start()

        if testAlarmOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.alarm.trigger(test: true)
            }
        }
    }

    // MARK: - Rendering

    private func render(_ state: AlarmController.State) {
        lastState = state
        stopAlarmItem?.isHidden = !state.alarmActive

        let header = state.present ? "\(state.percent)%" : "Charge Now"
        titleField?.stringValue = header
        statusField?.stringValue = state.present ? subtitleText(for: state) : ""

        let showHealth = state.present && state.health != nil
        healthItem?.isHidden = !showHealth
        cyclesItem?.isHidden = !showHealth
        if let health = state.health {
            healthItem?.title = "Battery Health: \(String(format: "%.1f", health.healthPercent))% (\(health.maxCapacity)/\(health.designCapacity) mAh)"
            if health.designCycleCount > 0 {
                cyclesItem?.title = "Cycles: \(health.cycleCount)/\(health.designCycleCount)"
            } else {
                cyclesItem?.title = "Cycles: \(health.cycleCount)"
            }
        }

        let button = statusItem?.button
        if !state.present {
            button?.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Charge Now")
            button?.title = ""
        } else {
            if state.alarmActive {
                button?.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Low battery alarm")
            } else {
                button?.image = BatteryIcon.image(percent: state.percent, charging: state.charging)
            }
            button?.title = showPercentage ? "\(state.percent)%" : ""
        }

        // Time-remaining changes affect the energy impact annotations.
        renderEnergySection()
    }

    private func subtitleText(for state: AlarmController.State) -> String {
        if state.plugged {
            if state.charging { return "Charging" }
            return state.percent >= 100 ? "Fully charged" : "Power adapter"
        }
        if state.minutesRemaining >= 0 {
            return String(format: "%d:%02d remaining", state.minutesRemaining / 60, state.minutesRemaining % 60)
        }
        return "Estimating time remaining…"
    }

    /// Impact annotation for an energy row. On battery: estimated extra
    /// runtime if the app were quit (from the current time-remaining
    /// estimate). Plugged in: share of the sampled system load.
    private func energyDetail(for app: EnergyMonitor.EnergyApp) -> String {
        if let state = lastState, !state.plugged, state.minutesRemaining > 0, app.share > 0 {
            let gained = Double(state.minutesRemaining) * app.share / (1 - app.share)
            let minutes = Int((gained / 5).rounded() * 5)
            if minutes >= 5 {
                return "−\(minutes) min"
            }
            return "minor"
        }
        return "\(Int((app.share * 100).rounded()))% of load"
    }

    private func renderEnergySection() {
        // Never mutate a menu that is currently being displayed — the cached
        // list is applied the next time the menu opens (menuNeedsUpdate).
        guard !menuIsOpen else { return }
        guard let menu = statusItem?.menu,
              let header = energyHeader,
              let separator = energySeparator else { return }
        let apps = energy.significantApps

        separator.isHidden = apps.isEmpty
        header.isHidden = apps.isEmpty

        energyAppItems.forEach(menu.removeItem)
        energyAppItems = []

        var index = menu.index(of: header) + 1
        for app in apps {
            let item = NSMenuItem(title: "\(app.name) — \(energyDetail(for: app))", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.toolTip = String(format: "top power score %.0f (~%.0f%% of sampled system load)", app.power, app.share * 100)
            menu.insertItem(item, at: index)
            energyAppItems.append(item)
            index += 1
        }
    }

    // MARK: - Low Power Mode

    private func refreshLowPowerItem() {
        guard let item = lowPowerItem else { return }
        if let on = LowPowerMode.currentState {
            item.isHidden = false
            item.state = on ? .on : .off
        } else {
            item.isHidden = true
        }
    }

    @objc private func toggleLowPowerMode(_ sender: NSMenuItem) {
        guard let current = LowPowerMode.currentState else { return }
        if LowPowerMode.setEnabled(!current) {
            print("[ChargeNow] Low Power Mode \(!current ? "enabled" : "disabled")")
        }
        refreshLowPowerItem()
    }

    // MARK: - Actions

    @objc private func toggleShowPercentage(_ sender: NSMenuItem) {
        showPercentage.toggle()
        sender.state = showPercentage ? .on : .off
        if let lastState {
            render(lastState)
        }
    }

    @objc private func stopAlarm(_ sender: NSMenuItem) {
        alarm.reset()
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Refresh dynamic sections each time the menu opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Stretch the header row to the menu's real width so the status
        // string sits flush with the right inset, whatever the widest row is.
        let menuWidth = menu.size.width
        if let header = headerView, menuWidth > 0 {
            if abs(header.frame.width - menuWidth) > 0.5 {
                header.frame.size.width = menuWidth
            }
            if let status = statusField {
                status.frame.origin.x = menuWidth - 15 - status.frame.width
            }
        }
        refreshLowPowerItem()
        showPercentageItem?.state = showPercentage ? .on : .off
        renderEnergySection()
        energy.refresh() // re-sample for the next open
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        renderEnergySection() // apply any results that arrived while open
    }
}
