import Foundation

@MainActor
final class RemoteMcpStore {
    struct ServerRecord: Codable {
        let id: String
        let name: String
        let endpointURL: String
        let bearerToken: String
        let enabled: Bool
        let lastHealth: String
        let lastError: String?
        let toolCount: Int
        let lastSyncedAt: Int?

        init(
            id: String = UUID().uuidString,
            name: String,
            endpointURL: String,
            bearerToken: String = "",
            enabled: Bool = true,
            lastHealth: String = "unknown",
            lastError: String? = nil,
            toolCount: Int = 0,
            lastSyncedAt: Int? = nil
        ) {
            self.id = id
            self.name = name
            self.endpointURL = endpointURL
            self.bearerToken = bearerToken
            self.enabled = enabled
            self.lastHealth = lastHealth
            self.lastError = lastError
            self.toolCount = toolCount
            self.lastSyncedAt = lastSyncedAt
        }

        var payload: [String: Any] {
            [
                "id": id,
                "name": name,
                "endpointUrl": endpointURL,
                "bearerToken": bearerToken,
                "enabled": enabled,
                "lastHealth": lastHealth,
                "lastError": lastError ?? NSNull(),
                "toolCount": toolCount,
                "lastSyncedAt": lastSyncedAt ?? NSNull(),
            ]
        }
    }

    struct ToolRecord {
        let serverId: String
        let serverName: String
        let toolName: String
        let description: String
        let inputSchema: [String: Any]

        var encodedToolName: String {
            "mcp__\(serverId)__\(toolName)"
        }

        var promptPayload: [String: Any] {
            [
                "name": encodedToolName,
                "displayName": toolName,
                "toolType": "mcp",
                "serverName": serverName,
                "description": description,
                "parameters": inputSchema,
            ]
        }
    }

    struct ToolCallResult {
        let summaryText: String
        let previewJSON: String
        let rawResultJSON: String
        let success: Bool
    }

    private struct ToolCacheRecord: Codable {
        let toolName: String
        let description: String
        let inputSchema: [String: JSONValue]
    }

    static let shared = RemoteMcpStore()

    private let client = RemoteMcpClient.shared

    private init() {}

    func listServersPayload() -> [[String: Any]] {
        loadServers().map(\.payload)
    }

    func upsertServer(_ raw: [String: Any]) -> [String: Any] {
        var servers = loadServers()
        let normalized = serverRecord(from: raw)
        if let index = servers.firstIndex(where: { $0.id == normalized.id }) {
            let existing = servers[index]
            servers[index] = ServerRecord(
                id: normalized.id,
                name: normalized.name,
                endpointURL: normalized.endpointURL,
                bearerToken: normalized.bearerToken,
                enabled: normalized.enabled,
                lastHealth: normalized.lastHealth == "unknown" ? existing.lastHealth : normalized.lastHealth,
                lastError: normalized.lastError ?? existing.lastError,
                toolCount: normalized.toolCount > 0 ? normalized.toolCount : existing.toolCount,
                lastSyncedAt: normalized.lastSyncedAt ?? existing.lastSyncedAt
            )
            saveServers(servers)
            return servers[index].payload
        }
        servers.append(normalized)
        saveServers(servers)
        return normalized.payload
    }

    func deleteServer(id: String) {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedID.isEmpty == false else { return }
        saveServers(loadServers().filter { $0.id != normalizedID })
        try? FileManager.default.removeItem(at: toolCacheURL(serverID: normalizedID))
    }

    func setServerEnabled(id: String, enabled: Bool) -> [String: Any]? {
        var servers = loadServers()
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return nil }
        let updated = ServerRecord(
            id: servers[index].id,
            name: servers[index].name,
            endpointURL: servers[index].endpointURL,
            bearerToken: servers[index].bearerToken,
            enabled: enabled,
            lastHealth: servers[index].lastHealth,
            lastError: servers[index].lastError,
            toolCount: servers[index].toolCount,
            lastSyncedAt: servers[index].lastSyncedAt
        )
        servers[index] = updated
        saveServers(servers)
        return updated.payload
    }

    func refreshServerTools(id: String) async throws -> [String: Any] {
        guard let server = loadServers().first(where: { $0.id == id }) else {
            throw NSError(domain: "RemoteMcpStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server not found"])
        }
        do {
            let tools = try await client.listTools(server: server)
            saveToolCache(serverID: server.id, tools: tools)
            let updated = updateDiscoveryStatus(
                serverID: server.id,
                health: "healthy",
                toolCount: tools.count,
                lastError: nil
            )
            return [
                "server": updated?.payload ?? server.payload,
                "tools": tools.map(\.promptPayload),
            ]
        } catch {
            let updated = updateDiscoveryStatus(
                serverID: server.id,
                health: "error",
                toolCount: 0,
                lastError: error.localizedDescription
            )
            throw NSError(domain: "RemoteMcpStore", code: 2, userInfo: [NSLocalizedDescriptionKey: updated?.lastError ?? error.localizedDescription])
        }
    }

    func discoverEnabledTools(forceRefresh: Bool = false) async -> [ToolRecord] {
        var discovered = [ToolRecord]()
        for server in loadServers().filter(\.enabled) {
            if forceRefresh {
                _ = try? await refreshServerTools(id: server.id)
            }
            discovered.append(contentsOf: loadToolCache(server: server))
        }
        return discovered
    }

    func callEncodedTool(_ encodedToolName: String, arguments: [String: Any]) async throws -> ToolCallResult {
        let components = encodedToolName.split(separator: "_")
        guard encodedToolName.hasPrefix("mcp__") else {
            throw NSError(domain: "RemoteMcpStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid remote MCP tool name"])
        }
        let remainder = encodedToolName.dropFirst("mcp__".count)
        guard let separatorRange = remainder.range(of: "__") else {
            throw NSError(domain: "RemoteMcpStore", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid remote MCP tool name"])
        }
        let serverID = String(remainder[..<separatorRange.lowerBound])
        let toolName = String(remainder[separatorRange.upperBound...])
        guard components.isEmpty == false, toolName.isEmpty == false,
              let server = loadServers().first(where: { $0.id == serverID }) else {
            throw NSError(domain: "RemoteMcpStore", code: 5, userInfo: [NSLocalizedDescriptionKey: "Remote MCP server not found"])
        }
        return try await client.callTool(server: server, toolName: toolName, arguments: arguments)
    }

    private var serversURL: URL {
        IOSWorkspaceSupport.remoteMcpRootURL.appendingPathComponent("servers.json")
    }

    private func toolCacheURL(serverID: String) -> URL {
        IOSWorkspaceSupport.remoteMcpRootURL.appendingPathComponent("tools-\(serverID).json")
    }

    private func loadServers() -> [ServerRecord] {
        if let data = try? Data(contentsOf: serversURL),
           let servers = try? JSONDecoder().decode([ServerRecord].self, from: data) {
            return servers
        }
        return []
    }

    private func saveServers(_ servers: [ServerRecord]) {
        IOSWorkspaceSupport.ensureReady()
        IOSWorkspaceSupport.createDirectoryIfNeeded(serversURL.deletingLastPathComponent())
        if let data = try? JSONEncoder().encode(servers) {
            try? data.write(to: serversURL, options: .atomic)
        }
    }

    private func saveToolCache(serverID: String, tools: [ToolRecord]) {
        IOSWorkspaceSupport.ensureReady()
        let cache = tools.map {
            ToolCacheRecord(
                toolName: $0.toolName,
                description: $0.description,
                inputSchema: $0.inputSchema.reduce(into: [String: JSONValue]()) { partialResult, entry in
                    partialResult[entry.key] = JSONValue(entry.value)
                }
            )
        }
        let url = toolCacheURL(serverID: serverID)
        IOSWorkspaceSupport.createDirectoryIfNeeded(url.deletingLastPathComponent())
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func loadToolCache(server: ServerRecord) -> [ToolRecord] {
        let url = toolCacheURL(serverID: server.id)
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode([ToolCacheRecord].self, from: data) else {
            return []
        }
        return cache.map {
            ToolRecord(
                serverId: server.id,
                serverName: server.name,
                toolName: $0.toolName,
                description: $0.description,
                inputSchema: $0.inputSchema.mapValues(\.foundationValue)
            )
        }
    }

    private func updateDiscoveryStatus(
        serverID: String,
        health: String,
        toolCount: Int,
        lastError: String?
    ) -> ServerRecord? {
        var servers = loadServers()
        guard let index = servers.firstIndex(where: { $0.id == serverID }) else { return nil }
        let updated = ServerRecord(
            id: servers[index].id,
            name: servers[index].name,
            endpointURL: servers[index].endpointURL,
            bearerToken: servers[index].bearerToken,
            enabled: servers[index].enabled,
            lastHealth: health,
            lastError: lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
            toolCount: toolCount,
            lastSyncedAt: Int(Date().timeIntervalSince1970 * 1000)
        )
        servers[index] = updated
        saveServers(servers)
        return updated
    }

    private func serverRecord(from raw: [String: Any]) -> ServerRecord {
        ServerRecord(
            id: normalizedOptionalString(raw["id"]) ?? UUID().uuidString,
            name: normalizedOptionalString(raw["name"]) ?? "Remote MCP",
            endpointURL: normalizedOptionalString(raw["endpointUrl"]) ?? "",
            bearerToken: normalizedOptionalString(raw["bearerToken"]) ?? "",
            enabled: boolValue(raw["enabled"], defaultValue: true),
            lastHealth: normalizedOptionalString(raw["lastHealth"]) ?? "unknown",
            lastError: normalizedOptionalString(raw["lastError"]),
            toolCount: integerValue(raw["toolCount"]) ?? 0,
            lastSyncedAt: integerValue(raw["lastSyncedAt"])
        )
    }

    private func normalizedOptionalString(_ raw: Any?) -> String? {
        switch raw {
        case let string as String:
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? nil : normalized
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private func integerValue(_ raw: Any?) -> Int? {
        switch raw {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private func boolValue(_ raw: Any?, defaultValue: Bool) -> Bool {
        switch raw {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return defaultValue
            }
        default:
            return defaultValue
        }
    }
}

private struct JSONValue: Codable {
    let foundationValue: Any

    init(_ value: Any) {
        if let dictionary = value as? [String: Any] {
            foundationValue = dictionary.mapValues(JSONValue.init)
        } else if let array = value as? [Any] {
            foundationValue = array.map(JSONValue.init)
        } else {
            foundationValue = value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            foundationValue = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            foundationValue = doubleValue
        } else if let boolValue = try? container.decode(Bool.self) {
            foundationValue = boolValue
        } else if let stringValue = try? container.decode(String.self) {
            foundationValue = stringValue
        } else if let arrayValue = try? container.decode([JSONValue].self) {
            foundationValue = arrayValue
        } else if let dictValue = try? container.decode([String: JSONValue].self) {
            foundationValue = dictValue
        } else {
            foundationValue = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch foundationValue {
        case let value as Int:
            try container.encode(value)
        case let value as Double:
            try container.encode(value)
        case let value as Bool:
            try container.encode(value)
        case let value as String:
            try container.encode(value)
        case let value as [JSONValue]:
            try container.encode(value)
        case let value as [String: JSONValue]:
            try container.encode(value)
        default:
            try container.encodeNil()
        }
    }
}
