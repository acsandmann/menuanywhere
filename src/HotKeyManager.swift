import Carbon

class HotKeyManager {
	static let signature = OSType("Mbar".fourCharCode)
	private var hotKeyRef: EventHotKeyRef?
	private var eventHandlerRef: EventHandlerRef?
	private var keyCode: UInt32 = 0
	private var modifiers: UInt32 = 0

	var onActivated: (() -> Void)?

	func setup() {
		let config = HotKeyConfig.load()

		guard let code = KeyMappings.keys[config.key.lowercased()] else {
			print("Unknown key: \(config.key)")
			return
		}

		keyCode = code
		modifiers = config.modifiers.compactMap { KeyMappings.modifiers[$0.lowercased()] }
			.reduce(0, |)

		registerHotKey()
		setupEventHandler()
	}

	func cleanup() {
		if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
		if let handler = eventHandlerRef { RemoveEventHandler(handler) }
	}

	private func registerHotKey() {
		let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
		RegisterEventHotKey(
			keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
		)
	}

	private func setupEventHandler() {
		let context = Unmanaged.passUnretained(self).toOpaque()
		var eventType = EventTypeSpec(
			eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
		)
		InstallEventHandler(
			GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, context, &eventHandlerRef
		)
	}

	func handlePress() {
		cleanup()
		onActivated?()
	}

	func reregister() {
		registerHotKey()
		setupEventHandler()
	}
}

private func hotKeyHandler(
	nextHandler _: EventHandlerCallRef?,
	theEvent: EventRef?,
	userData: UnsafeMutableRawPointer?
) -> OSStatus {
	guard let userData = userData, let event = theEvent else { return OSStatus(eventNotHandledErr) }

	let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
	var hotKeyID = EventHotKeyID()

	let status = GetEventParameter(
		event, EventParamName(kEventParamDirectObject),
		EventParamType(typeEventHotKeyID), nil,
		MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
	)

	if status == noErr && hotKeyID.signature == HotKeyManager.signature {
		DispatchQueue.main.async { manager.handlePress() }
		return noErr
	}

	return OSStatus(eventNotHandledErr)
}

extension String {
	var fourCharCode: FourCharCode {
		let chars = Array(prefix(4).utf8) + Array(repeating: 32, count: 4)
		return chars.prefix(4).reduce(0) { ($0 << 8) + FourCharCode($1) }
	}
}
