import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusLine: NSMenuItem?
    private var triggerItem: NSMenuItem?

    private let alarm = AlarmController()
    private let testAlarmOnLaunch: Bool

    init(testAlarmOnLaunch: Bool) {
        self.testAlarmOnLaunch = testAlarmOnLaunch
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        alarm.onStateChange = { [weak self] state in
            self?.render(state)
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Charge Now")

        let menu = NSMenu()
        menu.autoenablesItems = false

        let status = NSMenuItem(title: "Battery: …", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusLine = status

        menu.addItem(.separator())

        let trigger = NSMenuItem(title: "Trigger Alarm (Test)", action: #selector(toggleAlarm(_:)), keyEquivalent: "t")
        trigger.target = self
        menu.addItem(trigger)
        triggerItem = trigger

        let quit = NSMenuItem(title: "Quit Charge Now", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        item.menu = menu

        alarm.start()

        if testAlarmOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.alarm.trigger(test: true)
            }
        }
    }

    private func render(_ state: AlarmController.State) {
        let power: String
        if state.plugged {
            power = state.charging ? "charging" : "plugged in"
        } else {
            power = "on battery"
        }
        statusLine?.title = "Battery: \(state.percent)% (\(power))"
        triggerItem?.title = state.alarmActive ? "Stop Alarm" : "Trigger Alarm (Test)"
        let symbol = state.alarmActive ? "exclamationmark.triangle.fill" : "bolt.fill"
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Charge Now")
    }

    @objc private func toggleAlarm(_ sender: NSMenuItem) {
        if alarm.alarmActive {
            alarm.reset()
        } else {
            alarm.trigger(test: true)
        }
    }
}
