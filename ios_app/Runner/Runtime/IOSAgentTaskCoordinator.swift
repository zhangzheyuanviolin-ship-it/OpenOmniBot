import Foundation

@MainActor
final class IOSAgentTaskCoordinator {
    private struct PromptMessage {
        let role: String
        let text: String
        let attachments: [[String: Any]]
    }

    private struct CompletionResult {
        let text: String
        let promptTokens: Int?
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

    static let shared = IOSAgentTaskCoordinator()

    private let conversationArchiveStore = ConversationArchiveStore.shared
    private let modelProviderStore = ModelProviderProfileStore.shared
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

    private init() {}

    func createAgentTask(
        arguments: [String: Any],
        eventSink: @escaping (String, [String: Any]) -> Void
    ) throws {
        let taskID = try normalizedRequiredString(arguments["taskId"], name: "taskId")
        let userMessage = try normalizedRequiredString(arguments["userMessage"], name: "userMessage")
        let conversationID = integerValue(arguments["conversationId"])
        let conversationMode = normalizeConversationMode(arguments["conversationMode"] as? String)
        let modelOverride = dictionaryValue(arguments["modelOverride"])
        let reasoningEffort = normalizedOptionalString(arguments["reasoningEffort"])
        let attachments = dictionaryArrayValue(arguments["attachments"])

        activeTasks[taskID]?.cancel()
        activeTasks[taskID] = Task { [weak self] in
            guard let self else { return }
            defer {
                self.activeTasks.removeValue(forKey: taskID)
            }

            let basePayload = self.baseEventPayload(
                taskId: taskID,
                conversationId: conversationID,
                conversationMode: conversationMode
            )

            do {
                eventSink("onAgentThinkingStart", basePayload)
                eventSink(
                    "onAgentThinkingUpdate",
                    basePayload.merging(
                        ["thinking": "正在思考回复…"],
                        uniquingKeysWith: { _, new in new }
                    )
                )

                let promptMessages = self.buildPromptMessages(
                    userMessage: userMessage,
                    conversationId: conversationID,
                    conversationMode: conversationMode,
                    attachments: attachments,
                    legacyConversationHistory: dictionaryArrayValue(arguments["conversationHistory"])
                )
                let config = try await self.modelProviderStore.resolveCompletionRequestConfig(
                    sceneId: "scene.dispatch.model",
                    modelOverride: modelOverride
                )
                let completion = try await self.requestCompletion(
                    config: config,
                    promptMessages: promptMessages,
                    reasoningEffort: reasoningEffort
                )

                if let promptTokens = completion.promptTokens {
                    eventSink(
                        "onAgentPromptTokenUsageChanged",
                        basePayload.merging(
                            ["latestPromptTokens": promptTokens, "promptTokenThreshold": 128_000],
                            uniquingKeysWith: { _, new in new }
                        )
                    )
                }

                eventSink(
                    "onAgentChatMessage",
                    basePayload.merging(
                        ["message": completion.text, "isFinal": true],
                        uniquingKeysWith: { _, new in new }
                    )
                )
                eventSink(
                    "onAgentComplete",
                    basePayload.merging(
                        [
                            "success": true,
                            "outputKind": "chat",
                            "hasUserVisibleOutput": true,
                            "latestPromptTokens": completion.promptTokens ?? NSNull(),
                            "promptTokenThreshold": 128_000,
                        ],
                        uniquingKeysWith: { _, new in new }
                    )
                )
            } catch is CancellationError {
                return
            } catch {
                eventSink(
                    "onAgentError",
                    basePayload.merging(
                        ["error": self.userFacingMessage(for: error)],
                        uniquingKeysWith: { _, new in new }
                    )
                )
            }
        }
    }

    func cancelTask(taskId: String?) {
        if let taskId, taskId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            activeTasks[taskId]?.cancel()
            activeTasks.removeValue(forKey: taskId)
            return
        }

        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
    }

    func postLLMChat(
        text: String,
        modelScene: String,
        modelOverride: [String: Any]? = nil,
        reasoningEffort: String? = nil
    ) async throws -> String {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedText.isEmpty == false else {
            throw CoordinatorError.invalidArguments("text is empty")
        }
        let config = try await modelProviderStore.resolveCompletionRequestConfig(
            sceneId: modelScene,
            modelOverride: modelOverride
        )
        let completion = try await requestCompletion(
            config: config,
            promptMessages: [PromptMessage(role: "user", text: normalizedText, attachments: [])],
            reasoningEffort: normalizedOptionalString(reasoningEffort)
        )
        return completion.text
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

    private func buildPromptMessages(
        userMessage: String,
        conversationId: Int?,
        conversationMode: String,
        attachments: [[String: Any]],
        legacyConversationHistory: [[String: Any]]
    ) -> [PromptMessage] {
        var promptMessages = promptMessagesFromArchive(
            conversationId: conversationId,
            conversationMode: conversationMode
        )

        if promptMessages.isEmpty {
            promptMessages = promptMessagesFromLegacyHistory(legacyConversationHistory)
        }

        if attachments.isEmpty == false,
           let last = promptMessages.last,
           last.role == "user",
           last.text.trimmingCharacters(in: .whitespacesAndNewlines) == userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        {
            promptMessages.removeLast()
        }

        let normalizedUserMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedUserMessage.isEmpty == false {
            let shouldAppend =
                promptMessages.last?.role != "user" ||
                promptMessages.last?.text.trimmingCharacters(in: .whitespacesAndNewlines) != normalizedUserMessage ||
                attachments.isEmpty == false
            if shouldAppend {
                promptMessages.append(
                    PromptMessage(
                        role: "user",
                        text: normalizedUserMessage,
                        attachments: attachments
                    )
                )
            }
        }

        return promptMessages
    }

    private func promptMessagesFromArchive(
        conversationId: Int?,
        conversationMode: String
    ) -> [PromptMessage] {
        guard let conversationId, conversationId > 0 else { return [] }

        let messages = conversationArchiveStore.listConversationMessages(
            conversationId: conversationId,
            mode: conversationMode
        )

        return messages.reversed().compactMap { message in
            guard integerValue(message["type"]) == 1 else { return nil }
            let sender = integerValue(message["user"])
            let role: String
            switch sender {
            case 1:
                role = "user"
            case 2:
                role = "assistant"
            default:
                return nil
            }

            guard
                let content = dictionaryValue(message["content"]),
                let text = normalizedOptionalString(content["text"])
            else {
                return nil
            }

            return PromptMessage(role: role, text: text, attachments: [])
        }
    }

    private func promptMessagesFromLegacyHistory(_ history: [[String: Any]]) -> [PromptMessage] {
        history.compactMap { item in
            guard
                let role = normalizedOptionalString(item["role"]),
                role == "user" || role == "assistant",
                let text = normalizedOptionalString(item["content"])
            else {
                return nil
            }
            return PromptMessage(role: role, text: text, attachments: [])
        }
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

        var messages = [[String: Any]]()
        messages.append(["role": "system", "content": systemPrompt])
        messages.append(contentsOf: promptMessages.map { promptMessage in
            [
                "role": promptMessage.role,
                "content": openAIContent(for: promptMessage),
            ]
        })

        var body: [String: Any] = [
            "model": config.modelId,
            "messages": messages,
            "stream": false,
        ]
        if let reasoningEffort {
            body["reasoning_effort"] = reasoningEffort
        }
        return body
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
            return CompletionResult(text: outputText, promptTokens: promptTokens)
        }

        if
            let choices = object["choices"] as? [[String: Any]],
            let firstChoice = choices.first
        {
            if let message = dictionaryValue(firstChoice["message"]) {
                if let content = parseOpenAIMessageContent(message["content"]) {
                    return CompletionResult(text: content, promptTokens: promptTokens)
                }
            }
            if let text = normalizedOptionalString(firstChoice["text"]) {
                return CompletionResult(text: text, promptTokens: promptTokens)
            }
        }

        throw CoordinatorError.invalidResponse("模型没有返回可展示的回复。")
    }

    private func parseAnthropicResponse(_ data: Data) throws -> CompletionResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CoordinatorError.invalidResponse("模型返回内容无法解析。")
        }
        let promptTokens = integerValue(dictionaryValue(object["usage"])?["input_tokens"])
        if
            let contentItems = object["content"] as? [[String: Any]]
        {
            let texts = contentItems.compactMap { item -> String? in
                guard (item["type"] as? String) == "text" else { return nil }
                return normalizedOptionalString(item["text"])
            }
            let merged = texts.joined()
            if merged.isEmpty == false {
                return CompletionResult(text: merged, promptTokens: promptTokens)
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

    private func parseServerError(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let dictionary = object as? [String: Any] {
            if let message = normalizedOptionalString(dictionary["error"]) {
                return message
            }
            if
                let error = dictionaryValue(dictionary["error"]),
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

    private func userFacingMessage(for error: Error) -> String {
        let localized = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if localized.isEmpty == false {
            return localized
        }
        return "暂时无法生成回复，请稍后重试。"
    }

    private func baseEventPayload(
        taskId: String,
        conversationId: Int?,
        conversationMode: String
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "taskId": taskId,
            "conversationMode": conversationMode,
        ]
        if let conversationId {
            payload["conversationId"] = conversationId
        }
        return payload
    }

    private var systemPrompt: String {
        """
        你是 Omnibot 的 iOS 助手。优先直接、准确地回答用户问题。
        如果当前 iOS 版本暂时无法调用某些 Android 专属系统工具，请简短说明限制，并继续给出最有帮助的文本答复。
        默认使用简体中文回答，除非用户明确使用其他语言。
        """
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

        guard
            candidate.isEmpty == false,
            let url = URL(string: candidate),
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
