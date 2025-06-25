import Cocoa

enum AccessibilityManager {
	static func ensurePermissions() {
		guard
			!AXIsProcessTrustedWithOptions(
				[kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
		else { return }

		print("Waiting for accessibility permissions...")
		Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { timer in
			if AXIsProcessTrusted() {
				print("Permissions granted, restarting...")
				timer.invalidate()
				NSApp.terminate(nil)
			}
		}
	}
}
