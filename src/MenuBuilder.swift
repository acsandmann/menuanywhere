import Cocoa
import ObjectiveC

class MenuBuilder {
	private static let itemAttributeKeys = [
		"AXTitle", "AXRole", "AXRoleDescription", "AXEnabled",
		"AXMenuItemMarkChar", "AXMenuItemCmdChar", "AXMenuItemCmdModifiers", "AXChildren",
	]
	private let boldFont = NSFontManager.shared.convert(
		NSFont.menuFont(ofSize: NSFont.systemFontSize), toHaveTrait: .boldFontMask
	)

	func buildMenu(from element: AXUIElement, target: AnyObject?, action: Selector?) -> [NSMenuItem]
	{
		return autoreleasepool {
			buildMenuItems(from: element, target: target, action: action, isSubmenu: false)
		}
	}

	func buildSubmenu(from element: AXUIElement, target: AnyObject?, action: Selector?)
		-> [NSMenuItem]
	{
		return autoreleasepool {
			buildMenuItems(from: element, target: target, action: action, isSubmenu: true)
		}
	}

	func buildSubmenu(
		fromChildren children: [AXUIElement],
		itemsData: [[String: Any]],
		target: AnyObject?,
		action: Selector?
	) -> [NSMenuItem] {
		return buildMenuItems(
			children: children,
			itemsData: itemsData,
			target: target,
			action: action,
			isSubmenu: true
		)
	}

	private func buildMenuItems(
		from element: AXUIElement, target: AnyObject?, action: Selector?, isSubmenu: Bool
	) -> [NSMenuItem] {
		guard let children = element.getChildren() else { return [] }

		let itemsData = autoreleasepool {
			var results: [[String: Any]] = []
			results.reserveCapacity(children.count)

			for child in children {
				if let values = child.getMultipleAttributes(Self.itemAttributeKeys) {
					results.append(values)
				} else {
					results.append([:])
				}
			}

			return results
		}

		return buildMenuItems(
			children: children, itemsData: itemsData, target: target, action: action,
			isSubmenu: isSubmenu
		)
	}

	private func buildMenuItems(
		children: [AXUIElement],
		itemsData: [[String: Any]],
		target: AnyObject?,
		action: Selector?,
		isSubmenu: Bool
	) -> [NSMenuItem] {
		var items: [NSMenuItem] = []
		items.reserveCapacity(children.count)

		var appleItem: NSMenuItem?
		var isFirst = true
		var needsSeparator = false

		for (index, child) in children.enumerated() {
			autoreleasepool {
				let itemData = itemsData[index]
				let isApple = isAppleMenuItem(
					title: itemData["AXTitle"] as? String, itemData: itemData
				)
				if let item = buildSingleMenuItem(
					from: child,
					itemData: itemData,
					target: target,
					action: action,
					isSubmenu: isSubmenu,
					isFirst: &isFirst,
					isApple: isApple
				) {
					if item.isSeparatorItem {
						needsSeparator = true
						return
					}

					if needsSeparator, !items.isEmpty {
						items.append(.separator())
						needsSeparator = false
					}

					if isApple {
						appleItem = item
					} else {
						items.append(item)
					}
				}
			}
		}

		if let apple = appleItem {
			if !items.isEmpty, items.last?.isSeparatorItem == false {
				items.append(.separator())
			}
			items.append(apple)
		}

		return items
	}

	private func buildSingleMenuItem(
		from child: AXUIElement,
		itemData: [String: Any],
		target: AnyObject?,
		action: Selector?,
		isSubmenu: Bool,
		isFirst: inout Bool,
		isApple: Bool
	) -> NSMenuItem? {
		let title = itemData["AXTitle"] as? String ?? ""
		let role = itemData["AXRole"] as? String ?? ""

		if title.isEmpty || role == "AXSeparator" {
			return .separator()
		}

		let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
		item.representedObject = child

		item.isEnabled = itemData["AXEnabled"] as? Bool ?? true

		if let mark = itemData["AXMenuItemMarkChar"] as? String, !mark.isEmpty {
			item.state = mark == "✓" ? .on : (mark == "•" ? .mixed : .off)
		}

		setKeyboardShortcut(for: item, from: itemData)

		let hasSubmenu = handleSubmenu(for: item, from: itemData, target: target, action: action)

		if !hasSubmenu && item.isEnabled {
			item.target = target
			item.action = action
		}

		if !isSubmenu, isFirst || isApple {
			item.attributedTitle = NSAttributedString(
				string: item.title,
				attributes: [.font: boldFont]
			)
			if !isApple {
				isFirst = false
			}
		}

		return item
	}

	private func setKeyboardShortcut(for item: NSMenuItem, from values: [String: Any]) {
		guard let cmd = values["AXMenuItemCmdChar"] as? String, !cmd.isEmpty else { return }

		item.keyEquivalent = cmd.lowercased()
		let flags = NSEvent.ModifierFlags.fromAXModifiers(values["AXMenuItemCmdModifiers"] as? Int)
		item.keyEquivalentModifierMask = flags
	}

	private func handleSubmenu(
		for item: NSMenuItem,
		from values: [String: Any],
		target: AnyObject?,
		action _: Selector?
	) -> Bool {
		guard let subChildren = values["AXChildren"] as? [AXUIElement],
			!subChildren.isEmpty,
			let firstSub = subChildren.first,
			let subRole = firstSub.getAttribute("AXRole") as? String,
			subRole == "AXMenu"
		else {
			return false
		}

		let submenu = NSMenu(title: item.title)

		submenu.delegate = target as? NSMenuDelegate
		submenu.axRootElement = firstSub
		item.submenu = submenu

		return true
	}
}

extension MenuBuilder {
	fileprivate func isAppleMenuItem(title: String?, itemData: [String: Any]) -> Bool {
		return title == "Apple" || (itemData["AXRoleDescription"] as? String) == "Apple menu"
	}
}

private var kAXRootElementAssociatedKey: UInt8 = 0
private var kIsPopulatingAssociatedKey: UInt8 = 0

extension NSMenu {
	var axRootElement: AXUIElement? {
		get {
			guard let obj = objc_getAssociatedObject(self, &kAXRootElementAssociatedKey) else {
				return nil
			}
			return (obj as! AXUIElement)
		}
		set {
			objc_setAssociatedObject(
				self, &kAXRootElementAssociatedKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
			)
		}
	}

	var isPopulatingAsynchronously: Bool {
		get {
			return (objc_getAssociatedObject(self, &kIsPopulatingAssociatedKey) as? NSNumber)?
				.boolValue ?? false
		}
		set {
			objc_setAssociatedObject(
				self, &kIsPopulatingAssociatedKey, NSNumber(value: newValue),
				.OBJC_ASSOCIATION_RETAIN_NONATOMIC
			)
		}
	}
}

extension AXUIElement {
	func getAttribute(_ name: String) -> Any? {
		return autoreleasepool {
			var value: AnyObject?
			return AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success
				? value : nil
		}
	}

	func getChildren() -> [AXUIElement]? {
		return autoreleasepool {
			var value: AnyObject?
			guard AXUIElementCopyAttributeValue(self, "AXChildren" as CFString, &value) == .success,
				let children = value as? [AXUIElement], !children.isEmpty
			else {
				return nil
			}
			return children
		}
	}

	func getMultipleAttributes(_ names: [String]) -> [String: Any]? {
		return autoreleasepool {
			let attrs = names as CFArray
			var values: CFArray?
			let options = AXCopyMultipleAttributeOptions(rawValue: 0)

			guard AXUIElementCopyMultipleAttributeValues(self, attrs, options, &values) == .success,
				let results = values as? [Any], results.count == names.count
			else { return nil }

			var dict: [String: Any] = [:]
			dict.reserveCapacity(names.count)

			for i in 0..<names.count {
				let value = results[i]
				if !(value is NSNull) {
					dict[names[i]] = value
				}
			}
			return dict.isEmpty ? nil : dict
		}
	}
}

extension NSEvent.ModifierFlags {
	// AXMenuItemCmdModifiers
	static func fromAXModifiers(_ maybeMods: Int?) -> NSEvent.ModifierFlags {
		guard let mods = maybeMods else { return [.command] }
		var flags: NSEvent.ModifierFlags = []
		if mods & 1 != 0 { flags.insert(.shift) }
		if mods & 2 != 0 { flags.insert(.option) }
		if mods & 4 != 0 { flags.insert(.control) }
		if mods & 8 != 0 { flags.insert(.command) }
		if flags.isEmpty { flags.insert(.command) }
		return flags
	}
}
