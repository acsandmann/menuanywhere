import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
	private let hotKeyManager = HotKeyManager()
	private let menuBuilder = MenuBuilder()
	private weak var currentApp: NSRunningApplication?
	private var activeMenu: NSMenu?

	private static let kAXMenuBarAttributeString = kAXMenuBarAttribute as CFString
	private static let kAXPressAction = "AXPress" as CFString
	private static let appActivationDelay: TimeInterval = 0.1

	// Lock file properties
	private static let uniqueLockFileName = "menuanywhere.lock"
	private var lockFileHandle: FileHandle?
	private var lockFilePath: URL?

	func applicationDidFinishLaunching(_: Notification) {
		if !acquireSingleInstanceLock() {
			print("Exiting this instance...")
			NSApp.terminate(nil)
			return
		}

		hotKeyManager.onActivated = { [weak self] in
			self?.showMenu(at: NSEvent.mouseLocation)
		}
		_ = hotKeyManager.setup()
		print("Ready! Press hotkey to show menu.")
	}

	func applicationWillTerminate(_: Notification) {
		hotKeyManager.cleanup()
		cleanupActiveMenu()
		releaseSingleInstanceLock()
	}

	private func acquireSingleInstanceLock() -> Bool {
		let temporaryDirectory = FileManager.default.temporaryDirectory

		lockFilePath = temporaryDirectory.appendingPathComponent(Self.uniqueLockFileName)

		guard let path = lockFilePath else {
			print("Error: Failed to construct lock file path.")
			return false
		}

		do {
			// Attempt to open/create the lock file for updating.
			// If the file doesn't exist, this will create it.
            if !FileManager.default.fileExists(atPath: path.path) {
				FileManager.default.createFile(atPath: path.path, contents: nil, attributes: nil)
			}
			lockFileHandle = try FileHandle(forUpdating: path)
			guard let fileDescriptor = lockFileHandle?.fileDescriptor else {
                print("Error: Could not get file descriptor for lock file.")
                return false
            }

			// Attempt to acquire an exclusive, non-blocking lock.
			let result = flock(fileDescriptor, LOCK_EX | LOCK_NB)

			if result == 0 {
				return true
			} else if errno == EWOULDBLOCK {
				print("Error: Another instance is running (lock file is held).")
				lockFileHandle?.closeFile()
				lockFileHandle = nil
				return false
			} else {
				print("Error: Failed to acquire lock file: \(String(cString: strerror(errno)))")
				lockFileHandle?.closeFile()
				lockFileHandle = nil

				try? FileManager.default.removeItem(at: lockFilePath!)
				return false
			}
		} catch {
			print("Error: Lock file operation failed: \(error.localizedDescription)")
			lockFileHandle?.closeFile()
			lockFileHandle = nil

			try? FileManager.default.removeItem(at: lockFilePath!)
			return false
		}
	}

	private func releaseSingleInstanceLock() {
		if let handle = lockFileHandle {
			flock(handle.fileDescriptor, LOCK_UN)
			handle.closeFile()
			lockFileHandle = nil
			if let path = lockFilePath {
				do {
					try FileManager.default.removeItem(at: path)
					print("Released and removed single instance lock from /tmp.")
				} catch {
					print("Failed to remove lock file from /tmp: \(error.localizedDescription)")
				}
			}
		}
	}

	// MARK: - Existing Menu Logic (Unchanged)

	private func showMenu(at location: NSPoint) {
		cleanupActiveMenu()

		guard let app = NSWorkspace.shared.frontmostApplication else { return }

		currentApp = app

		let appElement = AXUIElementCreateApplication(app.processIdentifier)
		var menuBar: AnyObject?

		guard
			AXUIElementCopyAttributeValue(appElement, Self.kAXMenuBarAttributeString, &menuBar)
			== .success,
			let menuBarElement = menuBar,
			CFGetTypeID(menuBarElement as CFTypeRef) == AXUIElementGetTypeID()
		else {
			print("Failed to get menu bar")
			return
		}

		let items = menuBuilder.buildMenu(
			from: menuBar as! AXUIElement,
			target: self,
			action: #selector(menuAction(_:))
		)

		let menu = NSMenu()
		menu.delegate = self
		menu.autoenablesItems = false
		items.forEach(menu.addItem)
		activeMenu = menu

		menu.popUp(positioning: nil, at: location, in: nil)
	}

	private func cleanupActiveMenu() {
		guard let menu = activeMenu else { return }

		cleanupMenuItems(menu.items)

		menu.removeAllItems()

		activeMenu = nil

		autoreleasepool {}
	}

	private func cleanupMenuItems(_ items: [NSMenuItem]) {
		for item in items {
			if let submenu = item.submenu {
				cleanupMenuItems(submenu.items)
				submenu.removeAllItems()
			}

			item.representedObject = nil
			item.target = nil
			item.action = nil
		}
	}

	@objc private func menuAction(_ sender: NSMenuItem) {
		guard let obj = sender.representedObject,
		      CFGetTypeID(obj as CFTypeRef) == AXUIElementGetTypeID(),
		      let app = currentApp, !app.isTerminated
		else { return }

		let element = obj as! AXUIElement

		if !app.isActive {
			app.activate(options: [])
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
				AXUIElementPerformAction(element, "AXPress" as CFString)
			}
		} else {
			AXUIElementPerformAction(element, "AXPress" as CFString)
		}
	}

	@objc func menuDidEndTracking(_ notification: Notification) {
		if activeMenu === notification.object as? NSMenu {
			DispatchQueue.main.async { [weak self] in
				self?.cleanupActiveMenu()
			}
			_ = hotKeyManager.reregister()
		}
	}
}
