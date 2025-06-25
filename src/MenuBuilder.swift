import Cocoa

class MenuBuilder {
	private let boldFont = NSFontManager.shared.convert(
		NSFont.menuFont(ofSize: NSFont.systemFontSize), toHaveTrait: .boldFontMask
	)

	func buildMenu(from element: AXUIElement, target: AnyObject?, action: Selector?) -> [NSMenuItem] {
		return buildMenuItems(from: element, target: target, action: action, isSubmenu: false)
	}

	private func buildMenuItems(
		from element: AXUIElement, target: AnyObject?, action: Selector?, isSubmenu: Bool
	) -> [NSMenuItem] {
		guard let children = element.getChildren() else { return [] }

		var items: [NSMenuItem] = []
		var appleItem: NSMenuItem?
		var isFirst = true

		for child in children {
			let attrs = [
				"AXTitle", "AXRole", "AXRoleDescription", "AXEnabled",
				"AXMenuItemMarkChar", "AXMenuItemCmdChar", "AXMenuItemCmdModifiers", "AXChildren",
			]

			guard let values = child.getMultipleAttributes(attrs) else { continue }

			let title = values["AXTitle"] as? String ?? ""
			let role = values["AXRole"] as? String ?? ""

			if title.isEmpty || role == "AXSeparator" {
				if !items.isEmpty, items.last?.isSeparatorItem == false {
					items.append(.separator())
				}
				continue
			}

			let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
			item.representedObject = child
			let isEnabled = values["AXEnabled"] as? Bool ?? true
			item.isEnabled = isEnabled

			if let mark = values["AXMenuItemMarkChar"] as? String, !mark.isEmpty {
				item.state = mark == "✓" ? .on : (mark == "•" ? .mixed : .off)
			}

			if let cmd = values["AXMenuItemCmdChar"] as? String, !cmd.isEmpty {
				item.keyEquivalent = cmd.lowercased()
				var flags: NSEvent.ModifierFlags = [.command]
				if let mods = values["AXMenuItemCmdModifiers"] as? Int {
					flags = []
					if mods & 1 != 0 { flags.insert(.shift) }
					if mods & 2 != 0 { flags.insert(.option) }
					if mods & 4 != 0 { flags.insert(.control) }
					if mods & 8 != 0 { flags.insert(.command) }
					if flags.isEmpty { flags.insert(.command) }
				}
				item.keyEquivalentModifierMask = flags
			}

			var hasSubmenu = false
			if let subChildren = values["AXChildren"] as? [AXUIElement], !subChildren.isEmpty,
			   let firstSub = subChildren.first,
			   let subRole = firstSub.getAttribute("AXRole") as? String, subRole == "AXMenu"
			{
				let submenu = NSMenu(title: title)
				buildMenuItems(from: firstSub, target: target, action: action, isSubmenu: true)
					.forEach { submenu.addItem($0) }
				item.submenu = submenu
				hasSubmenu = true
			}

			if !hasSubmenu && isEnabled {
				item.target = target
				item.action = action
			}

			let isApple =
				(values["AXRoleDescription"] as? String) == "Apple menu" || title == "Apple"
			if !isSubmenu, isFirst || isApple {
				item.attributedTitle = NSAttributedString(
					string: title, attributes: [.font: boldFont]
				)
				if !isApple { isFirst = false }
			}

			if isApple {
				appleItem = item
			} else {
				items.append(item)
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
}

extension AXUIElement {
	func getAttribute(_ name: String) -> Any? {
		var value: AnyObject?
		return AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success
			? value : nil
	}

	func getChildren() -> [AXUIElement]? {
		var value: AnyObject?
		guard AXUIElementCopyAttributeValue(self, "AXChildren" as CFString, &value) == .success,
		      let children = value as? [AXUIElement], !children.isEmpty
		else {
			return nil
		}
		return children
	}

	func getMultipleAttributes(_ names: [String]) -> [String: Any]? {
		let attrs = names as CFArray
		var values: CFArray?
		let options = AXCopyMultipleAttributeOptions(rawValue: 0)

		guard AXUIElementCopyMultipleAttributeValues(self, attrs, options, &values) == .success,
		      let results = values as? [Any], results.count == names.count
		else { return nil }

		var dict: [String: Any] = [:]
		dict.reserveCapacity(names.count)

		for i in 0 ..< names.count {
			let value = results[i]
			let valueRef = value as CFTypeRef
			if CFGetTypeID(valueRef) != AXValueGetTypeID()
				|| AXValueGetType(value as! AXValue) != .illegal
			{
				dict[names[i]] = value
			}
		}
		return dict.isEmpty ? nil : dict
	}
}
