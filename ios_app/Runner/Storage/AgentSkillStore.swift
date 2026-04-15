import Foundation

@MainActor
final class AgentSkillStore {
    private struct SkillManifest: Codable {
        let id: String
        let name: String
        let description: String
        let enabled: Bool
        let source: String
        let installed: Bool
    }

    private struct BuiltinSkill {
        let id: String
        let name: String
        let description: String
    }

    static let shared = AgentSkillStore()

    private let builtinSkills = [
        BuiltinSkill(
            id: "builtin.terminal",
            name: "Terminal",
            description: "Use the iOS embedded workspace terminal to inspect files and run CLI commands."
        ),
        BuiltinSkill(
            id: "builtin.memory",
            name: "Workspace Memory",
            description: "Read and update workspace soul, chat prompt, long-term memory, and short memories."
        ),
        BuiltinSkill(
            id: "builtin.schedule",
            name: "Scheduled Tasks",
            description: "Inspect and update workspace scheduled tasks stored inside the iOS workspace."
        ),
        BuiltinSkill(
            id: "builtin.browser",
            name: "Browser Snapshot",
            description: "Read the current in-app browser session snapshot and webpage summary."
        ),
        BuiltinSkill(
            id: "builtin.remote_mcp",
            name: "Remote MCP",
            description: "Discover configured remote MCP tools and call them from the unified iOS agent."
        ),
    ]

    private init() {}

    func listSkillsPayload() -> [[String: Any]] {
        let installed = Dictionary(uniqueKeysWithValues: loadInstalledManifests().map { ($0.id, $0) })
        return builtinSkills.map { builtin in
            if let manifest = installed[builtin.id] {
                return payload(for: manifest)
            }
            return builtinPayload(for: builtin)
        } + loadCustomSkillPayloads(excluding: Set(builtinSkills.map(\.id)))
    }

    func installSkill(from sourcePath: String) throws -> [String: Any] {
        let normalizedSourcePath = sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedSourcePath.isEmpty == false else {
            throw NSError(domain: "AgentSkillStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "sourcePath is required"])
        }
        let sourceURL = URL(fileURLWithPath: normalizedSourcePath, isDirectory: true)
        let skillFileURL = sourceURL.appendingPathComponent("SKILL.md")
        guard FileManager.default.fileExists(atPath: skillFileURL.path) else {
            throw NSError(domain: "AgentSkillStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "SKILL.md not found in sourcePath"])
        }

        let manifest = try manifestFromSkillFile(at: skillFileURL, defaultSource: "user")
        let destinationURL = rootURL(for: manifest.id)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        IOSWorkspaceSupport.createDirectoryIfNeeded(destinationURL.deletingLastPathComponent())
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        saveManifest(
            SkillManifest(
                id: manifest.id,
                name: manifest.name,
                description: manifest.description,
                enabled: true,
                source: "user",
                installed: true
            ),
            at: destinationURL
        )
        return payload(for: loadManifest(at: destinationURL)!)
    }

    func setSkillEnabled(skillId: String, enabled: Bool) throws -> [String: Any] {
        let normalizedSkillID = skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedSkillID.isEmpty == false else {
            throw NSError(domain: "AgentSkillStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "skillId is required"])
        }
        let url = rootURL(for: normalizedSkillID)
        guard var manifest = loadManifest(at: url) else {
            throw NSError(domain: "AgentSkillStore", code: 4, userInfo: [NSLocalizedDescriptionKey: "Skill not installed"])
        }
        manifest = SkillManifest(
            id: manifest.id,
            name: manifest.name,
            description: manifest.description,
            enabled: enabled,
            source: manifest.source,
            installed: true
        )
        saveManifest(manifest, at: url)
        return payload(for: manifest)
    }

    func deleteSkill(skillId: String) -> Bool {
        let normalizedSkillID = skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedSkillID.isEmpty == false else { return false }
        let url = rootURL(for: normalizedSkillID)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        try? FileManager.default.removeItem(at: url)
        return true
    }

    func installBuiltinSkill(skillId: String) throws -> [String: Any] {
        let normalizedSkillID = skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let builtin = builtinSkills.first(where: { $0.id == normalizedSkillID }) else {
            throw NSError(domain: "AgentSkillStore", code: 5, userInfo: [NSLocalizedDescriptionKey: "Builtin skill not found"])
        }
        let url = rootURL(for: builtin.id)
        IOSWorkspaceSupport.createDirectoryIfNeeded(url)
        IOSWorkspaceSupport.writeText(skillFileContent(for: builtin), to: url.appendingPathComponent("SKILL.md"))
        let manifest = SkillManifest(
            id: builtin.id,
            name: builtin.name,
            description: builtin.description,
            enabled: true,
            source: "builtin",
            installed: true
        )
        saveManifest(manifest, at: url)
        return payload(for: manifest)
    }

    func enabledSkillPromptSummaries() -> [String] {
        loadInstalledManifests()
            .filter { $0.enabled && $0.installed }
            .map { "\($0.name): \($0.description)" }
            .sorted()
    }

    private func loadInstalledManifests() -> [SkillManifest] {
        IOSWorkspaceSupport.ensureReady()
        IOSWorkspaceSupport.createDirectoryIfNeeded(IOSWorkspaceSupport.skillsRootURL)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: IOSWorkspaceSupport.skillsRootURL,
            includingPropertiesForKeys: nil
        )) ?? []
        return urls.compactMap(loadManifest)
    }

    private func loadCustomSkillPayloads(excluding builtinIDs: Set<String>) -> [[String: Any]] {
        loadInstalledManifests()
            .filter { builtinIDs.contains($0.id) == false }
            .map(payload)
    }

    private func payload(for manifest: SkillManifest) -> [String: Any] {
        let url = rootURL(for: manifest.id)
        let skillFileURL = url.appendingPathComponent("SKILL.md")
        let rootPath = url.path
        return [
            "id": manifest.id,
            "name": manifest.name,
            "description": manifest.description,
            "compatibility": NSNull(),
            "metadata": [:],
            "rootPath": rootPath,
            "shellRootPath": IOSWorkspaceSupport.shellPath(for: url),
            "skillFilePath": skillFileURL.path,
            "shellSkillFilePath": IOSWorkspaceSupport.shellPath(for: skillFileURL),
            "hasScripts": FileManager.default.fileExists(atPath: url.appendingPathComponent("scripts").path),
            "hasReferences": FileManager.default.fileExists(atPath: url.appendingPathComponent("references").path),
            "hasAssets": FileManager.default.fileExists(atPath: url.appendingPathComponent("assets").path),
            "hasEvals": FileManager.default.fileExists(atPath: url.appendingPathComponent("evals").path),
            "enabled": manifest.enabled,
            "source": manifest.source,
            "installed": manifest.installed,
        ]
    }

    private func builtinPayload(for builtin: BuiltinSkill) -> [String: Any] {
        let url = rootURL(for: builtin.id)
        let skillFileURL = url.appendingPathComponent("SKILL.md")
        return [
            "id": builtin.id,
            "name": builtin.name,
            "description": builtin.description,
            "compatibility": NSNull(),
            "metadata": [:],
            "rootPath": url.path,
            "shellRootPath": IOSWorkspaceSupport.shellPath(for: url),
            "skillFilePath": skillFileURL.path,
            "shellSkillFilePath": IOSWorkspaceSupport.shellPath(for: skillFileURL),
            "hasScripts": false,
            "hasReferences": false,
            "hasAssets": false,
            "hasEvals": false,
            "enabled": false,
            "source": "builtin",
            "installed": false,
        ]
    }

    private func manifestFromSkillFile(at skillFileURL: URL, defaultSource: String) throws -> SkillManifest {
        let content = try String(contentsOf: skillFileURL, encoding: .utf8)
        let name = firstMatch(in: content, pattern: #"(?m)^name:\s*(.+)$"#)
            ?? skillFileURL.deletingLastPathComponent().lastPathComponent
        let description = firstMatch(in: content, pattern: #"(?m)^description:\s*(.+)$"#)
            ?? "User-installed skill"
        let id = sanitizedSkillID(
            firstMatch(in: content, pattern: #"(?m)^id:\s*(.+)$"#)
                ?? name
        )
        return SkillManifest(
            id: id,
            name: stripQuotes(name),
            description: stripQuotes(description),
            enabled: true,
            source: defaultSource,
            installed: true
        )
    }

    private func loadManifest(at url: URL) -> SkillManifest? {
        let manifestURL = url.appendingPathComponent("skill.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(SkillManifest.self, from: data) else {
            return nil
        }
        return manifest
    }

    private func saveManifest(_ manifest: SkillManifest, at url: URL) {
        IOSWorkspaceSupport.createDirectoryIfNeeded(url)
        let manifestURL = url.appendingPathComponent("skill.json")
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }

    private func rootURL(for skillId: String) -> URL {
        IOSWorkspaceSupport.skillsRootURL.appendingPathComponent(skillId, isDirectory: true)
    }

    private func skillFileContent(for builtin: BuiltinSkill) -> String {
        """
        ---
        name: \(builtin.name)
        description: \(builtin.description)
        ---

        \(builtin.description)
        """
    }

    private func sanitizedSkillID(_ raw: String) -> String {
        let normalized = stripQuotes(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9._-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return normalized.isEmpty ? UUID().uuidString : normalized
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripQuotes(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
            (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }
}
