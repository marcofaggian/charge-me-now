import Cocoa

let appDelegate = AppDelegate(testAlarmOnLaunch: CommandLine.arguments.contains("--test"))

let application = NSApplication.shared
application.delegate = appDelegate
application.setActivationPolicy(.accessory) // tray-only app: no Dock icon, no main window
application.run()
