import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
	private let hotKeyManager = HotKeyManager()
	private let menuBuilder = MenuBuilder()
	private weak var currentApp: NSRunningApplication?
	private var activeMenu: NSMenu?

	func applicationDidFinishLaunching(_: Notification) {
		hotKeyManager.onActivated = { [weak self] in
			self?.showMenu(at: NSEvent.mouseLocation)
		}
		hotKeyManager.setup()
		print("Ready! Press hotkey to show menu.")
	}

	func applicationWillTerminate(_: Notification) {
		hotKeyManager.cleanup()
	}

	private func showMenu(at location: NSPoint) {
		guard let app = NSWorkspace.shared.frontmostApplication else { return }

		currentApp = app
		let appElement = AXUIElementCreateApplication(app.processIdentifier)
		var menuBar: AnyObject?

		guard
			AXUIElementCopyAttributeValue(appElement, "AXMenuBar" as CFString, &menuBar)
			== .success,
			let menuBarRef = menuBar,
			CFGetTypeID(menuBarRef) == AXUIElementGetTypeID()
		else {
			print("Failed to get menu bar")
			return
		}

		let items = menuBuilder.buildMenu(
			from: menuBarRef as! AXUIElement,
			target: self,
			action: #selector(menuAction(_:))
		)

		let menu = NSMenu()
		menu.delegate = self
		menu.autoenablesItems = false

		items.forEach { menu.addItem($0) }
		activeMenu = menu

		menu.popUp(positioning: nil, at: location, in: nil)
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
		if activeMenu == notification.object as? NSMenu {
			activeMenu = nil
			hotKeyManager.reregister()
		}
	}
}
