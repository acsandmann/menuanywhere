import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
	private let hotKeyManager = HotKeyManager()
	private let menuBuilder = MenuBuilder()
	private weak var currentApp: NSRunningApplication?
	private var activeMenu: NSMenu?

	private static let kAXMenuBarAttributeString = kAXMenuBarAttribute as CFString
	private static let kAXPressAction = "AXPress" as CFString
	private static let appActivationDelay: TimeInterval = 0.1

	func applicationDidFinishLaunching(_: Notification) {
		hotKeyManager.onActivated = { [weak self] in
			self?.showMenu(at: NSEvent.mouseLocation)
		}
		_ = hotKeyManager.setup()
		print("Ready! Press hotkey to show menu.")
	}

	func applicationWillTerminate(_: Notification) {
		hotKeyManager.cleanup()
		cleanupActiveMenu()
	}

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
