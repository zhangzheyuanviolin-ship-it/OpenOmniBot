import Foundation

@MainActor
final class IOSChatTaskCoordinator {
    private struct PromptMessage {
        let role: String
        let text: String
        let attachments: [[String: Any]]
    }

    private struct CompletionResult {
        let text: String
        let reasoning: String?
        let promptTokens: Int?
        let attachments: [[String: Any]]
    }

    private struct PersistenceState {
        let conversationId: Int
        let conversationMode: String
        let userEntryId: String
        let assistantEntryId: String
        let promptTokenThreshold: Int
    }

    enum CoordinatorError: LocalizedError {
        case invalidArguments(String)
        case providerUnavailable
        case invalidBaseURL
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case let .invalidArguments(message):
                return message
            case .providerUnavailable:
                return "当前没有可用的模型提供商，请先在设置中配置模型。"
            case .invalidBaseURL:
                return "模型提供商地址无效。"
            case let .invalidResponse(message):
                return message
            }
        }
    }

    static let shared = IOSChatTaskCoordinator()

    private let conversationArchiveStore = ConversationArchiveStore.shared
    private let modelProviderStore = ModelProviderProfileStore.shared
    private let memoryStore = WorkspaceMemoryStore.shared
    private let canonicalEndpointSuffixes = [
        "/v1/chat/completions",
        "/chat/completions",
        "/v1/models",
        "/models",
        "/v1/messages",
        "/messages",
    ]
    private let directRequestURLMarker = "#"

    private var activeTasks: [String: Task<Void, Never>] = [:]
    private var persistenceStates: [String: PersistenceState] = [:]

    private init() {}

    func createChatTask(
        arguments: [String: Any],
        eventSink: @escaping (String, [String: Any]) -> Void,
        syncConversation: @escaping (Int, String) -> Void
    ) throws {
        let taskID = try normalizedRequiredString(arguments["taskID"], name: "taskID")
        let content = dictionaryArrayValue(arguments["content"])
        let provider = normalizedOptionalString(arguments["provider"])
        let conversationId = integerValue(arguments["conversationId"])
        let conversationMode = normalizeConversationMode(arguments["conversationMode"] as? String)
        let userMessage = normalizedOptionalString(arguments["userMessage"]) ?? ""
        let userAttachments = dictionaryArrayValue(arguments["userAttachments"])
        let modelOverride = dictionaryValue(arguments["modelOverride"])
        let reasoningEffort = normalizedOptionalString(arguments["reasoningEffort"])
        let openClawConfig = dictionaryValue(arguments["openClawConfig"])

        activeTasks[taskID]?.cancel()
        if let conversationId, conversationId > 0 {
            if userMessage.isEmpty == false || userAttachments.isEmpty == false {
                let userEntryID = "\(taskID)-user"
                conversationArchiveStore.upsertUserMessage(
                    conversationId: conversationId,
                    conversationMode: conversationMode,
                    entryId: userEntryID,
                    text: userMessage,
                    attachments: userAttachments
                )
                syncConversation(conversationId, conversationMode)
            }
            let threshold = currentPromptTokenThreshold(conversationId: conversationId)
            persistenceStates[taskID] = PersistenceState(
                conversationId: conversationId,
                conversationMode: conversationMode,
                userEntryId: "\(taskID)-user",
                assistantEntryId: "\(taskID)-assistant",
                promptTokenThreshold: threshold
            )
        } else {
            persistenceStates.removeValue(forKey: taskID)
        }

        activeTasks[taskID] = Task { [weak self] in
            guard let self else { return }
            defer {
                self.activeTasks.removeValue(forKey: taskID)
            }

            do {
                let promptMessages = self.buildPromptMessages(
                    content: content,
                    fallbackUserMessage: userMessage,
                    userAttachments: userAttachments
                )
                let completion: CompletionResult
                if provider == "openclaw", let openClawConfig {
                    completion = try await self.requestOpenClawCompletion(
                        openClawConfig: openClawConfig,
                        promptMessages: promptMessages
                    )
                } else {
                    let config = try await self.modelProviderStore.resolveCompletionRequestConfig(
                        sceneId: "scene.dispatch.model",
                        modelOverride: modelOverride
                    )
                    completion = try await self.requestCompletion(
                        config: config,
                        promptMessages: promptMessages,
                        reasoningEffort: reasoningEffort
                    )
                }

                if let state = self.persistenceStates[taskID] {
                    if let promptTokens = completion.promptTokens {
                        self.conversationArchiveStore.updatePromptTokenUsage(
                            conversationId: state.conversationId,
                            promptTokens: promptTokens,
                            threshold: state.promptTokenThreshold
                        )
                        eventSink(
                            "onAgentPromptTokenUsageChanged",
                            [
                                "taskId": taskID,
                                "conversationId": state.conversationId,
                                "conversationMode": state.conversationMode,
                                "latestPromptTokens": promptTokens,
                                "promptTokenThreshold": state.promptTokenThreshold,
                            ]
                        )
                    }
                    self.conversationArchiveStore.upsertAssistantMessage(
                        conversationId: state.conversationId,
                        conversationMode: state.conversationMode,
                        entryId: state.assistantEntryId,
                        text: completion.text,
                        attachments: completion.attachments,
                        isError: false
                    )
                    syncConversation(state.conversationId, state.conversationMode)
                }

                var payload: [String: Any] = ["text": completion.text]
                if let reasoning = completion.reasoning {
                    payload["thinking"] = reasoning
                    payload["reasoning"] = reasoning
                }
                if let promptTokens = completion.promptTokens {
                    payload["usage"] = ["prompt_tokens": promptTokens]
                }
                if completion.attachments.isEmpty == false {
                    payload["attachments"] = completion.attachments
                }
                let jsonString = self.jsonString(from: payload)
                eventSink(
                    "onChatMessage",
                    [
                        "taskID": taskID,
                        "content": jsonString,
                        "type": NSNull(),
                    ]
                )
                eventSink("onChatMessageEnd", ["taskID": taskID])
                self.persistenceStates.removeValue(forKey: taskID)
            } catch is CancellationError {
                self.persistenceStates.removeValue(forKey: taskID)
                eventSink("onChatMessageEnd", ["taskID": taskID])
            } catch {
                if let state = self.persistenceStates[taskID] {
                    self.conversationArchiveStore.upsertAssistantMessage(
                        conversationId: state.conversationId,
                        conversationMode: state.conversationMode,
                        entryId: state.assistantEntryId,
                        text: self.userFacingMessage(for: error),
                        isError: true
                    )
                    syncConversation(state.conversationId, state.conversationMode)
                }
                eventSink(
                    "onChatMessage",
                    [
                        "taskID": taskID,
                        "content": self.jsonString(from: ["text": self.userFacingMessage(for: error)]),
                        "type": "error",
                    ]
                )
                eventSink("onChatMessageEnd", ["taskID": taskID])
                self.persistenceStates.removeValue(forKey: taskID)
            }
        }
    }

    func cancelTask(taskId: String?) {
        if let taskId, taskId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            activeTasks[taskId]?.cancel()
            activeTasks.removeValue(forKey: taskId)
            persistenceStates.removeValue(forKey: taskId)
            return
        }
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
        persistenceStates.removeAll()
    }

    private func buildPromptMessages(
        content: [[String: Any]],
        fallbackUserMessage: String,
        userAttachments: [[String: Any]]
    ) -> [PromptMessage] {
        var messages = content.compactMap { item -> PromptMessage? in
            guard let role = normalizedOptionalString(item["role"]),
                  role == "user" || role == "assistant" || role == "system"
            else {
                return nil
            }
            let text = normalizedOptionalString(item["content"]) ?? ""
            return PromptMessage(role: role, text: text, attachments: [])
        }

        let normalizedFallbackMessage = fallbackUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedFallbackMessage.isEmpty == false,
           (messages.last?.role != "user" || messages.last?.text != normalizedFallbackMessage || userAttachments.isEmpty == false)
        {
            messages.append(
                PromptMessage(
                    role: "user",
                    text: normalizedFallbackMessage,
                    attachments: userAttachments
                )
            )
        }
        return messages
    }

    private func requestCompletion(
        config: ModelProviderProfileStore.CompletionRequestConfig,
        promptMessages: [PromptMessage],
        reasoningEffort: String?
    ) async throws -> CompletionResult {
        guard config.apiBase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw CoordinatorError.providerUnavailable
        }

        var request = URLRequest(url: try completionRequestURL(for: config))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if config.protocolType == "anthropic" {
            if config.apiKey.isEmpty == false {
                request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            }
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else if config.apiKey.isEmpty == false {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body = buildRequestBody(
            config: config,
            promptMessages: promptMessages,
            reasoningEffort: reasoningEffort
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CoordinatorError.invalidResponse("模型服务返回异常。")
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw CoordinatorError.invalidResponse(
                parseServerError(from: data) ?? "模型服务请求失败（\(httpResponse.statusCode)）。"
            )
        }

        if config.protocolType == "anthropic" {
            return try parseAnthropicResponse(data)
        }
        return try parseOpenAICompatibleResponse(data)
    }

    private func requestOpenClawCompletion(
        openClawConfig: [String: Any],
        promptMessages: [PromptMessage]
    ) async throws -> CompletionResult {
        guard let baseURL = normalizeBaseURL(normalizedOptionalString(openClawConfig["baseUrl"]) ?? "") else {
            throw CoordinatorError.invalidBaseURL
        }
        let strippedBase = stripDirectRequestURLMarker(baseURL)
        guard let url = URL(string: "\(strippedBase)/v1/chat/completions") else {
            throw CoordinatorError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let token = normalizedOptionalString(openClawConfig["token"]) ?? ""
        if token.isEmpty == false {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let sessionKey = normalizedOptionalString(openClawConfig["sessionKey"]) {
            request.setValue(sessionKey, forHTTPHeaderField: "X-OpenClaw-Session-Key")
        }

        var body: [String: Any] = [
            "model": "openclaw",
            "stream": false,
            "messages": buildOpenAIRequestMessages(promptMessages: promptMessages),
        ]
        if let userID = normalizedOptionalString(openClawConfig["userId"]) {
            body["user"] = userID
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CoordinatorError.invalidResponse("OpenClaw 返回异常。")
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw CoordinatorError.invalidResponse(
                parseServerError(from: data) ?? "OpenClaw 请求失败（\(httpResponse.statusCode)）。"
            )
        }
        return try parseOpenAICompatibleResponse(data)
    }

    private func buildRequestBody(
        config: ModelProviderProfileStore.CompletionRequestConfig,
        promptMessages: [PromptMessage],
        reasoningEffort: String?
    ) -> [String: Any] {
        if config.protocolType == "anthropic" {
            var body: [String: Any] = [
                "model": config.modelId,
                "max_tokens": 2_048,
                "system": systemPrompt,
                "messages": promptMessages.map { promptMessage in
                    [
                        "role": promptMessage.role,
                        "content": anthropicContent(for: promptMessage),
                    ]
                },
            ]
            if let reasoningEffort {
                body["metadata"] = ["reasoning_effort": reasoningEffort]
            }
            return body
        }

        return [
            "model": config.modelId,
            "messages": buildOpenAIRequestMessages(promptMessages: promptMessages),
            "stream": false,
            "reasoning_effort": reasoningEffort ?? NSNull(),
        ]
    }

    private func buildOpenAIRequestMessages(promptMessages: [PromptMessage]) -> [[String: Any]] {
        var messages = [[String: Any]]()
        messages.append(["role": "system", "content": systemPrompt])
        messages.append(contentsOf: promptMessages.map { promptMessage in
            [
                "role": promptMessage.role,
                "content": openAIContent(for: promptMessage),
            ]
        })
        return messages
    }

    private func openAIContent(for promptMessage: PromptMessage) -> Any {
        guard promptMessage.attachments.isEmpty == false else {
            return promptMessage.text
        }

        var items = [[String: Any]]()
        if promptMessage.text.isEmpty == false {
            items.append(["type": "text", "text": promptMessage.text])
        }

        for attachment in promptMessage.attachments {
            if let imageURL = imageURLString(from: attachment) {
                items.append(["type": "image_url", "image_url": ["url": imageURL]])
            }
        }

        return items.isEmpty ? promptMessage.text : items
    }

    private func anthropicContent(for promptMessage: PromptMessage) -> [[String: Any]] {
        var items = [[String: Any]]()
        if promptMessage.text.isEmpty == false {
            items.append(["type": "text", "text": promptMessage.text])
        }

        for attachment in promptMessage.attachments {
            guard let imageURL = imageURLString(from: attachment) else { continue }
            guard let imageSource = anthropicImageSource(from: imageURL) else { continue }
            items.append(["type": "image", "source": imageSource])
        }

        if items.isEmpty {
            return [["type": "text", "text": promptMessage.text]]
        }
        return items
    }

    private func completionRequestURL(
        for config: ModelProviderProfileStore.CompletionRequestConfig
    ) throws -> URL {
        guard let normalizedBase = normalizeBaseURL(config.apiBase) else {
            throw CoordinatorError.invalidBaseURL
        }

        let directRequest = hasDirectRequestURLMarker(normalizedBase)
        let strippedBase = stripDirectRequestURLMarker(normalizedBase)
        let requestString: String
        if directRequest {
            requestString = strippedBase
        } else if config.protocolType == "anthropic" {
            requestString = strippedBase.lowercased().hasSuffix("/v1")
                ? "\(strippedBase)/messages"
                : "\(strippedBase)/v1/messages"
        } else {
            requestString = strippedBase.lowercased().hasSuffix("/v1")
                ? "\(strippedBase)/chat/completions"
                : "\(strippedBase)/v1/chat/completions"
        }

        guard let url = URL(string: requestString) else {
            throw CoordinatorError.invalidBaseURL
        }
        return url
    }

    private func parseOpenAICompatibleResponse(_ data: Data) throws -> CompletionResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CoordinatorError.invalidResponse("模型返回内容无法解析。")
        }

        let promptTokens = integerValue(dictionaryValue(object["usage"])?["prompt_tokens"])
        if let outputText = normalizedOptionalString(object["output_text"]) {
            return CompletionResult(
                text: outputText,
                reasoning: parseReasoning(from: object),
                promptTokens: promptTokens,
                attachments: parseAttachments(from: object)
            )
        }

        if let choices = object["choices"] as? [[String: Any]],
           let firstChoice = choices.first
        {
            if let message = dictionaryValue(firstChoice["message"]) {
                if let content = parseOpenAIMessageContent(message["content"]) {
                    return CompletionResult(
                        text: content,
                        reasoning: parseReasoning(from: object),
                        promptTokens: promptTokens,
                        attachments: parseAttachments(from: object)
                    )
                }
            }
            if let text = normalizedOptionalString(firstChoice["text"]) {
                return CompletionResult(
                    text: text,
                    reasoning: parseReasoning(from: object),
                    promptTokens: promptTokens,
                    attachments: parseAttachments(from: object)
                )
            }
        }

        throw CoordinatorError.invalidResponse("模型没有返回可展示的回复。")
    }

    private func parseAnthropicResponse(_ data: Data) throws -> CompletionResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CoordinatorError.invalidResponse("模型返回内容无法解析。")
        }
        let promptTokens = integerValue(dictionaryValue(object["usage"])?["input_tokens"])
        if let contentItems = object["content"] as? [[String: Any]] {
            let texts = contentItems.compactMap { item -> String? in
                guard (item["type"] as? String) == "text" else { return nil }
                return normalizedOptionalString(item["text"])
            }
            let merged = texts.joined()
            if merged.isEmpty == false {
                return CompletionResult(
                    text: merged,
                    reasoning: parseReasoning(from: object),
                    promptTokens: promptTokens,
                    attachments: parseAttachments(from: object)
                )
            }
        }
        throw CoordinatorError.invalidResponse("模型没有返回可展示的回复。")
    }

    private func parseOpenAIMessageContent(_ raw: Any?) -> String? {
        if let text = normalizedOptionalString(raw) {
            return text
        }
        if let items = raw as? [[String: Any]] {
            let texts = items.compactMap { item -> String? in
                let type = normalizedOptionalString(item["type"])
                if type == nil || type == "text" || type == "output_text" {
                    return normalizedOptionalString(item["text"])
                }
                return nil
            }
            let merged = texts.joined()
            return merged.isEmpty ? nil : merged
        }
        return nil
    }

    private func parseAttachments(from object: [String: Any]) -> [[String: Any]] {
        let directContent = parseAttachmentPayloads(object["content"])
        if directContent.isEmpty == false {
            return directContent
        }
        if let choices = object["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = dictionaryValue(firstChoice["message"])
        {
            return parseAttachmentPayloads(message["content"])
        }
        return []
    }

    private func parseAttachmentPayloads(_ raw: Any?) -> [[String: Any]] {
        guard let items = raw as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let type = normalizedOptionalString(item["type"])?.lowercased() else { return nil }
            if type == "image_url" {
                let imageURL = dictionaryValue(item["image_url"])?["url"]
                return [
                    "isImage": true,
                    "url": normalizedOptionalString(imageURL) ?? "",
                    "mimeType": "image/*",
                ]
            }
            return nil
        }
    }

    private func parseReasoning(from object: [String: Any]) -> String? {
        let directReasoning = mergeNonEmptyTexts([
            parseReasoningPayload(object["reasoning_content"]),
            parseReasoningPayload(object["reasoning"]),
            parseReasoningPayload(object["thinking"]),
        ])
        if let directReasoning {
            return directReasoning
        }

        if let message = dictionaryValue(object["message"]),
           let messageReasoning = mergeNonEmptyTexts([
               parseReasoningPayload(message["reasoning_content"]),
               parseReasoningPayload(message["reasoning"]),
               parseReasoningPayload(message["thinking"]),
               parseReasoningPayload(message["content"]),
           ])
        {
            return messageReasoning
        }

        if let choices = object["choices"] as? [[String: Any]],
           let firstChoice = choices.first
        {
            if let delta = dictionaryValue(firstChoice["delta"]),
               let deltaReasoning = mergeNonEmptyTexts([
                   parseReasoningPayload(delta["reasoning_content"]),
                   parseReasoningPayload(delta["reasoning"]),
                   parseReasoningPayload(delta["thinking"]),
                   parseReasoningPayload(delta["content"]),
               ])
            {
                return deltaReasoning
            }

            if let message = dictionaryValue(firstChoice["message"]),
               let messageReasoning = mergeNonEmptyTexts([
                   parseReasoningPayload(message["reasoning_content"]),
                   parseReasoningPayload(message["reasoning"]),
                   parseReasoningPayload(message["thinking"]),
                   parseReasoningPayload(message["content"]),
               ])
            {
                return messageReasoning
            }
        }

        if let output = object["output"] as? [Any] {
            let outputReasoning = output.compactMap(parseReasoningPayload).joined()
            if outputReasoning.isEmpty == false {
                return outputReasoning
            }
        }

        if let content = object["content"] as? [Any] {
            let contentReasoning = content.compactMap(parseReasoningPayload).joined()
            if contentReasoning.isEmpty == false {
                return contentReasoning
            }
        }

        return nil
    }

    private func parseReasoningPayload(_ raw: Any?) -> String? {
        if let text = normalizedOptionalString(raw) {
            return text
        }

        if let items = raw as? [Any] {
            let merged = items.compactMap(parseReasoningPayload).joined()
            return merged.isEmpty ? nil : merged
        }

        guard let payload = raw as? [String: Any] else {
            return nil
        }

        let type = normalizedOptionalString(payload["type"])?.lowercased()
        if type == "reasoning" || type == "reasoning_text" || type == "thinking" {
            return mergeNonEmptyTexts([
                parseTextPayload(payload["text"]),
                parseTextPayload(payload["content"]),
                parseTextPayload(payload["reasoning_content"]),
                parseTextPayload(payload["reasoning"]),
                parseTextPayload(payload["thinking"]),
            ])
        }

        return mergeNonEmptyTexts([
            parseTextPayload(payload["reasoning_content"]),
            parseTextPayload(payload["reasoning"]),
            parseTextPayload(payload["thinking"]),
            parseReasoningPayload(payload["content"]),
        ])
    }

    private func parseTextPayload(_ raw: Any?) -> String? {
        if let text = normalizedOptionalString(raw) {
            return text
        }

        if let items = raw as? [Any] {
            let merged = items.compactMap(parseTextPayload).joined()
            return merged.isEmpty ? nil : merged
        }

        guard let payload = raw as? [String: Any] else {
            return nil
        }

        let type = normalizedOptionalString(payload["type"])?.lowercased()
        if type == "text" || type == "output_text" {
            return parseTextPayload(payload["text"])
        }

        return mergeNonEmptyTexts([
            parseTextPayload(payload["text"]),
            parseTextPayload(payload["content"]),
        ])
    }

    private func mergeNonEmptyTexts(_ values: [String?]) -> String? {
        let merged = values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined()
        return merged.isEmpty ? nil : merged
    }

    private func parseServerError(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let dictionary = object as? [String: Any] {
            if let message = normalizedOptionalString(dictionary["error"]) {
                return message
            }
            if let error = dictionaryValue(dictionary["error"]),
               let message = normalizedOptionalString(error["message"])
            {
                return message
            }
            if let message = normalizedOptionalString(dictionary["message"]) {
                return message
            }
        }

        return nil
    }

    private var systemPrompt: String {
        let promptContext = memoryStore.promptContext()
        var sections = [
            "你是 Omnibot 的 iOS 聊天助手。优先直接、准确地回答用户问题。",
            "默认使用简体中文回答，除非用户明确使用其他语言。",
        ]
        let soul = promptContext.soul.trimmingCharacters(in: .whitespacesAndNewlines)
        if soul.isEmpty == false {
            sections.append("Workspace Soul:\n\(soul)")
        }
        let chatPrompt = promptContext.chatPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if chatPrompt.isEmpty == false {
            sections.append("Workspace Chat Prompt:\n\(chatPrompt)")
        }
        let longMemory = promptContext.longMemory.trimmingCharacters(in: .whitespacesAndNewlines)
        if longMemory.isEmpty == false {
            sections.append("Workspace Long Memory:\n\(longMemory)")
        }
        return sections.joined(separator: "\n\n")
    }

    private func currentPromptTokenThreshold(conversationId: Int) -> Int {
        let payload = conversationArchiveStore
            .listConversationPayloads()
            .first(where: { integerValue($0["id"]) == conversationId })
        return integerValue(payload?["promptTokenThreshold"]) ?? 128_000
    }

    private func userFacingMessage(for error: Error) -> String {
        let localized = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return localized.isEmpty ? "暂时无法生成回复，请稍后重试。" : localized
    }

    private func jsonString(from payload: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return payload["text"] as? String ?? ""
        }
        return text
    }

    private func imageURLString(from attachment: [String: Any]) -> String? {
        if let dataURL = normalizedOptionalString(attachment["dataUrl"]) {
            return dataURL
        }
        return normalizedOptionalString(attachment["url"])
    }

    private func anthropicImageSource(from rawURL: String) -> [String: Any]? {
        let normalized = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.hasPrefix("data:") else { return nil }
        let components = normalized.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        guard components.count == 2 else { return nil }
        let header = String(components[0])
        let data = String(components[1])
        guard header.contains(";base64") else { return nil }
        let mediaType = header
            .replacingOccurrences(of: "data:", with: "")
            .replacingOccurrences(of: ";base64", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard mediaType.isEmpty == false else { return nil }
        return [
            "type": "base64",
            "media_type": mediaType,
            "data": data,
        ]
    }

    private func normalizeBaseURL(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let hasDirectRequest = hasDirectRequestURLMarker(trimmed)
        let candidate = hasDirectRequest
            ? String(trimmed.dropLast(directRequestURLMarker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            : trimmed
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host?.isEmpty == false
        else {
            return nil
        }
        var result = candidate.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        if hasDirectRequest == false {
            for suffix in canonicalEndpointSuffixes where result.lowercased().hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count))
                break
            }
        }
        result = result.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard result.isEmpty == false else { return nil }
        return hasDirectRequest ? "\(result)\(directRequestURLMarker)" : result
    }

    private func hasDirectRequestURLMarker(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(directRequestURLMarker)
    }

    private func stripDirectRequestURLMarker(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasSuffix(directRequestURLMarker) {
            result.removeLast(directRequestURLMarker.count)
        }
        return result.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
    }

    private func normalizedRequiredString(_ raw: Any?, name: String) throws -> String {
        guard let normalized = normalizedOptionalString(raw) else {
            throw CoordinatorError.invalidArguments("\(name) is empty")
        }
        return normalized
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

    private func normalizeConversationMode(_ raw: String?) -> String {
        let normalized = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return normalized.isEmpty ? "normal" : normalized
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

    private func dictionaryArrayValue(_ raw: Any?) -> [[String: Any]] {
        guard let array = raw as? [Any] else { return [] }
        return array.compactMap { dictionaryValue($0) }
    }
}
