import Foundation

@MainActor
enum IOSWorkspaceSupport {
    private static var fileManager: FileManager { .default }

    static func ensureReady() {
        _ = TerminalRuntimeCoordinator.shared.prepareRuntime()
    }

    static var applicationSupportURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OmnibotIOS", isDirectory: true)
    }

    static var workspaceRootURL: URL {
        applicationSupportURL.appendingPathComponent("workspace", isDirectory: true)
    }

    static var internalRootURL: URL {
        workspaceRootURL.appendingPathComponent(".omnibot", isDirectory: true)
    }

    static var memoryRootURL: URL {
        internalRootURL.appendingPathComponent("memory", isDirectory: true)
    }

    static var shortMemoryRootURL: URL {
        memoryRootURL.appendingPathComponent("short-memories", isDirectory: true)
    }

    static var skillsRootURL: URL {
        internalRootURL.appendingPathComponent("skills", isDirectory: true)
    }

    static var scheduleRootURL: URL {
        internalRootURL.appendingPathComponent("schedule", isDirectory: true)
    }

    static var remoteMcpRootURL: URL {
        internalRootURL.appendingPathComponent("mcp", isDirectory: true)
    }

    static func normalizedShellPath(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "/workspace" {
            return "/workspace"
        }
        if trimmed.hasPrefix("/workspace") {
            return trimmed
        }
        if trimmed.hasPrefix("/") {
            return "/workspace\(trimmed)"
        }
        return "/workspace/\(trimmed)"
    }

    static func hostURL(forShellPath shellPath: String?) -> URL {
        ensureReady()
        let normalized = normalizedShellPath(shellPath)
        let relative = normalized
            .replacingOccurrences(of: "/workspace", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if relative.isEmpty {
            return workspaceRootURL
        }
        return workspaceRootURL.appendingPathComponent(relative, isDirectory: false)
    }

    static func shellPath(for hostURL: URL) -> String {
        ensureReady()
        let relative = hostURL.path.replacingOccurrences(of: workspaceRootURL.path, with: "")
        if relative.isEmpty {
            return "/workspace"
        }
        return "/workspace\(relative)"
    }

    static func createDirectoryIfNeeded(_ url: URL) {
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func readText(at url: URL, default defaultValue: String = "") -> String {
        ensureReady()
        createDirectoryIfNeeded(url.deletingLastPathComponent())
        return (try? String(contentsOf: url, encoding: .utf8)) ?? defaultValue
    }

    static func writeText(_ text: String, to url: URL) {
        ensureReady()
        createDirectoryIfNeeded(url.deletingLastPathComponent())
        let normalized = text.hasSuffix("\n") ? text : "\(text)\n"
        try? normalized.write(to: url, atomically: true, encoding: .utf8)
    }

    static func readJSONObject(at url: URL) -> Any? {
        ensureReady()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func writeJSONObject(_ object: Any, to url: URL) throws {
        ensureReady()
        createDirectoryIfNeeded(url.deletingLastPathComponent())
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
