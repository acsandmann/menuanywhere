import Carbon

class HotKeyManager {
	static let signature: OSType = 0x4D62_6172 // "Mbar"
	private static let hotKeyID = EventHotKeyID(signature: signature, id: 1)
	private static let eventType = EventTypeSpec(
		eventClass: OSType(kEventClassKeyboard),
		eventKind: UInt32(kEventHotKeyPressed)
	)

	private var hotKeyRef: EventHotKeyRef?
	private var eventHandlerRef: EventHandlerRef?
	private var keyCode: UInt32!
	private var modifiers: UInt32!

	var onActivated: (() -> Void)?

	func setup() -> Bool {
		let config = HotKeyConfig.load()

		guard let code = KeyMappings.keys[config.key.lowercased()] else {
			print("Unknown key: \(config.key)")
			return false
		}

		keyCode = code
		modifiers = config.modifiers.compactMap { KeyMappings.modifiers[$0.lowercased()] }
			.reduce(0, |)

		guard registerHotKey(), setupEventHandler() else {
			cleanup()
			return false
		}
		return true
	}

	func cleanup() {
		if let ref = hotKeyRef {
			UnregisterEventHotKey(ref)
			hotKeyRef = nil
		}
		if let handler = eventHandlerRef {
			RemoveEventHandler(handler)
			eventHandlerRef = nil
		}
	}

	@discardableResult
	private func registerHotKey() -> Bool {
		return RegisterEventHotKey(
			keyCode, modifiers, Self.hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
		) == noErr
	}

	@discardableResult
	private func setupEventHandler() -> Bool {
		let context = Unmanaged.passUnretained(self).toOpaque()
		var eventType = Self.eventType
		return InstallEventHandler(
			GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, context, &eventHandlerRef
		) == noErr
	}

	func handlePress() {
		cleanup()
		onActivated?()
	}

	func reregister() -> Bool {
		return registerHotKey() && setupEventHandler()
	}
}

private func hotKeyHandler(
	nextHandler _: EventHandlerCallRef?,
	theEvent: EventRef?,
	userData: UnsafeMutableRawPointer?
) -> OSStatus {
	guard let userData = userData, let event = theEvent else {
		return OSStatus(eventNotHandledErr)
	}

	let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
	var hotKeyID = EventHotKeyID()

	guard
		GetEventParameter(
			event, EventParamName(kEventParamDirectObject),
			EventParamType(typeEventHotKeyID), nil,
			MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
		) == noErr, hotKeyID.signature == HotKeyManager.signature
	else {
		return OSStatus(eventNotHandledErr)
	}

	DispatchQueue.main.async { manager.handlePress() }
	return noErr
}
