import Foundation

@MainActor
final class ConversationArchiveStore {
    private struct StoredConversation: Codable {
        let id: Int
        let mode: String
        let isArchived: Bool
        let title: String
        let summary: String?
        let contextSummary: String?
        let contextSummaryCutoffEntryDbId: Int?
        let contextSummaryUpdatedAt: Int
        let status: Int
        let lastMessage: String?
        let messageCount: Int
        let latestPromptTokens: Int
        let promptTokenThreshold: Int
        let latestPromptTokensUpdatedAt: Int
        let createdAt: Int
        let updatedAt: Int

        var payload: [String: Any] {
            [
                "id": id,
                "mode": mode,
                "isArchived": isArchived,
                "title": title,
                "summary": summary ?? NSNull(),
                "contextSummary": contextSummary ?? NSNull(),
                "contextSummaryCutoffEntryDbId": contextSummaryCutoffEntryDbId ?? NSNull(),
                "contextSummaryUpdatedAt": contextSummaryUpdatedAt,
                "status": status,
                "lastMessage": lastMessage ?? NSNull(),
                "messageCount": messageCount,
                "latestPromptTokens": latestPromptTokens,
                "promptTokenThreshold": promptTokenThreshold,
                "latestPromptTokensUpdatedAt": latestPromptTokensUpdatedAt,
                "createdAt": createdAt,
                "updatedAt": updatedAt,
            ]
        }
    }

    enum StoreError: LocalizedError {
        case invalidConversationID
        case conversationNotFound

        var errorDescription: String? {
            switch self {
            case .invalidConversationID:
                return "Conversation ID is invalid."
            case .conversationNotFound:
                return "Conversation was not found."
            }
        }
    }

    static let shared = ConversationArchiveStore()

    private let defaults = UserDefaults.standard
    private let conversationsKey = "omnibot.ios.conversations_v1"
    private let currentConversationKeyPrefix = "omnibot.ios.current_conversation_id."
    private let messagesKeyPrefix = "omnibot.ios.conversation_messages."

    private init() {}

    func listConversationPayloads() -> [[String: Any]] {
        loadConversations()
            .sorted(by: sortConversations(left:right:))
            .map(\.payload)
    }

    func createConversation(title: String, summary: String?, mode: String) -> [String: Any] {
        var conversations = loadConversations()
        let now = timestampMillis()
        let conversation = StoredConversation(
            id: nextConversationID(from: conversations),
            mode: normalizeMode(mode),
            isArchived: false,
            title: sanitizedTitle(title),
            summary: normalizedOptionalString(summary),
            contextSummary: nil,
            contextSummaryCutoffEntryDbId: nil,
            contextSummaryUpdatedAt: 0,
            status: 0,
            lastMessage: nil,
            messageCount: 0,
            latestPromptTokens: 0,
            promptTokenThreshold: 128_000,
            latestPromptTokensUpdatedAt: 0,
            createdAt: now,
            updatedAt: now
        )
        conversations.append(conversation)
        persistConversations(conversations)
        return conversation.payload
    }

    func updateConversation(from payload: [String: Any]) throws -> [String: Any] {
        var conversations = loadConversations()
        guard let conversationID = integerValue(payload["id"]), conversationID > 0 else {
            throw StoreError.invalidConversationID
        }
        guard let existingIndex = conversations.firstIndex(where: { $0.id == conversationID }) else {
            throw StoreError.conversationNotFound
        }

        let existing = conversations[existingIndex]
        let updated = StoredConversation(
            id: existing.id,
            mode: normalizeMode(stringValue(payload["mode"]) ?? existing.mode),
            isArchived: boolValue(payload["isArchived"]) ?? existing.isArchived,
            title: normalizedFieldString(payload, key: "title") ?? existing.title,
            summary: normalizedFieldOptionalString(payload, key: "summary", fallback: existing.summary),
            contextSummary: normalizedFieldOptionalString(payload, key: "contextSummary", fallback: existing.contextSummary),
            contextSummaryCutoffEntryDbId: normalizedFieldOptionalInt(
                payload,
                key: "contextSummaryCutoffEntryDbId",
                fallback: existing.contextSummaryCutoffEntryDbId
            ),
            contextSummaryUpdatedAt: normalizedFieldInt(
                payload,
                key: "contextSummaryUpdatedAt",
                fallback: existing.contextSummaryUpdatedAt
            ),
            status: normalizedFieldInt(payload, key: "status", fallback: existing.status),
            lastMessage: normalizedFieldOptionalString(payload, key: "lastMessage", fallback: existing.lastMessage),
            messageCount: normalizedFieldInt(payload, key: "messageCount", fallback: existing.messageCount),
            latestPromptTokens: normalizedFieldInt(
                payload,
                key: "latestPromptTokens",
                fallback: existing.latestPromptTokens
            ),
            promptTokenThreshold: max(
                1,
                normalizedFieldInt(
                    payload,
                    key: "promptTokenThreshold",
                    fallback: existing.promptTokenThreshold
                )
            ),
            latestPromptTokensUpdatedAt: normalizedFieldInt(
                payload,
                key: "latestPromptTokensUpdatedAt",
                fallback: existing.latestPromptTokensUpdatedAt
            ),
            createdAt: normalizedFieldInt(payload, key: "createdAt", fallback: existing.createdAt),
            updatedAt: timestampMillis()
        )
        conversations[existingIndex] = updated
        persistConversations(conversations)
        return updated.payload
    }

    func updateConversationTitle(conversationId: Int, newTitle: String) throws -> [String: Any] {
        try updateConversationField(conversationId: conversationId) { conversation in
            let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return StoredConversation(
                id: conversation.id,
                mode: conversation.mode,
                isArchived: conversation.isArchived,
                title: trimmedTitle.isEmpty ? conversation.title : trimmedTitle,
                summary: conversation.summary,
                contextSummary: conversation.contextSummary,
                contextSummaryCutoffEntryDbId: conversation.contextSummaryCutoffEntryDbId,
                contextSummaryUpdatedAt: conversation.contextSummaryUpdatedAt,
                status: conversation.status,
                lastMessage: conversation.lastMessage,
                messageCount: conversation.messageCount,
                latestPromptTokens: conversation.latestPromptTokens,
                promptTokenThreshold: conversation.promptTokenThreshold,
                latestPromptTokensUpdatedAt: conversation.latestPromptTokensUpdatedAt,
                createdAt: conversation.createdAt,
                updatedAt: timestampMillis()
            )
        }
    }

    func updateConversationPromptTokenThreshold(conversationId: Int, promptTokenThreshold: Int) throws -> [String: Any] {
        try updateConversationField(conversationId: conversationId) { conversation in
            return StoredConversation(
                id: conversation.id,
                mode: conversation.mode,
                isArchived: conversation.isArchived,
                title: conversation.title,
                summary: conversation.summary,
                contextSummary: conversation.contextSummary,
                contextSummaryCutoffEntryDbId: conversation.contextSummaryCutoffEntryDbId,
                contextSummaryUpdatedAt: conversation.contextSummaryUpdatedAt,
                status: conversation.status,
                lastMessage: conversation.lastMessage,
                messageCount: conversation.messageCount,
                latestPromptTokens: conversation.latestPromptTokens,
                promptTokenThreshold: max(1, promptTokenThreshold),
                latestPromptTokensUpdatedAt: conversation.latestPromptTokensUpdatedAt,
                createdAt: conversation.createdAt,
                updatedAt: timestampMillis()
            )
        }
    }

    func completeConversation(conversationId: Int) throws -> [String: Any] {
        try updateConversationField(conversationId: conversationId) { conversation in
            return StoredConversation(
                id: conversation.id,
                mode: conversation.mode,
                isArchived: conversation.isArchived,
                title: conversation.title,
                summary: conversation.summary,
                contextSummary: conversation.contextSummary,
                contextSummaryCutoffEntryDbId: conversation.contextSummaryCutoffEntryDbId,
                contextSummaryUpdatedAt: conversation.contextSummaryUpdatedAt,
                status: 1,
                lastMessage: conversation.lastMessage,
                messageCount: conversation.messageCount,
                latestPromptTokens: conversation.latestPromptTokens,
                promptTokenThreshold: conversation.promptTokenThreshold,
                latestPromptTokensUpdatedAt: conversation.latestPromptTokensUpdatedAt,
                createdAt: conversation.createdAt,
                updatedAt: timestampMillis()
            )
        }
    }

    func deleteConversation(conversationId: Int) -> [String: Any]? {
        var conversations = loadConversations()
        guard let existingIndex = conversations.firstIndex(where: { $0.id == conversationId }) else {
            return nil
        }
        let removed = conversations.remove(at: existingIndex)
        persistConversations(conversations)
        clearAllMessageThreads(for: conversationId)
        clearCurrentConversationReferences(for: conversationId)
        return removed.payload
    }

    func setCurrentConversationId(_ conversationId: Int?, mode: String) {
        let key = currentConversationKey(mode: mode)
        if let conversationId, conversationId > 0 {
            defaults.set(conversationId, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func listConversationMessages(conversationId: Int, mode: String) -> [[String: Any]] {
        loadMessagePayloads(for: messageStorageKey(conversationId: conversationId, mode: mode))
    }

    func replaceConversationMessages(
        conversationId: Int,
        mode: String,
        messages: [[String: Any]]
    ) {
        let normalizedMessages = sanitizeMessagePayloads(messages)
        persistMessagePayloads(
            normalizedMessages,
            for: messageStorageKey(conversationId: conversationId, mode: mode)
        )
        refreshConversationStats(
            conversationId: conversationId,
            mode: normalizeMode(mode),
            messages: normalizedMessages
        )
    }

    func upsertConversationUiCard(
        conversationId: Int,
        mode: String,
        entryId: String,
        cardData: [String: Any],
        createdAt: Int
    ) {
        let storageKey = messageStorageKey(conversationId: conversationId, mode: mode)
        var messages = loadMessagePayloads(for: storageKey)
        let normalizedEntryID = entryId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedEntryID.isEmpty == false else { return }

        let cardMessage: [String: Any] = [
            "id": normalizedEntryID,
            "type": 2,
            "user": 3,
            "content": [
                "cardData": sanitizeJSONValue(cardData),
                "id": normalizedEntryID,
            ],
            "isLoading": false,
            "isFirst": false,
            "isError": false,
            "isSummarizing": false,
            "createAt": createdAt > 0 ? createdAt : timestampMillis(),
        ]

        if let index = messages.firstIndex(where: { messagePayload in
            if let messageID = stringValue(messagePayload["id"]), messageID == normalizedEntryID {
                return true
            }
            let content = dictionaryValue(messagePayload["content"])
            return stringValue(content?["id"]) == normalizedEntryID
        }) {
            messages[index] = cardMessage
        } else {
            messages.insert(cardMessage, at: 0)
        }

        persistMessagePayloads(messages, for: storageKey)
        refreshConversationStats(
            conversationId: conversationId,
            mode: normalizeMode(mode),
            messages: messages
        )
    }

    func clearConversationMessages(conversationId: Int, mode: String) {
        let normalizedMode = normalizeMode(mode)
        defaults.removeObject(forKey: messageStorageKey(conversationId: conversationId, mode: normalizedMode))
        refreshConversationStats(conversationId: conversationId, mode: normalizedMode, messages: [])
    }

    func upsertUserMessage(
        conversationId: Int,
        conversationMode: String,
        entryId: String,
        text: String,
        attachments: [[String: Any]] = [],
        createdAtMillis: Int? = nil
    ) {
        upsertTextMessage(
            conversationId: conversationId,
            mode: conversationMode,
            entryId: entryId,
            user: 1,
            text: text,
            attachments: attachments,
            isError: false,
            createdAtMillis: createdAtMillis
        )
    }

    func upsertAssistantMessage(
        conversationId: Int,
        conversationMode: String,
        entryId: String,
        text: String,
        attachments: [[String: Any]] = [],
        isError: Bool = false,
        createdAtMillis: Int? = nil
    ) {
        upsertTextMessage(
            conversationId: conversationId,
            mode: conversationMode,
            entryId: entryId,
            user: 2,
            text: text,
            attachments: attachments,
            isError: isError,
            createdAtMillis: createdAtMillis
        )
    }

    func updatePromptTokenUsage(
        conversationId: Int,
        promptTokens: Int,
        threshold: Int
    ) {
        guard promptTokens >= 0, threshold > 0 else { return }
        do {
            _ = try updateConversation(
                from: [
                    "id": conversationId,
                    "latestPromptTokens": promptTokens,
                    "promptTokenThreshold": threshold,
                    "latestPromptTokensUpdatedAt": timestampMillis(),
                ]
            )
        } catch {
            return
        }
    }

    func generateConversationSummary(from conversationHistory: String) -> String? {
        let normalized = conversationHistory
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.isEmpty == false })?
            .replacingOccurrences(of: "[^\\p{L}\\p{N}\\s]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, normalized.isEmpty == false else {
            return nil
        }
        return String(normalized.prefix(10))
    }

    private func updateConversationField(
        conversationId: Int,
        mutate: (StoredConversation) -> StoredConversation
    ) throws -> [String: Any] {
        var conversations = loadConversations()
        guard let existingIndex = conversations.firstIndex(where: { $0.id == conversationId }) else {
            throw StoreError.conversationNotFound
        }
        let updated = mutate(conversations[existingIndex])
        conversations[existingIndex] = updated
        persistConversations(conversations)
        return updated.payload
    }

    private func upsertTextMessage(
        conversationId: Int,
        mode: String,
        entryId: String,
        user: Int,
        text: String,
        attachments: [[String: Any]],
        isError: Bool,
        createdAtMillis: Int?
    ) {
        let normalizedEntryID = entryId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard conversationId > 0, normalizedEntryID.isEmpty == false else { return }

        let storageKey = messageStorageKey(conversationId: conversationId, mode: mode)
        var messages = loadMessagePayloads(for: storageKey)
        let existingIndex = messages.firstIndex(where: {
            stringValue($0["id"]) == normalizedEntryID
        })
        let existing = existingIndex == nil ? nil : messages[existingIndex!]
        let content = contentPayload(
            entryId: normalizedEntryID,
            text: text,
            attachments: attachments,
            fallback: dictionaryValue(existing?["content"])
        )
        let payload: [String: Any] = [
            "id": normalizedEntryID,
            "type": 1,
            "user": user,
            "content": content,
            "isLoading": false,
            "isFirst": false,
            "isError": isError,
            "isSummarizing": false,
            "createAt": createdAtMillis
                ?? integerValue(existing?["createAt"])
                ?? timestampMillis(),
        ]

        if let existingIndex {
            messages[existingIndex] = payload
        } else {
            messages.insert(payload, at: 0)
        }

        persistMessagePayloads(messages, for: storageKey)
        refreshConversationStats(
            conversationId: conversationId,
            mode: normalizeMode(mode),
            messages: messages
        )
    }

    private func contentPayload(
        entryId: String,
        text: String,
        attachments: [[String: Any]],
        fallback: [String: Any]?
    ) -> [String: Any] {
        var content = fallback ?? [:]
        content["id"] = entryId
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedText.isEmpty == false || content["text"] == nil {
            content["text"] = normalizedText
        }
        let normalizedAttachments = attachments.compactMap {
            sanitizeJSONValue($0) as? [String: Any]
        }
        if normalizedAttachments.isEmpty == false {
            content["attachments"] = normalizedAttachments
        } else if fallback?["attachments"] == nil {
            content.removeValue(forKey: "attachments")
        }
        return content
    }

    private func refreshConversationStats(
        conversationId: Int,
        mode: String,
        messages: [[String: Any]]
    ) {
        var conversations = loadConversations()
        guard let existingIndex = conversations.firstIndex(where: {
            $0.id == conversationId && $0.mode == mode
        }) else {
            return
        }
        let existing = conversations[existingIndex]
        let updated = StoredConversation(
            id: existing.id,
            mode: existing.mode,
            isArchived: existing.isArchived,
            title: existing.title,
            summary: existing.summary,
            contextSummary: existing.contextSummary,
            contextSummaryCutoffEntryDbId: existing.contextSummaryCutoffEntryDbId,
            contextSummaryUpdatedAt: existing.contextSummaryUpdatedAt,
            status: existing.status,
            lastMessage: lastMessageText(from: messages),
            messageCount: messages.count,
            latestPromptTokens: existing.latestPromptTokens,
            promptTokenThreshold: existing.promptTokenThreshold,
            latestPromptTokensUpdatedAt: existing.latestPromptTokensUpdatedAt,
            createdAt: existing.createdAt,
            updatedAt: timestampMillis()
        )
        conversations[existingIndex] = updated
        persistConversations(conversations)
    }

    private func lastMessageText(from messages: [[String: Any]]) -> String? {
        for message in messages {
            if let text = extractText(from: message), text.isEmpty == false {
                return text
            }
        }
        return nil
    }

    private func extractText(from message: [String: Any]) -> String? {
        if let content = dictionaryValue(message["content"]),
           let text = stringValue(content["text"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           text.isEmpty == false
        {
            return text
        }
        return nil
    }

    private func clearAllMessageThreads(for conversationId: Int) {
        let keys = defaults.dictionaryRepresentation().keys
        let suffix = ".\(conversationId)"
        for key in keys where key.hasPrefix(messagesKeyPrefix) && key.hasSuffix(suffix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func clearCurrentConversationReferences(for conversationId: Int) {
        let keys = defaults.dictionaryRepresentation().keys
        for key in keys where key.hasPrefix(currentConversationKeyPrefix) {
            if defaults.integer(forKey: key) == conversationId {
                defaults.removeObject(forKey: key)
            }
        }
    }

    private func loadConversations() -> [StoredConversation] {
        guard
            let data = defaults.data(forKey: conversationsKey),
            let conversations = try? JSONDecoder().decode([StoredConversation].self, from: data)
        else {
            return []
        }
        return conversations
    }

    private func persistConversations(_ conversations: [StoredConversation]) {
        let encoded = try? JSONEncoder().encode(conversations)
        defaults.set(encoded, forKey: conversationsKey)
    }

    private func nextConversationID(from conversations: [StoredConversation]) -> Int {
        let maxID = conversations.map(\.id).max() ?? 0
        return max(maxID + 1, 1)
    }

    private func currentConversationKey(mode: String) -> String {
        "\(currentConversationKeyPrefix)\(normalizeMode(mode))"
    }

    private func messageStorageKey(conversationId: Int, mode: String) -> String {
        "\(messagesKeyPrefix)\(normalizeMode(mode)).\(conversationId)"
    }

    private func loadMessagePayloads(for key: String) -> [[String: Any]] {
        guard
            let data = defaults.data(forKey: key),
            let object = try? JSONSerialization.jsonObject(with: data),
            let payloads = object as? [[String: Any]]
        else {
            return []
        }
        return sanitizeMessagePayloads(payloads)
    }

    private func persistMessagePayloads(_ payloads: [[String: Any]], for key: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: payloads) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    private func sanitizeMessagePayloads(_ payloads: [[String: Any]]) -> [[String: Any]] {
        payloads.compactMap { payload in
            sanitizeJSONValue(payload) as? [String: Any]
        }
    }

    private func sanitizeJSONValue(_ value: Any) -> Any {
        switch value {
        case let dictionary as [String: Any]:
            return dictionary.reduce(into: [String: Any]()) { partialResult, entry in
                partialResult[entry.key] = sanitizeJSONValue(entry.value)
            }
        case let dictionary as [AnyHashable: Any]:
            return dictionary.reduce(into: [String: Any]()) { partialResult, entry in
                partialResult[String(describing: entry.key)] = sanitizeJSONValue(entry.value)
            }
        case let array as [Any]:
            return array.map(sanitizeJSONValue)
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let url as URL:
            return url.absoluteString
        case is NSNull, is String, is Bool, is NSNumber:
            return value
        case let number as Int64:
            return Int(number)
        case let number as UInt64:
            return Int(number)
        default:
            return String(describing: value)
        }
    }

    private func sortConversations(left: StoredConversation, right: StoredConversation) -> Bool {
        if left.updatedAt != right.updatedAt {
            return left.updatedAt > right.updatedAt
        }
        let leftPenalty = left.mode == "subagent" ? 1 : 0
        let rightPenalty = right.mode == "subagent" ? 1 : 0
        if leftPenalty != rightPenalty {
            return leftPenalty < rightPenalty
        }
        return left.createdAt > right.createdAt
    }

    private func normalizeMode(_ raw: String?) -> String {
        let normalized = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return normalized.isEmpty ? "normal" : normalized
    }

    private func sanitizedTitle(_ raw: String) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "新对话" : normalized
    }

    private func timestampMillis() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }

    private func normalizedOptionalString(_ raw: String?) -> String? {
        let normalized = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == true ? nil : normalized
    }

    private func normalizedFieldString(_ payload: [String: Any], key: String) -> String? {
        if payload.keys.contains(key) == false {
            return nil
        }
        guard let value = stringValue(payload[key])?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return value.isEmpty ? nil : value
    }

    private func normalizedFieldOptionalString(
        _ payload: [String: Any],
        key: String,
        fallback: String?
    ) -> String? {
        if payload.keys.contains(key) == false {
            return fallback
        }
        if payload[key] is NSNull {
            return nil
        }
        return normalizedOptionalString(stringValue(payload[key])) ?? nil
    }

    private func normalizedFieldOptionalInt(
        _ payload: [String: Any],
        key: String,
        fallback: Int?
    ) -> Int? {
        if payload.keys.contains(key) == false {
            return fallback
        }
        if payload[key] is NSNull {
            return nil
        }
        return integerValue(payload[key]) ?? fallback
    }

    private func normalizedFieldInt(
        _ payload: [String: Any],
        key: String,
        fallback: Int
    ) -> Int {
        if payload.keys.contains(key) == false {
            return fallback
        }
        return integerValue(payload[key]) ?? fallback
    }

    private func stringValue(_ raw: Any?) -> String? {
        switch raw {
        case let string as String:
            return string
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

    private func boolValue(_ raw: Any?) -> Bool? {
        switch raw {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.intValue != 0
        case let string as String:
            return string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
        default:
            return nil
        }
    }

    private func dictionaryValue(_ raw: Any?) -> [String: Any]? {
        if let dictionary = raw as? [String: Any] {
            return dictionary
        }
        if let dictionary = raw as? [AnyHashable: Any] {
            return dictionary.reduce(into: [String: Any]()) { partialResult, entry in
                partialResult[String(describing: entry.key)] = entry.value
            }
        }
        return nil
    }
}
