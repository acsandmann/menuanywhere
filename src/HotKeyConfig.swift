import Foundation

struct HotKeyConfig: Codable {
	let key: String
	let modifiers: [String]

	static func load() -> HotKeyConfig {
		let configHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? "~/.config"
		let configPath = (configHome as NSString).expandingTildeInPath + "/menuanywhere/config.json"

		do {
			let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
			return try JSONDecoder().decode(HotKeyConfig.self, from: data)
		} catch {
			print("Using default hotkey: control+m")
			return HotKeyConfig(key: "m", modifiers: ["control"])
		}
	}
}
