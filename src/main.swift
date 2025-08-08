import Cocoa

do {
	let singletonLock = try SingletonLock()

	AccessibilityManager.ensurePermissions()

	let delegate = AppDelegate(singletonLock: singletonLock)
	NSApplication.shared.delegate = delegate

	NotificationCenter.default.addObserver(
		delegate,
		selector: #selector(delegate.menuDidEndTracking(_:)),
		name: NSMenu.didEndTrackingNotification,
		object: nil
	)

	print("Starting menuanywhere...")
	_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
} catch SingletonLock.Error.instanceAlreadyRunning {
	print(
		"menuanywhere is already running. please close the existing instance before starting a new one."
	)
	exit(0)
} catch {
	print("An error occurred on startup: \(error.localizedDescription)")
	exit(1)
}
