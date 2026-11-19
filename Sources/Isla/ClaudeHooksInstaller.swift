import Foundation

/// Adds (or removes) Isla's hooks in ~/.claude/settings.json.
/// Makes a dated backup first and leaves every other setting and hook untouched.
enum ClaudeHooksInstaller {
    static let events = ["Notification", "Stop", "PermissionRequest"]

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    private static func command(for event: String) -> String {
        event == "PermissionRequest"
            ? "\"\(HookServer.permissionScriptPath)\""
            : "\"\(HookServer.hookScriptPath)\" \(event)"
    }

    /// Claude Code waits this long for the hook; permission requests wait for your click.
    private static func timeout(for event: String) -> Int {
        event == "PermissionRequest" ? 120 : 5
    }

    private static func isOurs(_ hook: [String: Any]) -> Bool {
        let cmd = hook["command"] as? String ?? ""
        return cmd.contains("Isla/isla-hook") || cmd.contains("Isla/isla-permission")
    }

    static var isInstalled: Bool {
        guard let hooks = load()["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            (hooks[event] as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains(where: isOurs)
            }
        }
    }

    private static func load() -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    private static func backup() throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let dest = settingsURL.deletingLastPathComponent()
            .appendingPathComponent("settings.json.isla-backup-\(f.string(from: Date()))")
        try FileManager.default.copyItem(at: settingsURL, to: dest)
    }

    private static func save(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: settingsURL, options: .atomic)
    }

    static func install() throws {
        // A settings file that exists but is not valid JSON is left alone.
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            let data = try Data(contentsOf: settingsURL)
            if !data.isEmpty, (try? JSONSerialization.jsonObject(with: data)) == nil {
                throw NSError(domain: "Isla", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "~/.claude/settings.json no es un JSON válido; no lo he tocado."])
            }
        }
        var settings = load()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            let present = groups.contains { ($0["hooks"] as? [[String: Any]] ?? []).contains(where: isOurs) }
            if !present {
                groups.append(["hooks": [["type": "command", "command": command(for: event), "timeout": timeout(for: event)]]])
            }
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        try backup()
        try save(settings)
    }

    static func uninstall() throws {
        var settings = load()
        guard var hooks = settings["hooks"] as? [String: Any] else { return }
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups = groups.compactMap { group in
                var g = group
                let kept = (group["hooks"] as? [[String: Any]] ?? []).filter { !isOurs($0) }
                if kept.isEmpty { return nil }
                g["hooks"] = kept
                return g
            }
            hooks[event] = groups.isEmpty ? nil : groups
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try backup()
        try save(settings)
    }
}
