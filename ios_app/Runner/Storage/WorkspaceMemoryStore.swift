import Foundation

@MainActor
final class WorkspaceMemoryStore {
    private struct EmbeddingConfigRecord: Codable {
        let enabled: Bool
        let sceneId: String
        let providerProfileId: String?
        let modelId: String?
    }

    private struct RollupStatusRecord: Codable {
        let enabled: Bool
        let lastRunAtMillis: Int?
        let lastRunSummary: String?
        let nextRunAtMillis: Int?
    }

    static let shared = WorkspaceMemoryStore()

    private let providerStore = ModelProviderProfileStore.shared
    private let calendar = Calendar(identifier: .gregorian)

    private init() {}

    func getSoulPayload() -> [String: Any] {
        ["content": readSoul()]
    }

    func saveSoul(_ content: String) -> [String: Any] {
        IOSWorkspaceSupport.writeText(content.trimmingCharacters(in: .newlines), to: soulURL)
        return getSoulPayload()
    }

    func getChatPromptPayload() -> [String: Any] {
        ["content": readChatPrompt()]
    }

    func saveChatPrompt(_ content: String) -> [String: Any] {
        IOSWorkspaceSupport.writeText(content.trimmingCharacters(in: .newlines), to: chatPromptURL)
        return getChatPromptPayload()
    }

    func getLongMemoryPayload() -> [String: Any] {
        ["content": readLongMemory()]
    }

    func saveLongMemory(_ content: String) -> [String: Any] {
        IOSWorkspaceSupport.writeText(content.trimmingCharacters(in: .newlines), to: longMemoryURL)
        return getLongMemoryPayload()
    }

    func getShortMemoriesPayload(days: Int, limit: Int) -> [String: Any] {
        let safeDays = max(1, days)
        let safeLimit = max(1, limit)
        let now = Date()
        let startDate = calendar.date(byAdding: .day, value: -(safeDays - 1), to: now) ?? now
        let items = loadShortMemoryItems()
            .filter { item in
                Date(timeIntervalSince1970: Double(item.timestampMillis) / 1000) >= startDate
            }
            .sorted { $0.timestampMillis > $1.timestampMillis }
            .prefix(safeLimit)
            .map(\.payload)
        return ["items": Array(items)]
    }

    func appendShortMemory(_ content: String, timestampMillis: Int? = nil) -> [String: Any]? {
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return nil }

        let date = timestampMillis.flatMap {
            Date(timeIntervalSince1970: Double($0) / 1000)
        } ?? Date()
        let url = dailyShortMemoryURL(for: date)
        IOSWorkspaceSupport.ensureReady()
        IOSWorkspaceSupport.createDirectoryIfNeeded(url.deletingLastPathComponent())

        if FileManager.default.fileExists(atPath: url.path) == false {
            let header = "# \(dateFormatter.date(from: dayFormatter.string(from: date)).map(dayFormatter.string(from:)) ?? dayFormatter.string(from: date)) Daily Memory\n\n"
            IOSWorkspaceSupport.writeText(header, to: url)
        }

        let line = "- [\(timeFormatter.string(from: date))] \(normalized)\n"
        if var existing = try? String(contentsOf: url, encoding: .utf8) {
            if existing.hasSuffix("\n") == false {
                existing.append("\n")
            }
            existing.append(line)
            try? existing.write(to: url, atomically: true, encoding: .utf8)
        } else {
            IOSWorkspaceSupport.writeText(line, to: url)
        }

        return loadShortMemoryItems()
            .first(where: { $0.content == normalized && $0.date == dayFormatter.string(from: date) })?
            .payload
    }

    func getEmbeddingConfigPayload() async -> [String: Any] {
        let record = loadEmbeddingConfig()
        return await embeddingConfigPayload(from: record)
    }

    func saveEmbeddingConfigPayload(
        enabled: Bool,
        providerProfileId: String?,
        modelId: String?
    ) async -> [String: Any] {
        let record = EmbeddingConfigRecord(
            enabled: enabled,
            sceneId: "scene.memory.embedding",
            providerProfileId: normalizedOptionalString(providerProfileId),
            modelId: normalizedOptionalString(modelId)
        )
        persist(record, to: embeddingConfigURL)
        return await embeddingConfigPayload(from: record)
    }

    func getRollupStatusPayload() -> [String: Any] {
        rollupPayload(loadRollupStatus())
    }

    func saveRollupEnabledPayload(_ enabled: Bool) -> [String: Any] {
        let current = loadRollupStatus()
        let next = RollupStatusRecord(
            enabled: enabled,
            lastRunAtMillis: current.lastRunAtMillis,
            lastRunSummary: current.lastRunSummary,
            nextRunAtMillis: enabled ? nextDefaultRollupTimeMillis() : nil
        )
        persist(next, to: rollupStatusURL)
        return rollupPayload(next)
    }

    func runRollupNowPayload() -> [String: Any] {
        let today = dayFormatter.string(from: Date())
        let todayItems = loadShortMemoryItems()
            .filter { $0.date == today }
            .sorted { $0.timestampMillis < $1.timestampMillis }
        let summary: String
        var writes = 0

        if todayItems.isEmpty {
            summary = "无当日短期记忆，跳过整理。"
        } else {
            let longMemory = readLongMemory()
            let existingBullets = Set(
                longMemory
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.hasPrefix("- ") }
                    .map { String($0.dropFirst(2)).lowercased() }
            )
            var appended = [String]()
            for item in todayItems.suffix(8) {
                let normalized = item.content.lowercased()
                if existingBullets.contains(normalized) || appended.contains(item.content) {
                    continue
                }
                appended.append(item.content)
            }
            writes = appended.count

            if appended.isEmpty == false {
                var nextLongMemory = longMemory.trimmingCharacters(in: .newlines)
                if nextLongMemory.isEmpty {
                    nextLongMemory = "# MEMORY\n\n## Long-Term Memory"
                }
                if nextLongMemory.hasSuffix("\n") == false {
                    nextLongMemory.append("\n")
                }
                for entry in appended {
                    nextLongMemory.append("- \(entry)\n")
                }
                IOSWorkspaceSupport.writeText(nextLongMemory, to: longMemoryURL)
            }

            summary = "已整理 \(todayItems.count) 条短期记忆，新增 \(writes) 条长期记忆。"
        }

        let nextStatus = RollupStatusRecord(
            enabled: loadRollupStatus().enabled,
            lastRunAtMillis: timestampMillis(),
            lastRunSummary: summary,
            nextRunAtMillis: loadRollupStatus().enabled ? nextDefaultRollupTimeMillis() : nil
        )
        persist(nextStatus, to: rollupStatusURL)
        return [
            "success": true,
            "date": today,
            "summary": summary,
            "longTermWrites": writes,
            "rollupStatus": rollupPayload(nextStatus),
        ]
    }

    func promptContext() -> (soul: String, chatPrompt: String, longMemory: String, recentShortMemory: String) {
        let shortMemory = loadShortMemoryItems()
            .sorted { $0.timestampMillis > $1.timestampMillis }
            .prefix(8)
            .map { "- [\($0.date) \($0.time)] \($0.content)" }
            .joined(separator: "\n")
        return (
            soul: readSoul().trimmingCharacters(in: .whitespacesAndNewlines),
            chatPrompt: readChatPrompt().trimmingCharacters(in: .whitespacesAndNewlines),
            longMemory: readLongMemory().trimmingCharacters(in: .whitespacesAndNewlines),
            recentShortMemory: shortMemory
        )
    }

    func searchMemory(query: String, limit: Int = 8) -> [[String: Any]] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedQuery.isEmpty == false else { return [] }
        let tokens = Set(normalizedQuery.split(whereSeparator: \.isWhitespace).map(String.init))
        guard tokens.isEmpty == false else { return [] }

        var results = [[String: Any]]()
        for item in loadShortMemoryItems() {
            let haystack = item.content.lowercased()
            let hitCount = tokens.filter { haystack.contains($0) }.count
            if hitCount == 0 { continue }
            results.append([
                "id": item.id,
                "text": item.content,
                "source": "short_memory",
                "date": item.date,
                "score": Double(hitCount) / Double(tokens.count),
            ])
        }

        let longLines = readLongMemory()
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false && $0.hasPrefix("#") == false }
        for (index, line) in longLines.enumerated() {
            let normalized = line.replacingOccurrences(of: "^-\\s*", with: "", options: .regularExpression)
            let haystack = normalized.lowercased()
            let hitCount = tokens.filter { haystack.contains($0) }.count
            if hitCount == 0 { continue }
            results.append([
                "id": "long-\(index)",
                "text": normalized,
                "source": "long_memory",
                "date": "",
                "score": Double(hitCount) / Double(tokens.count),
            ])
        }

        return results
            .sorted {
                let left = ($0["score"] as? Double) ?? 0
                let right = ($1["score"] as? Double) ?? 0
                return left > right
            }
            .prefix(max(1, limit))
            .map { $0 }
    }

    private var soulURL: URL {
        IOSWorkspaceSupport.internalRootURL.appendingPathComponent("SOUL.md")
    }

    private var chatPromptURL: URL {
        IOSWorkspaceSupport.internalRootURL.appendingPathComponent("CHAT.md")
    }

    private var longMemoryURL: URL {
        IOSWorkspaceSupport.memoryRootURL.appendingPathComponent("MEMORY.md")
    }

    private var embeddingConfigURL: URL {
        IOSWorkspaceSupport.memoryRootURL.appendingPathComponent("embedding-config.json")
    }

    private var rollupStatusURL: URL {
        IOSWorkspaceSupport.memoryRootURL.appendingPathComponent("rollup-status.json")
    }

    private func dailyShortMemoryURL(for date: Date) -> URL {
        IOSWorkspaceSupport.shortMemoryRootURL.appendingPathComponent("\(dayFormatter.string(from: date)).md")
    }

    private func readSoul() -> String {
        IOSWorkspaceSupport.readText(at: soulURL)
    }

    private func readChatPrompt() -> String {
        IOSWorkspaceSupport.readText(at: chatPromptURL)
    }

    private func readLongMemory() -> String {
        IOSWorkspaceSupport.readText(at: longMemoryURL)
    }

    private func loadEmbeddingConfig() -> EmbeddingConfigRecord {
        if let data = try? Data(contentsOf: embeddingConfigURL),
           let record = try? JSONDecoder().decode(EmbeddingConfigRecord.self, from: data) {
            return record
        }
        return EmbeddingConfigRecord(
            enabled: false,
            sceneId: "scene.memory.embedding",
            providerProfileId: nil,
            modelId: nil
        )
    }

    private func loadRollupStatus() -> RollupStatusRecord {
        if let data = try? Data(contentsOf: rollupStatusURL),
           let record = try? JSONDecoder().decode(RollupStatusRecord.self, from: data) {
            return record
        }
        return RollupStatusRecord(
            enabled: false,
            lastRunAtMillis: nil,
            lastRunSummary: nil,
            nextRunAtMillis: nil
        )
    }

    private func persist<T: Encodable>(_ value: T, to url: URL) {
        IOSWorkspaceSupport.ensureReady()
        IOSWorkspaceSupport.createDirectoryIfNeeded(url.deletingLastPathComponent())
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func embeddingConfigPayload(from record: EmbeddingConfigRecord) async -> [String: Any] {
        let profilesPayload = await providerStore.listProfilesPayload()
        let profiles = (profilesPayload["profiles"] as? [[String: Any]]) ?? []
        let matchedProfile = profiles.first(where: {
            ($0["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == record.providerProfileId
        })
        let resolvedModelID = record.modelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let configured = matchedProfile != nil && resolvedModelID?.isEmpty == false
        return [
            "enabled": record.enabled,
            "configured": configured,
            "sceneId": record.sceneId,
            "providerProfileId": record.providerProfileId ?? NSNull(),
            "providerProfileName": matchedProfile?["name"] ?? NSNull(),
            "modelId": resolvedModelID ?? NSNull(),
            "apiBase": matchedProfile?["baseUrl"] ?? NSNull(),
            "hasApiKey": ((matchedProfile?["apiKey"] as? String)?.isEmpty == false),
        ]
    }

    private func rollupPayload(_ record: RollupStatusRecord) -> [String: Any] {
        [
            "enabled": record.enabled,
            "lastRunAtMillis": record.lastRunAtMillis ?? NSNull(),
            "lastRunSummary": record.lastRunSummary ?? NSNull(),
            "nextRunAtMillis": record.nextRunAtMillis ?? NSNull(),
        ]
    }

    private func loadShortMemoryItems() -> [ShortMemoryItem] {
        IOSWorkspaceSupport.ensureReady()
        IOSWorkspaceSupport.createDirectoryIfNeeded(IOSWorkspaceSupport.shortMemoryRootURL)
        let fileURLs = (try? FileManager.default.contentsOfDirectory(
            at: IOSWorkspaceSupport.shortMemoryRootURL,
            includingPropertiesForKeys: nil
        )) ?? []
        return fileURLs
            .filter { $0.pathExtension.lowercased() == "md" }
            .flatMap(parseShortMemoryFile)
    }

    private func parseShortMemoryFile(_ url: URL) -> [ShortMemoryItem] {
        let day = url.deletingPathExtension().lastPathComponent
        guard let fileDate = dayFormatter.date(from: day) else { return [] }
        let text = IOSWorkspaceSupport.readText(at: url)
        let pattern = #"^- \[(\d{2}:\d{2}:\d{2})\] (.+)$"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex?.matches(in: text, options: [], range: range) ?? []
        return matches.compactMap { match in
            guard let timeRange = Range(match.range(at: 1), in: text),
                  let contentRange = Range(match.range(at: 2), in: text) else {
                return nil
            }
            let time = String(text[timeRange])
            let content = String(text[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let timestamp = timestamp(from: day, time: time) ?? Int(fileDate.timeIntervalSince1970 * 1000)
            return ShortMemoryItem(
                id: "\(day)-\(time)-\(abs(content.hashValue))",
                date: day,
                time: time,
                content: content,
                timestampMillis: timestamp
            )
        }
    }

    private func timestamp(from day: String, time: String) -> Int? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let date = formatter.date(from: "\(day) \(time)") else { return nil }
        return Int(date.timeIntervalSince1970 * 1000)
    }

    private func nextDefaultRollupTimeMillis() -> Int {
        let now = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let components = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        let next = calendar.date(from: DateComponents(
            timeZone: .current,
            year: components.year,
            month: components.month,
            day: components.day,
            hour: 3,
            minute: 0,
            second: 0
        )) ?? tomorrow
        return Int(next.timeIntervalSince1970 * 1000)
    }

    private func timestampMillis() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }

    private func normalizedOptionalString(_ raw: String?) -> String? {
        let normalized = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == true ? nil : normalized
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

private struct ShortMemoryItem {
    let id: String
    let date: String
    let time: String
    let content: String
    let timestampMillis: Int

    var payload: [String: Any] {
        [
            "id": id,
            "date": date,
            "time": time,
            "content": content,
            "timestampMillis": timestampMillis,
        ]
    }
}
