import Cocoa
import CoreFoundation

enum AccessibilityManager {
	private static let didPromptKey = "AccessibilityManagerDidPrompt"

	static func ensurePermissions() {
		guard !AXIsProcessTrusted() else { return }

		let defaults = UserDefaults.standard
		if !defaults.bool(forKey: didPromptKey) {
			AXIsProcessTrustedWithOptions(
				[
					kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
				] as CFDictionary)
			defaults.set(true, forKey: didPromptKey)
		}

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
