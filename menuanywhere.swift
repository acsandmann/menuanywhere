import Carbon
import Cocoa

let keyCodeMap: [String: UInt32] = [
	"a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C),
	"d": UInt32(kVK_ANSI_D), "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F),
	"g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H), "i": UInt32(kVK_ANSI_I),
	"j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
	"m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O),
	"p": UInt32(kVK_ANSI_P), "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R),
	"s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T), "u": UInt32(kVK_ANSI_U),
	"v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
	"y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),

	"0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
	"3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
	"6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
	"9": UInt32(kVK_ANSI_9),

	"space": UInt32(kVK_Space),
	"return": UInt32(kVK_Return),
	"tab": UInt32(kVK_Tab),
	"delete": UInt32(kVK_Delete),
	"backspace": UInt32(kVK_Delete),
	"escape": UInt32(kVK_Escape),

	"f1": UInt32(kVK_F1), "f2": UInt32(kVK_F2), "f3": UInt32(kVK_F3),
	"f4": UInt32(kVK_F4), "f5": UInt32(kVK_F5), "f6": UInt32(kVK_F6),
	"f7": UInt32(kVK_F7), "f8": UInt32(kVK_F8), "f9": UInt32(kVK_F9),
	"f10": UInt32(kVK_F10), "f11": UInt32(kVK_F11), "f12": UInt32(kVK_F12),
]

let modifierMap: [String: UInt32] = [
	"control": UInt32(controlKey),
	"shift": UInt32(shiftKey),
	"option": UInt32(optionKey),
	"command": UInt32(cmdKey),
]

private let kAXTitleAttributeString = kAXTitleAttribute as String
private let kAXRoleAttributeString = kAXRoleAttribute as String
private let kAXRoleDescriptionAttributeString = kAXRoleDescriptionAttribute as String
private let kAXEnabledAttributeString = kAXEnabledAttribute as String
private let kAXMenuItemMarkCharAttributeString = kAXMenuItemMarkCharAttribute as String
private let kAXMenuItemCmdCharAttributeString = kAXMenuItemCmdCharAttribute as String
private let kAXMenuItemCmdModifiersAttributeString = kAXMenuItemCmdModifiersAttribute as String
private let kAXChildrenAttributeString = kAXChildrenAttribute as String
private let kAXMenuItemRoleString = kAXMenuItemRole as String
private let kAXSeparatorRoleString = "AXSeparator"
private let kAXMenuRoleString = "AXMenu"

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
	static let hotKeySignature = OSType("Mbar".fourCharCode)
	static let hotKeyIdValue: UInt32 = 1

	private var hotKeyRef: EventHotKeyRef?
	private var eventHandlerRef: EventHandlerRef?
	private weak var currentApp: NSRunningApplication?
	private var activeMenu: NSMenu?

	private var hotKeyCode: UInt32?
	private var hotKeyModifiers: UInt32?

	private lazy var boldMenuFont: NSFont = {
		let font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
		return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
	}()

	static func loadHotKeyConfig() -> HotKeyConfig {
		let env = ProcessInfo.processInfo.environment
		let xdgConfigHome = env["XDG_CONFIG_HOME"] ?? ("~/.config" as NSString).expandingTildeInPath
		let configPath = (xdgConfigHome as NSString).appendingPathComponent(
			"menuanywhere/config.json")
		let configURL = URL(fileURLWithPath: configPath)

		do {
			let data = try Data(contentsOf: configURL)
			let config = try JSONDecoder().decode(HotKeyConfig.self, from: data)
			print("Loaded configuration from \(configPath)")
			return config
		} catch {
			print("Failed to load or parse configuration from \(configPath): \(error)")
			let defaultConfig = HotKeyConfig(key: "m", modifiers: ["control"])
			print(
				"Using default configuration: \(defaultConfig.modifiers.joined(separator: "+"))+\(defaultConfig.key)"
			)
			return defaultConfig
		}
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		setupHotKeyFromConfig()

		registerHotKey(keyCode: hotKeyCode!, modifiers: hotKeyModifiers!)
		setupCarbonEventHandlers()
		print("Application finished launching. Press Ctrl+M to show the active app's menu.")
	}

	func setupHotKeyFromConfig() {
		let config = AppDelegate.loadHotKeyConfig()

		guard let keyCode = keyCodeMap[config.key.lowercased()] else {
			print(
				"Error: Unknown key '\(config.key)' found in configuration. Cannot register hotkey."
			)
			return
		}
		self.hotKeyCode = keyCode

		var combinedModifiers: UInt32 = 0
		for modString in config.modifiers {
			if let modFlag = modifierMap[modString.lowercased()] {
				combinedModifiers |= modFlag
			} else {
				print(
					"Warning: Unknown modifier string '\(modString)' in configuration. Ignoring it."
				)
			}
		}
		self.hotKeyModifiers = combinedModifiers

		print(
			"Hotkey configured: Key=\(config.key) (Code:\(keyCode)), Modifiers=\(config.modifiers) (Flags:\(combinedModifiers))"
		)
	}

	func applicationWillTerminate(_ notification: Notification) {
		print("Application will terminate. Unregistering hotkey and handler.")
		unregisterHotKey()
		removeCarbonEventHandlers()
	}

	private func setupCarbonEventHandlers() {
		let unretainedSelf = Unmanaged.passUnretained(self).toOpaque()
		var eventType = EventTypeSpec(
			eventClass: OSType(kEventClassKeyboard),
			eventKind: UInt32(kEventHotKeyPressed)
		)

		let installStatus = InstallEventHandler(
			GetApplicationEventTarget(),
			hotKeyHandler,
			1,
			&eventType,
			unretainedSelf,
			&eventHandlerRef)

		guard installStatus == noErr else {
			print("Fatal Error: Could not install Carbon event handler: \(installStatus).")
			NSApp.terminate(self)
			return
		}
		print("Carbon event handler installed successfully.")
	}

	private func removeCarbonEventHandlers() {
		if let handlerRef = eventHandlerRef {
			RemoveEventHandler(handlerRef)
			eventHandlerRef = nil
			print("Carbon event handler removed.")
		}
	}

	private func registerHotKey(keyCode: UInt32, modifiers: UInt32) {
		let hotKeyID = EventHotKeyID(
			signature: AppDelegate.hotKeySignature, id: AppDelegate.hotKeyIdValue)

		let status = RegisterEventHotKey(
			keyCode,
			modifiers,
			hotKeyID,
			GetApplicationEventTarget(),
			0,
			&hotKeyRef)
		guard status == noErr else {
			print("Error: Failed to register hot key \(status). Another app might be using it.")
			return
		}
		print("Hotkey registered successfully.")
	}

	private func unregisterHotKey() {
		if let ref = hotKeyRef {
			UnregisterEventHotKey(ref)
			hotKeyRef = nil
			print("Hotkey unregistered.")
		}
	}

	func handleHotKey() {
		unregisterHotKey()
		print("Hotkey Activated!")
		let location = NSEvent.mouseLocation
		showAppMenu(at: location)
	}

	private func getMenuBarOwningApp() -> NSRunningApplication? {
		return NSWorkspace.shared.frontmostApplication
	}

	private func getAppMenu(for app: NSRunningApplication) -> [NSMenuItem]? {
		let appElement = AXUIElementCreateApplication(app.processIdentifier)
		var menuBar: AnyObject?

		let error = AXUIElementCopyAttributeValue(
			appElement,
			kAXMenuBarAttribute as CFString,
			&menuBar)

		guard error == .success, let menuBarUncast = menuBar else {
			print(
				"Failed to get menu bar for app \(app.localizedName ?? "unknown") - AXError: \(error.rawValue)"
			)
			return nil
		}

		return buildMenuItems(from: menuBarUncast as! AXUIElement, isSubmenu: false)
	}
	private func buildMenuItems(from element: AXUIElement, isSubmenu: Bool) -> [NSMenuItem]? {
		guard let childArray = element.getChildren(), !childArray.isEmpty else {
			return nil
		}

		var menuItems: [NSMenuItem] = []
		var appleMenuItem: NSMenuItem? = nil
		var isFirstRealItem = true

		let attributesToFetch = [
			kAXTitleAttributeString,
			kAXRoleAttributeString,
			kAXRoleDescriptionAttributeString,
			kAXEnabledAttributeString,
			kAXMenuItemMarkCharAttributeString,
			kAXMenuItemCmdCharAttributeString,
			kAXMenuItemCmdModifiersAttributeString,
			kAXChildrenAttributeString,
		]

		for axItem in childArray {
			guard let attrs = axItem.getMultipleAttributes(attributesToFetch) else {
				print("Warning: Could not get attributes for an AXItem, skipping.")
				continue
			}

			let title: String = attrs[kAXTitleAttributeString] as? String ?? ""
			let role: String? = attrs[kAXRoleAttributeString] as? String

			if title.isEmpty || role == kAXSeparatorRoleString {
				if !menuItems.isEmpty && menuItems.last?.isSeparatorItem == false {
					menuItems.append(NSMenuItem.separator())
				}
				continue
			}

			let roleDescription: String? = attrs[kAXRoleDescriptionAttributeString] as? String
			let isAppleMenu = !isSubmenu && (title == "Apple" || roleDescription == "Apple menu")

			let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
			menuItem.target = self
			menuItem.representedObject = axItem

			let isEnabled: Bool = attrs[kAXEnabledAttributeString] as? Bool ?? true
			menuItem.isEnabled = isEnabled

			if let markChar = attrs[kAXMenuItemMarkCharAttributeString] as? String,
				!markChar.isEmpty
			{
				switch markChar {
				case "✓": menuItem.state = .on
				case "•": menuItem.state = .mixed
				default: menuItem.state = .off
				}
			} else {
				menuItem.state = .off
			}

			if let cmdChar = attrs[kAXMenuItemCmdCharAttributeString] as? String, !cmdChar.isEmpty {
				menuItem.keyEquivalent = cmdChar.lowercased()

				var flags: NSEvent.ModifierFlags = [.command]
				if let axModifiers = attrs[kAXMenuItemCmdModifiersAttributeString] as? Int {
					flags = []
					if axModifiers & 1 != 0 { flags.insert(.shift) }  // kAXMenuItemCmdShiftKeyMask = 1
					if axModifiers & 2 != 0 { flags.insert(.option) }  // kAXMenuItemCmdOptionKeyMask = 2
					if axModifiers & 4 != 0 { flags.insert(.control) }  // kAXMenuItemCmdControlKeyMask = 4
					if axModifiers & 8 != 0 { flags.insert(.command) }  // kAXMenuItemCmdKeyMask = 8
					if flags.isEmpty && axModifiers == 0 { flags.insert(.command) }
					if flags.isEmpty && axModifiers != 0 {
						print(
							"Warning: Unknown kAXMenuItemCmdModifiersAttribute value: \(axModifiers) for item '\(title)'. Defaulting to Command."
						)
						flags.insert(.command)
					}
				}
				if !flags.isEmpty {
					menuItem.keyEquivalentModifierMask = flags
				} else if menuItem.keyEquivalent.isEmpty {
					menuItem.keyEquivalentModifierMask = []
				}

			} else {
				menuItem.keyEquivalentModifierMask = []
			}

			var hasValidSubmenu = false
			if let subMenuChildren = attrs[kAXChildrenAttributeString] as? [AXUIElement],
				!subMenuChildren.isEmpty
			{
				if let firstChild = subMenuChildren.first {
					if let firstChildRole = firstChild.getAttributeValue(kAXRoleAttributeString)
						as? String,
						firstChildRole == kAXMenuRoleString
					{
						if let subMenuItems = buildMenuItems(from: firstChild, isSubmenu: true) {
							let submenu = NSMenu(title: title)
							submenu.delegate = self
							subMenuItems.forEach { submenu.addItem($0) }
							menuItem.submenu = submenu
							hasValidSubmenu = true
						}
					}
				}
			}

			if !hasValidSubmenu {
				if menuItem.isEnabled {
					menuItem.action = #selector(menuItemAction(_:))
				} else {
					menuItem.action = nil
					menuItem.target = nil
				}
			}

			if (!isSubmenu && isFirstRealItem) || isAppleMenu {
				menuItem.attributedTitle = NSAttributedString(
					string: title, attributes: [.font: boldMenuFont])
				if !isAppleMenu { isFirstRealItem = false }
			}

			if isAppleMenu {
				appleMenuItem = menuItem
			} else {
				menuItems.append(menuItem)
			}
		}

		if let finalAppleMenuItem = appleMenuItem {
			if !menuItems.isEmpty && !menuItems.last!.isSeparatorItem {
				menuItems.append(NSMenuItem.separator())
			}
			menuItems.append(finalAppleMenuItem)
		}

		return menuItems.isEmpty ? nil : menuItems
	}

	@objc private func menuItemAction(_ sender: NSMenuItem) {
		print("Menu Item Action: \(sender.title)")
		guard let representedObject = sender.representedObject,
			CFGetTypeID(representedObject as CFTypeRef) == AXUIElementGetTypeID()
		else {
			print(
				"Error: Menu item '\(sender.title)' does not have a valid AXUIElement."
			)
			return
		}
		let axElement = representedObject as! AXUIElement

		guard let targetApp = self.currentApp, !targetApp.isTerminated else {
			print(
				"Error: Target application \(self.currentApp?.localizedName ?? "unknown") is terminated."
			)
			self.currentApp = getMenuBarOwningApp()
			guard let refreshedApp = self.currentApp, !refreshedApp.isTerminated else {
				print("Could not re-acquire a running target app.")
				return
			}
			print("Refreshed target app to: \(refreshedApp.localizedName ?? "Unknown")")
			refreshedApp.activate(options: [])
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
				self.performAXPress(on: axElement, title: sender.title)
			}
			return
		}

		if !targetApp.isActive {
			print("Target app \(targetApp.localizedName ?? "") is not active. Activating...")
			targetApp.activate(options: [])
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
				self.performAXPress(on: axElement, title: sender.title)
			}
		} else {
			performAXPress(on: axElement, title: sender.title)
		}
	}

	private func performAXPress(on axElement: AXUIElement, title: String) {
		let error = AXUIElementPerformAction(axElement, kAXPressAction as CFString)
		if error != .success {
			print(
				"Error performing AXPress action on '\(title)': AXError \(error.rawValue)"
			)
		} else {
			print("Successfully performed AXPress on '\(title)'")
		}
	}

	private func showAppMenu(at position: NSPoint) {
		print("Attempting to show app menu at \(position)...")
		guard let app = getMenuBarOwningApp() else {
			print("Failed to get frontmost app (No app seems to be active?).")
			return
		}
		print("Frontmost app: \(app.localizedName ?? "Unknown") (PID: \(app.processIdentifier))")
		currentApp = app

		guard let menuItems = getAppMenu(for: app), !menuItems.isEmpty else {
			print(
				"Failed to get menu items or menu is empty for \(app.localizedName ?? "unknown app"). Check Accessibility Permissions."
			)
			return
		}
		print("Retrieved \(menuItems.count) top-level menu items.")

		let menu = NSMenu()
		menuItems.forEach { menu.addItem($0) }
		self.activeMenu = menu

		menu.popUp(positioning: nil, at: position, in: nil)
		print("Menu popped up.")
	}

	@objc func menuDidEndTracking(_ notification: Notification) {
		if activeMenu == notification.object as? NSMenu {
			self.activeMenu = nil

			registerHotKey(keyCode: hotKeyCode!, modifiers: hotKeyModifiers!)
		}
	}
}

private func hotKeyHandler(
	nextHandler: EventHandlerCallRef?,
	theEvent: EventRef?,
	userData: UnsafeMutableRawPointer?
) -> OSStatus {
	guard let userData = userData else {
		print("Error: Hotkey handler called without valid userData.")
		return OSStatus(eventNotHandledErr)
	}

	let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()

	var hotKeyID = EventHotKeyID()
	guard let event = theEvent else {
		print("Error: Hotkey handler received nil event.")
		return OSStatus(eventNotHandledErr)
	}

	let status = GetEventParameter(
		event,
		EventParamName(kEventParamDirectObject),
		EventParamType(typeEventHotKeyID), nil,
		MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

	guard status == noErr else {
		print("Error getting hot key ID parameter: \(status)")
		return status
	}

	if hotKeyID.signature == AppDelegate.hotKeySignature && hotKeyID.id == AppDelegate.hotKeyIdValue
	{
		DispatchQueue.main.async {
			appDelegate.handleHotKey()
		}
		return noErr
	}

	return OSStatus(eventNotHandledErr)
}

extension String {
	fileprivate var fourCharCode: FourCharCode {
		guard !self.isEmpty else { return 0 }
		var chars = self.prefix(4).utf8.map { UInt8($0) }
		while chars.count < 4 { chars.append(UInt8(ascii: " ")) }
		var result: FourCharCode = 0
		for byte in chars { result = (result << 8) + FourCharCode(byte) }
		return result
	}
}

extension AXUIElement {
	func getMultipleAttributes(_ attributes: [String]) -> [String: Any]? {
		let attrArray = attributes as CFArray
		var valuesRef: CFArray?

		let options: AXCopyMultipleAttributeOptions = AXCopyMultipleAttributeOptions(rawValue: 0)

		let error = AXUIElementCopyMultipleAttributeValues(
			self,
			attrArray,
			options,
			&valuesRef
		)

		guard error == .success else {
			return nil
		}

		guard let values = valuesRef as? [Any] else {
			return nil
		}

		guard values.count == attributes.count else {
			return nil
		}

		var results: [String: Any] = [:]
		for (index, attribute) in attributes.enumerated() {
			let value = values[index]
			if CFGetTypeID(value as CFTypeRef) != AXValueGetTypeID()
				|| AXValueGetType(value as! AXValue) != AXValueType.illegal
			{
				results[attribute] = value
			}
		}

		return results.isEmpty ? nil : results
	}

	func getAttributeValue(_ attribute: String) -> Any? {
		var value: AnyObject?
		let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)

		if result == .success, let value = value {
			return value
		} else {
			return nil
		}
	}

	func getChildren() -> [AXUIElement]? {
		guard let children = getAttributeValue(kAXChildrenAttribute) else {
			return nil
		}

		guard let childrenElements = children as? [AXUIElement] else {
			return nil
		}

		return childrenElements.isEmpty ? nil : childrenElements
	}
}

struct HotKeyConfig: Codable {
	let key: String
	let modifiers: [String]
}

let delegate = AppDelegate()

let application = NSApplication.shared
application.delegate = delegate

struct AccessibilityManager {

	private static var permissionTimer: Timer?

	static func ensurePermissions() {
		guard
			!AXIsProcessTrustedWithOptions(
				[kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
		else { return }

		print("accessibility permissions not granted. system prompt will be displayed")
		print("waiting for permission to be granted...")

		permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
			if AXIsProcessTrusted() {
				print(
					"permission granted\nquitting to allow the service manager to restart the process"
				)
				permissionTimer?.invalidate()
				NSApp.terminate(nil)
			}
		}
	}
}

AccessibilityManager.ensurePermissions()

NotificationCenter.default.addObserver(
	delegate,
	selector: #selector(delegate.menuDidEndTracking(_:)),
	name: NSMenu.didEndTrackingNotification,
	object: nil)

print("Starting application run loop (NSApplicationMain)...")
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

print("Application run loop finished.")
