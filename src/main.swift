import Cocoa

AccessibilityManager.ensurePermissions()

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate

NotificationCenter.default.addObserver(
	delegate,
	selector: #selector(delegate.menuDidEndTracking(_:)),
	name: NSMenu.didEndTrackingNotification,
	object: nil
)

print("Starting menuanywhere...")
let _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
