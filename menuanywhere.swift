import Carbon
import Cocoa

let keyCodeMap: [String: UInt32] = [
  "A": UInt32(kVK_ANSI_A), "B": UInt32(kVK_ANSI_B), "C": UInt32(kVK_ANSI_C),
  "D": UInt32(kVK_ANSI_D), "E": UInt32(kVK_ANSI_E), "F": UInt32(kVK_ANSI_F),
  "G": UInt32(kVK_ANSI_G), "H": UInt32(kVK_ANSI_H), "I": UInt32(kVK_ANSI_I),
  "J": UInt32(kVK_ANSI_J), "K": UInt32(kVK_ANSI_K), "L": UInt32(kVK_ANSI_L),
  "M": UInt32(kVK_ANSI_M), "N": UInt32(kVK_ANSI_N), "O": UInt32(kVK_ANSI_O),
  "P": UInt32(kVK_ANSI_P), "Q": UInt32(kVK_ANSI_Q), "R": UInt32(kVK_ANSI_R),
  "S": UInt32(kVK_ANSI_S), "T": UInt32(kVK_ANSI_T), "U": UInt32(kVK_ANSI_U),
  "V": UInt32(kVK_ANSI_V), "W": UInt32(kVK_ANSI_W), "X": UInt32(kVK_ANSI_X),
  "Y": UInt32(kVK_ANSI_Y), "Z": UInt32(kVK_ANSI_Z),

  "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
  "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
  "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
  "9": UInt32(kVK_ANSI_9),

  "Space": UInt32(kVK_Space),
  "Return": UInt32(kVK_Return),
  "Tab": UInt32(kVK_Tab),
  "Delete": UInt32(kVK_Delete),
  "Backspace": UInt32(kVK_Delete),
  "Escape": UInt32(kVK_Escape),

  "F1": UInt32(kVK_F1), "F2": UInt32(kVK_F2), "F3": UInt32(kVK_F3),
  "F4": UInt32(kVK_F4), "F5": UInt32(kVK_F5), "F6": UInt32(kVK_F6),
  "F7": UInt32(kVK_F7), "F8": UInt32(kVK_F8), "F9": UInt32(kVK_F9),
  "F10": UInt32(kVK_F10), "F11": UInt32(kVK_F11), "F12": UInt32(kVK_F12),
]

let modifierMap: [String: UInt32] = [
  "control": UInt32(controlKey),
  "shift": UInt32(shiftKey),
  "option": UInt32(optionKey),
  "command": UInt32(cmdKey),
]

private let kAXSeparatorRoleString = "AXSeparator"
private let kAXMenuRoleString = "AXMenu"
private let queue = DispatchQueue(label: "com.acsandmann.menu_anywhere.queue")

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  static let hotKeySignature = OSType("Mbar".fourCharCode)
  static let hotKeyIdValue: UInt32 = 1

  private var hotKeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?
  private weak var currentApp: NSRunningApplication?
  private var activeMenu: NSMenu?

  private let config: HotKeyConfig? = initConfig()
  private var keyCode: UInt32?
  private var combinedModifiers: UInt32?

  static func loadHotKeyConfig() -> HotKeyConfig? {
  let env = ProcessInfo.processInfo.environment
  let xdgConfigHome = env["XDG_CONFIG_HOME"] ?? ("~/.config" as NSString).expandingTildeInPath
  let configPath = (xdgConfigHome as NSString).appendingPathComponent("menuanywhere/config.json")
    let configURL = URL(fileURLWithPath: configPath)
    do {
      let data = try Data(contentsOf: configURL)
      let config = try JSONDecoder().decode(HotKeyConfig.self, from: data)
      print("Loaded configuration from \(configPath)")
      return config
    } catch {
      print("Failed to load configuration from \(configPath): \(error)")
      print("Using default configuration: ctrl+M")
      return HotKeyConfig(key: "M", modifiers: ["control"])
    }
  }

  static func initConfig() -> HotKeyConfig? {
    guard let config = loadHotKeyConfig() else {
      print("Error: Could not load hotkey configuration.")
      return
    }

    guard let keyCode = keyCodeMap[config.key] else {
      print("Error: Unknown key '\(config.key)' found in configuration. Hotkey not registered.")
      return
    }

    var combinedModifiers: UInt32 = 0
    for modString in config.modifiers {
      if let modFlag = modifierMap[modString.lowercased()] {
        combinedModifiers |= modFlag
      } else {
        print("Warning: Unknown modifier string '\(modString)' in configuration. Ignoring it.")
      }
    }

    keyCode = keyCode
    combinedModifiers = combinedModifiers

    return config
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard checkAccessibilityPermissions() else {
      print("Accessibility permissions denied or user chose to quit. Exiting.")
      return
    }
    print("Accessibility access granted.")

    setupCarbonEventHandlers()
    registerHotKey()

    print("Application finished launching. Press Ctrl+M to show the active app's menu.")
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

  private func registerHotKey() {
    let hotKeyID = EventHotKeyID(
      signature: AppDelegate.hotKeySignature, id: AppDelegate.hotKeyIdValue)

    let status = RegisterEventHotKey(
      keyCode!,
      combinedModifiers!,
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
    var children: AnyObject?
    let childrenResult = AXUIElementCopyAttributeValue(
      element, kAXChildrenAttribute as CFString, &children)

    guard childrenResult == .success, let childArray = children as? [AXUIElement],
      !childArray.isEmpty
    else {
      if !isSubmenu {
        print(
          "Could not get children for element (perhaps menu bar?). Error: \(childrenResult)"
        )
      }
      return nil
    }

    var menuItems: [NSMenuItem] = []
    var isFirstRealItem = true

    for axItem in childArray {
      let title: String = axItem.copyAttributeValue(kAXTitleAttribute, logOnError: false) ?? ""
      let role: String? = axItem.copyAttributeValue(kAXRoleAttribute, logOnError: false)

      if !isSubmenu
        && (title == "Apple"
          || axItem.copyAttributeValue(kAXRoleDescriptionAttribute, logOnError: false)
            == "Apple menu")
      {
        continue
      }

      if title.isEmpty || role == kAXSeparatorRoleString {
        if menuItems.last?.isSeparatorItem == false {
          menuItems.append(NSMenuItem.separator())
        }
        continue
      }

      let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      menuItem.target = self
      menuItem.representedObject = axItem

      if !isSubmenu && isFirstRealItem {
        let font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
        let boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        let attributes: [NSAttributedString.Key: Any] = [.font: boldFont]
        menuItem.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        isFirstRealItem = false
      } else {
        menuItem.title = title
      }

      let isEnabled: Bool = axItem.copyAttributeValue(kAXEnabledAttribute, logOnError: true) ?? true
      menuItem.isEnabled = isEnabled

      if let markChar: String = axItem.copyAttributeValue(
        kAXMenuItemMarkCharAttribute, logOnError: false), !markChar.isEmpty
      {
        if markChar == "✓" {
          menuItem.state = .on
        } else if markChar == "•" {
          menuItem.state = .mixed
        } else {
          menuItem.state = .off
        }
      } else {
        menuItem.state = .off
      }

      if let cmdChar: String = axItem.copyAttributeValue(
        kAXMenuItemCmdCharAttribute, logOnError: false), !cmdChar.isEmpty
      {
        menuItem.keyEquivalent = cmdChar.lowercased()

        if let axModifiers: Int = axItem.copyAttributeValue(
          kAXMenuItemCmdModifiersAttribute, logOnError: false)
        {
          var flags: NSEvent.ModifierFlags = []

          if axModifiers == 0 || (axModifiers & 8 != 0) { flags.insert(.command) }
          if axModifiers & 1 != 0 { flags.insert(.shift) }
          if axModifiers & 2 != 0 { flags.insert(.option) }
          if axModifiers & 4 != 0 { flags.insert(.control) }
          if !flags.isEmpty {
            menuItem.keyEquivalentModifierMask = flags
          } else if axModifiers == 0 && !flags.contains(.command) {
            menuItem.keyEquivalentModifierMask = .command
          } else if axModifiers != 0 {
            print("Unrecognized AXModifiers \(axModifiers) for item '\(title)'")
            menuItem.keyEquivalentModifierMask = .command
          }
        } else {
          menuItem.keyEquivalentModifierMask = .command
        }
      }

      var subMenuElement: AnyObject?
      let subMenuResult = AXUIElementCopyAttributeValue(
        axItem, kAXChildrenAttribute as CFString, &subMenuElement)

      if subMenuResult == .success,
        let subMenuChildren = subMenuElement as? [AXUIElement],
        !subMenuChildren.isEmpty,
        let firstChild = subMenuChildren.first,
        let firstChildRole: String = firstChild.copyAttributeValue(kAXRoleAttribute),
        firstChildRole == kAXMenuRoleString,
        let subMenuItems = buildMenuItems(from: firstChild, isSubmenu: true)
      {
        let submenu = NSMenu(title: title)
        submenu.delegate = self
        subMenuItems.forEach { submenu.addItem($0) }
        menuItem.submenu = submenu

      } else {
        if menuItem.isEnabled {
          menuItem.action = #selector(menuItemAction(_:))
        } else {
          menuItem.action = nil
          menuItem.target = nil
        }
      }

      menuItems.append(menuItem)
    }

    return menuItems.isEmpty ? nil : menuItems
  }

  @objc private func menuItemAction(_ sender: NSMenuItem) {
    print("Menu Item Action: \(sender.title)")
    guard let axObject = sender.representedObject,
      CFGetTypeID(axObject as! CFTypeRef) == AXUIElementGetTypeID()
    else {
      print("Error: Menu item '\(sender.title)' does not have a valid associated AXUIElement.")
      return
    }
    let axElement = axObject as! AXUIElement

    guard let targetApp = self.currentApp, !targetApp.isTerminated else {
      print(
        "Error: Target application \(self.currentApp?.localizedName ?? "unknown") is terminated.")
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

      registerHotKey()
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

  if hotKeyID.signature == AppDelegate.hotKeySignature && hotKeyID.id == AppDelegate.hotKeyIdValue {
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
  func copyAttributeValue<T>(_ attribute: String, logOnError: Bool = false) -> T? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
    guard result == .success else {
      if logOnError {
        print("Failed to get attribute '\(attribute)'")
      }
      return nil
    }
    if value == nil || value is NSNull {
      return nil
    }
    guard let typedValue = value as? T else {
      if logOnError {
        print(
          "Failed to cast attribute '\(attribute)' value (\(String(describing: value))) to type \(T.self)"
        )
      }
      return nil
    }
    return typedValue
  }
}

struct HotKeyConfig: Codable {
  let key: String
  let modifiers: [String]
}

let delegate = AppDelegate()

let application = NSApplication.shared
application.delegate = delegate

func checkAccessibilityPermissions() -> Bool {
  let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
  let options = [checkOptPrompt: true] as CFDictionary
  let accessEnabled = AXIsProcessTrustedWithOptions(options)

  if !accessEnabled {
    let alert = NSAlert()
    alert.messageText = "Accessibility Access Required"
    alert.informativeText =
      "To control other applications' menus, please enable Accessibility access for this application in System Settings > Privacy & Security > Accessibility, then relaunch."
    alert.alertStyle = .critical
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Quit")

    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
      NSWorkspace.shared.open(
        URL(
          string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    NSApp.terminate(nil)
    return false
  }
  print("Accessibility access granted.")
  return true
}

guard checkAccessibilityPermissions() else {
  print("Accessibility permissions denied or user chose to quit. Exiting.")
  exit(1)
}

NotificationCenter.default.addObserver(
  delegate,
  selector: #selector(delegate.menuDidEndTracking(_:)),
  name: NSMenu.didEndTrackingNotification,
  object: nil)

print("Starting application run loop (NSApplicationMain)...")
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

print("Application run loop finished.")
