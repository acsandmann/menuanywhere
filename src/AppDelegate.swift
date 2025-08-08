import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
	private var singletonLock: SingletonLock
	private let hotKeyManager = HotKeyManager()
	private let menuBuilder = MenuBuilder()
	private weak var currentApp: NSRunningApplication?
	private var activeMenu: NSMenu?
	private let axFetchQueue = DispatchQueue(label: "com.menuanywhere.axfetch", qos: .userInitiated)

	private static let kAXMenuBarAttributeString = kAXMenuBarAttribute as CFString
	private static let kAXPressAction = "AXPress" as CFString
	private static let appActivationDelay: TimeInterval = 0.1

	init(singletonLock: SingletonLock) {
		self.singletonLock = singletonLock
		super.init()
	}

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

		let axMenuBar = menuBarElement as! AXUIElement

		let items = menuBuilder.buildMenu(
			from: axMenuBar,
			target: self,
			action: #selector(menuAction(_:))
		)

		let menu = NSMenu()
		menu.delegate = self
		menu.autoenablesItems = false
		menu.axRootElement = axMenuBar
		items.forEach(menu.addItem)
		activeMenu = menu

		menu.popUp(positioning: nil, at: location, in: nil)
	}

	private func cleanupActiveMenu() {
		guard let menu = activeMenu else { return }

		cleanupMenuItems(menu.items)

		menu.removeAllItems()

		activeMenu = nil
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
			DispatchQueue.main.asyncAfter(deadline: .now() + Self.appActivationDelay) {
				AXUIElementPerformAction(element, Self.kAXPressAction)
			}
		} else {
			AXUIElementPerformAction(element, Self.kAXPressAction)
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

	func menuWillOpen(_ menu: NSMenu) {
		if menu === activeMenu { return }

		guard menu.items.isEmpty, let axRoot = menu.axRootElement else { return }

		guard menu.isPopulatingAsynchronously == false else { return }
		menu.isPopulatingAsynchronously = true

		let placeholder = NSMenuItem(title: "Loading...", action: nil, keyEquivalent: "")
		placeholder.isEnabled = false
		menu.addItem(placeholder)
		populateSubmenuAsync(menu: menu, axRoot: axRoot, placeholder: placeholder)
	}

	func menuNeedsUpdate(_ menu: NSMenu) {
		if menu === activeMenu { return }
		guard menu.items.isEmpty, let axRoot = menu.axRootElement else { return }
		let items = menuBuilder.buildSubmenu(
			from: axRoot, target: self, action: #selector(menuAction(_:))
		)
		menu.removeAllItems()
		items.forEach(menu.addItem)
	}

	private func asyncRefreshTopLevelMenuStates(menu: NSMenu, axRoot: AXUIElement) {
		axFetchQueue.async { [weak menu] in
			guard let menu = menu else { return }
			guard let children = axRoot.getChildren() else { return }
			let attrs = [
				"AXEnabled", "AXMenuItemMarkChar", "AXMenuItemCmdChar", "AXMenuItemCmdModifiers",
			]
			let count = min(menu.items.count, children.count)
			var updates: [(index: Int, enabled: Bool?, mark: String?, cmd: String?, mods: Int?)] =
				[]
			updates.reserveCapacity(count)
			for index in 0..<count {
				let child = children[index]
				let values = child.getMultipleAttributes(attrs)
				let enabled = values?["AXEnabled"] as? Bool
				let mark = values?["AXMenuItemMarkChar"] as? String
				let cmd = values?["AXMenuItemCmdChar"] as? String
				let mods = values?["AXMenuItemCmdModifiers"] as? Int
				updates.append((index, enabled, mark, cmd, mods))
			}
			DispatchQueue.main.async {
				let itemCount = min(menu.items.count, updates.count)
				for i in 0..<itemCount {
					let update = updates[i]
					let menuItem = menu.items[update.index]
					if let enabled = update.enabled { menuItem.isEnabled = enabled }
					if let mark = update.mark, !mark.isEmpty {
						menuItem.state = mark == "✓" ? .on : (mark == "•" ? .mixed : .off)
					} else {
						menuItem.state = .off
					}
					if let cmd = update.cmd, !cmd.isEmpty {
						menuItem.keyEquivalent = cmd.lowercased()
						menuItem.keyEquivalentModifierMask = NSEvent.ModifierFlags.fromAXModifiers(
							update.mods)
					} else {
						menuItem.keyEquivalent = ""
					}
				}
			}
		}
	}

	private func populateTopLevelMenuAsync(
		menu: NSMenu, axRoot: AXUIElement, placeholder: NSMenuItem
	) {
		axFetchQueue.async { [weak self, weak menu] in
			guard let self, let menu = menu else { return }
			let items = self.menuBuilder.buildMenu(
				from: axRoot, target: self, action: #selector(self.menuAction(_:))
			)
			DispatchQueue.main.async {
				guard menu.items.contains(placeholder) else { return }
				menu.removeAllItems()
				items.forEach(menu.addItem)

				self.asyncRefreshTopLevelMenuStates(menu: menu, axRoot: axRoot)
			}
		}
	}

	private func populateSubmenuAsync(menu: NSMenu, axRoot: AXUIElement, placeholder _: NSMenuItem)
	{
		axFetchQueue.async { [weak self, weak menu] in
			guard let self, let menu = menu else { return }
			guard let children = axRoot.getChildren() else {
				DispatchQueue.main.async {
					menu.removeAllItems()
					let empty = NSMenuItem(title: "(No items)", action: nil, keyEquivalent: "")
					empty.isEnabled = false
					menu.addItem(empty)
					menu.isPopulatingAsynchronously = false
				}
				return
			}
			let attrs = [
				"AXTitle", "AXRole", "AXRoleDescription", "AXEnabled",
				"AXMenuItemMarkChar", "AXMenuItemCmdChar", "AXMenuItemCmdModifiers", "AXChildren",
			]
			var itemsData: [[String: Any]] = []
			itemsData.reserveCapacity(children.count)
			for child in children {
				if let values = child.getMultipleAttributes(attrs) {
					itemsData.append(values)
				} else {
					itemsData.append([:])
				}
			}

			DispatchQueue.main.async {
				let submenuItems = self.menuBuilder.buildSubmenu(
					fromChildren: children, itemsData: itemsData, target: self,
					action: #selector(self.menuAction(_:))
				)
				menu.removeAllItems()
				if submenuItems.isEmpty {
					let empty = NSMenuItem(title: "(No items)", action: nil, keyEquivalent: "")
					empty.isEnabled = false
					menu.addItem(empty)
				} else {
					submenuItems.forEach { menu.addItem($0) }
				}
				menu.isPopulatingAsynchronously = false
			}
		}
	}
}
