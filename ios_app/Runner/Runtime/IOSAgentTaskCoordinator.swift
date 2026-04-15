import Foundation

@MainActor
final class IOSAgentTaskCoordinator {
    private struct PromptMessage: @unchecked Sendable {
        let role: String
        let text: String
        let attachments: [[String: Any]]
    }

    private struct CompletionResult: Sendable {
        let text: String
        let reasoning: String?
        let promptTokens: Int?
    }

    private struct ToolCall: Sendable {
        let id: String
        let name: String
        let argumentsJSON: String
    }

    private struct AgentRoundResult: @unchecked Sendable {
        let text: String
        let reasoning: String?
        let promptTokens: Int?
        let toolCalls: [ToolCall]
        let assistantMessage: [String: Any]
    }

    private struct AgentToolExecution: @unchecked Sendable {
        let status: String
        let summary: String
        let progress: String
        let resultPreviewJSON: String
        let rawResultJSON: String
        let terminalOutput: String
        let terminalOutputDelta: String
        let terminalSessionId: String?
        let terminalStreamState: String
        let workspaceId: String?
        let interruptedBy: String?
        let interruptionReason: String?
        let artifacts: [[String: Any]]
        let actions: [[String: Any]]
        let success: Bool
    }

    private struct AgentToolDefinition: @unchecked Sendable {
        let name: String
        let displayName: String
        let toolTitle: String
        let toolType: String
        let serverName: String?
        let description: String
        let parameters: [String: Any]
        let handler: @Sendable @MainActor ([String: Any]) async throws -> AgentToolExecution
    }

    private struct PersistenceState: Sendable {
        let conversationId: Int
        let conversationMode: String
        let userEntryId: String
        let assistantEntryId: String
        let promptTokenThreshold: Int
        let userMessageCreatedAtMillis: Int?
    }

    enum CoordinatorError: LocalizedError {
        case invalidArguments(String)
        case providerUnavailable
        case invalidBaseURL
        case invalidResponse(String)
        case fileNotFound(String)
        case taskNotFound(String)

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
            case let .fileNotFound(path):
                return "文件不存在：\(path)"
            case let .taskNotFound(message):
                return message
            }
        }
    }

    static let shared = IOSAgentTaskCoordinator()

    private let conversationArchiveStore = ConversationArchiveStore.shared
    private let modelProviderStore = ModelProviderProfileStore.shared
    private let memoryStore = WorkspaceMemoryStore.shared
    private let scheduledTaskStore = WorkspaceScheduledTaskStore.shared
    private let agentSkillStore = AgentSkillStore.shared
    private let remoteMcpStore = RemoteMcpStore.shared
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
    private var activeToolTasks: [String: Task<AgentToolExecution, Error>] = [:]
    private var requestedToolStops: Set<String> = []

    private init() {}

    func createAgentTask(
        arguments: [String: Any],
        eventSink: @escaping (String, [String: Any]) -> Void,
        syncConversation: @escaping (Int, String) -> Void
    ) throws {
        let taskID = try normalizedRequiredString(arguments["taskId"], name: "taskId")
        let userMessage = try normalizedRequiredString(arguments["userMessage"], name: "userMessage")
        let conversationID = integerValue(arguments["conversationId"])
        let conversationMode = normalizeConversationMode(arguments["conversationMode"] as? String)
        let modelOverride = dictionaryValue(arguments["modelOverride"])
        let reasoningEffort = normalizedOptionalString(arguments["reasoningEffort"])
        let attachments = dictionaryArrayValue(arguments["attachments"])
        let terminalEnvironment = stringDictionaryValue(arguments["terminalEnvironment"])
        let userMessageCreatedAtMillis = integerValue(arguments["userMessageCreatedAt"])

        activeTasks[taskID]?.cancel()
        cancelToolTasks(forTaskId: taskID)

        let persistenceState = makePersistenceState(
            taskId: taskID,
            userMessage: userMessage,
            attachments: attachments,
            conversationId: conversationID,
            conversationMode: conversationMode,
            userMessageCreatedAtMillis: userMessageCreatedAtMillis,
            syncConversation: syncConversation
        )

        activeTasks[taskID] = Task { [weak self] in
            guard let self else { return }
            defer {
                self.activeTasks.removeValue(forKey: taskID)
                self.cancelToolTasks(forTaskId: taskID)
            }

            let basePayload = self.baseEventPayload(
                taskId: taskID,
                conversationId: conversationID,
                conversationMode: conversationMode
            )

            do {
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
                if config.protocolType == "anthropic" {
                    try await self.runTextOnlyFallback(
                        taskId: taskID,
                        basePayload: basePayload,
                        config: config,
                        promptMessages: promptMessages,
                        reasoningEffort: reasoningEffort,
                        persistenceState: persistenceState,
                        eventSink: eventSink,
                        syncConversation: syncConversation
                    )
                    return
                }

                let toolDefinitions = await self.buildToolCatalog(
                    terminalEnvironment: terminalEnvironment
                )
                var messages = self.buildAgentRequestMessages(
                    promptMessages: promptMessages,
                    conversationId: conversationID,
                    conversationMode: conversationMode,
                    scheduledTaskId: normalizedOptionalString(arguments["scheduledTaskId"]),
                    scheduledTaskTitle: normalizedOptionalString(arguments["scheduledTaskTitle"]),
                    scheduleNotificationEnabled: boolValue(arguments["scheduleNotificationEnabled"]),
                    enabledSkills: self.agentSkillStore.enabledSkillPromptSummaries()
                )
                let promptTokenThreshold = persistenceState?.promptTokenThreshold ?? 128_000
                var latestPromptTokens: Int?
                var thinkingRound = 0
                let maxRounds = 6

                for _ in 0 ..< maxRounds {
                    try Task.checkCancellation()
                    thinkingRound += 1
                    eventSink("onAgentThinkingStart", basePayload)
                    let roundResult = try await self.requestAgentRound(
                        config: config,
                        messages: messages,
                        reasoningEffort: reasoningEffort,
                        toolDefinitions: Array(toolDefinitions.values)
                    )

                    if let reasoning = roundResult.reasoning, reasoning.isEmpty == false {
                        eventSink(
                            "onAgentThinkingUpdate",
                            basePayload.merging(
                                ["thinking": reasoning],
                                uniquingKeysWith: { _, new in new }
                            )
                        )
                        self.persistThinkingCard(
                            taskId: taskID,
                            round: thinkingRound,
                            thinking: reasoning,
                            stage: roundResult.toolCalls.isEmpty ? 4 : 2,
                            conversationId: conversationID,
                            conversationMode: conversationMode,
                            syncConversation: syncConversation
                        )
                    }

                    if let promptTokens = roundResult.promptTokens {
                        latestPromptTokens = promptTokens
                        if let persistenceState {
                            self.conversationArchiveStore.updatePromptTokenUsage(
                                conversationId: persistenceState.conversationId,
                                promptTokens: promptTokens,
                                threshold: persistenceState.promptTokenThreshold
                            )
                            syncConversation(persistenceState.conversationId, persistenceState.conversationMode)
                        }
                        eventSink(
                            "onAgentPromptTokenUsageChanged",
                            basePayload.merging(
                                [
                                    "latestPromptTokens": promptTokens,
                                    "promptTokenThreshold": promptTokenThreshold,
                                ],
                                uniquingKeysWith: { _, new in new }
                            )
                        )
                    }

                    if roundResult.toolCalls.isEmpty {
                        let finalText = roundResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard finalText.isEmpty == false else {
                            throw CoordinatorError.invalidResponse("模型没有返回可展示的回复。")
                        }

                        if let persistenceState {
                            self.conversationArchiveStore.upsertAssistantMessage(
                                conversationId: persistenceState.conversationId,
                                conversationMode: persistenceState.conversationMode,
                                entryId: persistenceState.assistantEntryId,
                                text: finalText
                            )
                            syncConversation(persistenceState.conversationId, persistenceState.conversationMode)
                        }

                        eventSink(
                            "onAgentChatMessage",
                            basePayload.merging(
                                ["message": finalText, "isFinal": true],
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
                                    "latestPromptTokens": latestPromptTokens ?? NSNull(),
                                    "promptTokenThreshold": promptTokenThreshold,
                                ],
                                uniquingKeysWith: { _, new in new }
                            )
                        )
                        return
                    }

                    messages.append(roundResult.assistantMessage)

                    for (index, toolCall) in roundResult.toolCalls.enumerated() {
                        try Task.checkCancellation()
                        let toolArguments = self.parseToolArguments(toolCall.argumentsJSON)
                        let toolTitle = self.extractToolTitle(from: toolArguments)
                        let cardId = self.toolCardId(
                            taskId: taskID,
                            toolCallId: toolCall.id,
                            fallbackIndex: index + 1
                        )

                        guard let definition = toolDefinitions[toolCall.name] else {
                            let execution = self.errorExecution(message: "未知工具：\(toolCall.name)")
                            let completePayload = self.buildToolCompletePayload(
                                basePayload: basePayload,
                                cardId: cardId,
                                definition: AgentToolDefinition(
                                    name: toolCall.name,
                                    displayName: toolCall.name,
                                    toolTitle: toolTitle ?? toolCall.name,
                                    toolType: "builtin",
                                    serverName: nil,
                                    description: "",
                                    parameters: [:],
                                    handler: { _ in execution }
                                ),
                                argumentsJSON: toolCall.argumentsJSON,
                                execution: execution
                            )
                            eventSink("onAgentToolCallComplete", completePayload)
                            self.persistToolCard(
                                payload: completePayload,
                                cardId: cardId,
                                conversationId: conversationID,
                                conversationMode: conversationMode,
                                syncConversation: syncConversation
                            )
                            messages.append(self.toolResultMessage(toolCallID: toolCall.id, execution: execution))
                            continue
                        }

                        let startPayload = self.buildToolStartPayload(
                            basePayload: basePayload,
                            cardId: cardId,
                            definition: definition,
                            argumentsJSON: toolCall.argumentsJSON,
                            toolTitle: toolTitle
                        )
                        eventSink("onAgentToolCallStart", startPayload)
                        self.persistToolCard(
                            payload: startPayload,
                            cardId: cardId,
                            conversationId: conversationID,
                            conversationMode: conversationMode,
                            syncConversation: syncConversation
                        )

                        let execution = try await self.executeTool(
                            definition: definition,
                            arguments: toolArguments,
                            cardId: cardId
                        )
                        let completePayload = self.buildToolCompletePayload(
                            basePayload: basePayload,
                            cardId: cardId,
                            definition: definition,
                            argumentsJSON: toolCall.argumentsJSON,
                            execution: execution
                        )
                        eventSink("onAgentToolCallComplete", completePayload)
                        self.persistToolCard(
                            payload: completePayload,
                            cardId: cardId,
                            conversationId: conversationID,
                            conversationMode: conversationMode,
                            syncConversation: syncConversation
                        )
                        messages.append(self.toolResultMessage(toolCallID: toolCall.id, execution: execution))
                    }
                }

                throw CoordinatorError.invalidResponse("Agent 超过最大工具轮次仍未产出最终回复。")
            } catch is CancellationError {
                return
            } catch {
                if let persistenceState {
                    self.conversationArchiveStore.upsertAssistantMessage(
                        conversationId: persistenceState.conversationId,
                        conversationMode: persistenceState.conversationMode,
                        entryId: persistenceState.assistantEntryId,
                        text: self.userFacingMessage(for: error),
                        isError: true
                    )
                    syncConversation(persistenceState.conversationId, persistenceState.conversationMode)
                }
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
            cancelToolTasks(forTaskId: taskId)
            return
        }

        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
        for toolTask in activeToolTasks.values {
            toolTask.cancel()
        }
        activeToolTasks.removeAll()
        requestedToolStops.removeAll()
    }

    func stopToolCall(taskId: String?, cardId: String?) {
        _ = taskId
        guard let cardId = cardId?.trimmingCharacters(in: .whitespacesAndNewlines),
              cardId.isEmpty == false else {
            return
        }
        requestedToolStops.insert(cardId)
        activeToolTasks[cardId]?.cancel()
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

    private func runTextOnlyFallback(
        taskId: String,
        basePayload: [String: Any],
        config: ModelProviderProfileStore.CompletionRequestConfig,
        promptMessages: [PromptMessage],
        reasoningEffort: String?,
        persistenceState: PersistenceState?,
        eventSink: @escaping (String, [String: Any]) -> Void,
        syncConversation: @escaping (Int, String) -> Void
    ) async throws {
        let completion = try await requestCompletion(
            config: config,
            promptMessages: promptMessages,
            reasoningEffort: reasoningEffort
        )

        if let reasoning = completion.reasoning {
            eventSink(
                "onAgentThinkingUpdate",
                basePayload.merging(["thinking": reasoning], uniquingKeysWith: { _, new in new })
            )
            persistThinkingCard(
                taskId: taskId,
                round: 1,
                thinking: reasoning,
                stage: 4,
                conversationId: persistenceState?.conversationId,
                conversationMode: persistenceState?.conversationMode,
                syncConversation: syncConversation
            )
        }

        if let promptTokens = completion.promptTokens {
            if let persistenceState {
                conversationArchiveStore.updatePromptTokenUsage(
                    conversationId: persistenceState.conversationId,
                    promptTokens: promptTokens,
                    threshold: persistenceState.promptTokenThreshold
                )
                syncConversation(persistenceState.conversationId, persistenceState.conversationMode)
            }
            eventSink(
                "onAgentPromptTokenUsageChanged",
                basePayload.merging(
                    [
                        "latestPromptTokens": promptTokens,
                        "promptTokenThreshold": persistenceState?.promptTokenThreshold ?? 128_000,
                    ],
                    uniquingKeysWith: { _, new in new }
                )
            )
        }

        if let persistenceState {
            conversationArchiveStore.upsertAssistantMessage(
                conversationId: persistenceState.conversationId,
                conversationMode: persistenceState.conversationMode,
                entryId: persistenceState.assistantEntryId,
                text: completion.text
            )
            syncConversation(persistenceState.conversationId, persistenceState.conversationMode)
        }

        eventSink(
            "onAgentChatMessage",
            basePayload.merging(["message": completion.text, "isFinal": true], uniquingKeysWith: { _, new in new })
        )
        eventSink(
            "onAgentComplete",
            basePayload.merging(
                [
                    "success": true,
                    "outputKind": "chat",
                    "hasUserVisibleOutput": true,
                    "latestPromptTokens": completion.promptTokens ?? NSNull(),
                    "promptTokenThreshold": persistenceState?.promptTokenThreshold ?? 128_000,
                ],
                uniquingKeysWith: { _, new in new }
            )
        )
    }

    private func makePersistenceState(
        taskId: String,
        userMessage: String,
        attachments: [[String: Any]],
        conversationId: Int?,
        conversationMode: String,
        userMessageCreatedAtMillis: Int?,
        syncConversation: @escaping (Int, String) -> Void
    ) -> PersistenceState? {
        guard let conversationId, conversationId > 0 else {
            return nil
        }

        let userEntryId = "\(taskId)-user"
        conversationArchiveStore.upsertUserMessage(
            conversationId: conversationId,
            conversationMode: conversationMode,
            entryId: userEntryId,
            text: userMessage,
            attachments: attachments,
            createdAtMillis: userMessageCreatedAtMillis
        )
        syncConversation(conversationId, conversationMode)
        return PersistenceState(
            conversationId: conversationId,
            conversationMode: conversationMode,
            userEntryId: userEntryId,
            assistantEntryId: "\(taskId)-text",
            promptTokenThreshold: currentPromptTokenThreshold(conversationId: conversationId),
            userMessageCreatedAtMillis: userMessageCreatedAtMillis
        )
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

    private func requestAgentRound(
        config: ModelProviderProfileStore.CompletionRequestConfig,
        messages: [[String: Any]],
        reasoningEffort: String?,
        toolDefinitions: [AgentToolDefinition]
    ) async throws -> AgentRoundResult {
        guard config.apiBase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw CoordinatorError.providerUnavailable
        }

        var request = URLRequest(url: try completionRequestURL(for: config))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if config.apiKey.isEmpty == false {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "model": config.modelId,
            "messages": messages,
            "stream": false,
        ]
        if let reasoningEffort {
            body["reasoning_effort"] = reasoningEffort
        }
        if toolDefinitions.isEmpty == false {
            body["tools"] = toolDefinitions.map(toolPayload)
            body["tool_choice"] = "auto"
        }
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
        return try parseAgentRoundResponse(data)
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
           last.text.trimmingCharacters(in: .whitespacesAndNewlines) == userMessage.trimmingCharacters(in: .whitespacesAndNewlines) {
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

            let attachments = dictionaryArrayValue(content["attachments"])
            return PromptMessage(role: role, text: text, attachments: attachments)
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

    private func buildAgentRequestMessages(
        promptMessages: [PromptMessage],
        conversationId: Int?,
        conversationMode: String,
        scheduledTaskId: String?,
        scheduledTaskTitle: String?,
        scheduleNotificationEnabled: Bool?,
        enabledSkills: [String]
    ) -> [[String: Any]] {
        var messages = [[String: Any]]()
        messages.append([
            "role": "system",
            "content": buildSystemPrompt(
                conversationId: conversationId,
                conversationMode: conversationMode,
                scheduledTaskId: scheduledTaskId,
                scheduledTaskTitle: scheduledTaskTitle,
                scheduleNotificationEnabled: scheduleNotificationEnabled,
                enabledSkills: enabledSkills
            ),
        ])
        messages.append(contentsOf: promptMessages.map { promptMessage in
            [
                "role": promptMessage.role,
                "content": openAIContent(for: promptMessage),
            ]
        })
        return messages
    }

    private func buildSystemPrompt(
        conversationId: Int?,
        conversationMode: String,
        scheduledTaskId: String?,
        scheduledTaskTitle: String?,
        scheduleNotificationEnabled: Bool?,
        enabledSkills: [String]
    ) -> String {
        let promptContext = memoryStore.promptContext()
        let normalizedSkills = enabledSkills.prefix(8).joined(separator: "\n- ")
        let conversationSummary = conversationId.flatMap { id in
            conversationArchiveStore
                .listConversationPayloads()
                .first(where: { integerValue($0["id"]) == id })
        }.flatMap { payload in
            normalizedOptionalString(payload["contextSummary"])
        } ?? ""

        let sections: [String] = [
            """
            你是 Omnibot 的 iOS 智能代理。优先给出准确、可执行、简洁的帮助。
            Flutter 聊天页是用户看到的唯一真相源；你的工具结果必须清晰、稳定，避免虚构能力。
            当前 iOS 版本只提供 iOS 可落地能力：workspace 文件、嵌入式 terminal、workspace memory、skills、remote MCP、scheduled tasks、只读 browser snapshot、以及轻量 subagent 分派。
            Android 专属能力（overlay、accessibility、外部 App 自动化、APK 安装、本地 MCP server、Home 键）都不可用，不要伪造执行成功。
            每次调用工具都必须提供 `tool_title`，用和用户相同的语言写一个简短标题。
            调用工具后先等待工具结果，再决定下一步；不要假设工具一定成功。
            默认使用简体中文回答，除非用户明确使用其他语言。
            """,
            promptContext.soul.isEmpty ? "" : "SOUL\n\(trimmedContext(promptContext.soul, limit: 1200))",
            promptContext.chatPrompt.isEmpty ? "" : "CHAT\n\(trimmedContext(promptContext.chatPrompt, limit: 1200))",
            promptContext.longMemory.isEmpty ? "" : "LONG MEMORY\n\(trimmedContext(promptContext.longMemory, limit: 1600))",
            promptContext.recentShortMemory.isEmpty ? "" : "RECENT SHORT MEMORY\n\(trimmedContext(promptContext.recentShortMemory, limit: 1200))",
            conversationSummary.isEmpty ? "" : "COMPACTED CONTEXT SUMMARY\n\(trimmedContext(conversationSummary, limit: 1200))",
            normalizedSkills.isEmpty ? "" : "ENABLED SKILLS\n- \(normalizedSkills)",
            scheduledTaskId == nil ? "" : """
            SCHEDULE CONTEXT
            - scheduledTaskId: \(scheduledTaskId ?? "")
            - scheduledTaskTitle: \(scheduledTaskTitle ?? "")
            - notificationsEnabled: \(scheduleNotificationEnabled == true ? "true" : "false")
            """,
            "WORKSPACE ROOT\n- shell path: /workspace\n- internal path: /workspace/.omnibot",
            "CONVERSATION MODE\n- \(conversationMode)",
        ]

        return sections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: "\n\n")
    }

    private func buildToolCatalog(
        terminalEnvironment: [String: String]
    ) async -> [String: AgentToolDefinition] {
        var catalog = [String: AgentToolDefinition]()

        func register(_ definition: AgentToolDefinition) {
            catalog[definition.name] = definition
        }

        register(makeTerminalExecuteTool(environment: terminalEnvironment))
        register(makeTerminalSessionStartTool())
        register(makeTerminalSessionExecTool())
        register(makeTerminalSessionReadTool())
        register(makeTerminalSessionStopTool())
        register(makeFileReadTool())
        register(makeFileWriteTool())
        register(makeFileEditTool())
        register(makeFileListTool())
        register(makeFileSearchTool())
        register(makeFileStatTool())
        register(makeFileMoveTool())
        register(makeSkillsListTool())
        register(makeSkillsReadTool())
        register(makeScheduleTaskCreateTool())
        register(makeScheduleTaskListTool())
        register(makeScheduleTaskUpdateTool())
        register(makeScheduleTaskDeleteTool())
        register(makeMemorySearchTool())
        register(makeMemoryWriteDailyTool())
        register(makeMemoryUpsertLongTermTool())
        register(makeMemoryRollupTool())
        register(makeBrowserSnapshotTool())
        register(makeSubagentDispatchTool())

        for remoteTool in await remoteMcpStore.discoverEnabledTools(forceRefresh: false) {
            register(
                AgentToolDefinition(
                    name: remoteTool.encodedToolName,
                    displayName: remoteTool.toolName,
                    toolTitle: remoteTool.toolName,
                    toolType: "mcp",
                    serverName: remoteTool.serverName,
                    description: remoteTool.description,
                    parameters: decorateToolParameters(
                        baseProperties: remoteTool.inputSchema,
                        required: []
                    )
                ) { [remoteMcpStore] arguments in
                    let result = try await remoteMcpStore.callEncodedTool(remoteTool.encodedToolName, arguments: arguments)
                    return AgentToolExecution(
                        status: result.success ? "success" : "error",
                        summary: result.summaryText,
                        progress: "",
                        resultPreviewJSON: result.previewJSON,
                        rawResultJSON: result.rawResultJSON,
                        terminalOutput: "",
                        terminalOutputDelta: "",
                        terminalSessionId: nil,
                        terminalStreamState: "",
                        workspaceId: nil,
                        interruptedBy: nil,
                        interruptionReason: nil,
                        artifacts: [],
                        actions: [],
                        success: result.success
                    )
                }
            )
        }

        return catalog
    }

    private func makeTerminalExecuteTool(environment: [String: String]) -> AgentToolDefinition {
        AgentToolDefinition(
            name: "terminal_execute",
            displayName: "Run Terminal Command",
            toolTitle: "终端执行",
            toolType: "terminal",
            serverName: nil,
            description: "Run a shell command inside the iOS embedded workspace runtime.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "command": schemaString("要执行的命令。"),
                    "working_directory": schemaString("可选工作目录，默认 /workspace。"),
                    "timeout_seconds": schemaInteger("超时时间，默认 30 秒。"),
                ],
                required: ["command"]
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let command = try self.normalizedRequiredString(arguments["command"], name: "command")
            let workingDirectory = self.normalizedOptionalString(arguments["working_directory"]) ?? "/workspace"
            let timeoutSeconds = Int64(max(1, min(self.integerValue(arguments["timeout_seconds"]) ?? 30, 300)))
            let environmentPayload = environment.reduce(into: [String?: String?]()) { partialResult, entry in
                partialResult[entry.key] = entry.value
            }
            let result = TerminalRuntimeCoordinator.shared.exec(
                request: TerminalCommandRequestMessage(
                    command: command,
                    workingDirectory: workingDirectory,
                    timeoutSeconds: timeoutSeconds,
                    environment: environmentPayload
                )
            )
            let rawResult: [String: Any] = [
                "success": result.success,
                "timedOut": result.timedOut,
                "exitCode": result.exitCode ?? NSNull(),
                "output": result.output,
                "errorMessage": result.errorMessage ?? NSNull(),
                "sessionId": result.sessionId,
                "transcript": result.transcript,
                "currentDirectory": result.currentDirectory,
                "executionState": String(describing: result.executionState),
            ]
            let summary: String
            if result.success {
                summary = normalizedOptionalString(arguments["tool_title"]) ?? "命令执行完成"
            } else {
                summary = result.errorMessage ?? "命令执行失败"
            }
            return AgentToolExecution(
                status: result.success ? "success" : (result.timedOut ? "interrupted" : "error"),
                summary: summary,
                progress: "",
                resultPreviewJSON: previewJSONString(from: rawResult),
                rawResultJSON: jsonString(from: rawResult),
                terminalOutput: result.transcript,
                terminalOutputDelta: result.output,
                terminalSessionId: result.sessionId,
                terminalStreamState: result.completed ? "completed" : "running",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: result.success
            )
        }
    }

    private func makeTerminalSessionStartTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "terminal_session_start",
            displayName: "Start Terminal Session",
            toolTitle: "启动终端会话",
            toolType: "terminal",
            serverName: nil,
            description: "Open a persistent terminal session.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "working_directory": schemaString("可选工作目录，默认 /workspace。"),
                ],
                required: []
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let snapshot = TerminalRuntimeCoordinator.shared.openSession(
                workingDirectory: self.normalizedOptionalString(arguments["working_directory"])
            )
            let payload: [String: Any] = [
                "sessionId": snapshot.sessionId,
                "currentDirectory": snapshot.currentDirectory,
                "transcript": snapshot.transcript,
                "commandRunning": snapshot.commandRunning,
            ]
            return AgentToolExecution(
                status: "success",
                summary: "终端会话已创建",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: snapshot.transcript,
                terminalOutputDelta: "",
                terminalSessionId: snapshot.sessionId,
                terminalStreamState: snapshot.commandRunning ? "running" : "idle",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: true
            )
        }
    }

    private func makeTerminalSessionExecTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "terminal_session_exec",
            displayName: "Run Session Command",
            toolTitle: "执行会话命令",
            toolType: "terminal",
            serverName: nil,
            description: "Append input to an existing terminal session.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "session_id": schemaString("终端会话 ID。"),
                    "text": schemaString("写入会话 stdin 的文本。"),
                ],
                required: ["session_id", "text"]
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let sessionId = try self.normalizedRequiredString(arguments["session_id"], name: "session_id")
            let text = try self.normalizedRequiredString(arguments["text"], name: "text")
            let snapshot = TerminalRuntimeCoordinator.shared.writeStdin(sessionId: sessionId, text: text)
            let payload: [String: Any] = [
                "sessionId": snapshot.sessionId,
                "currentDirectory": snapshot.currentDirectory,
                "transcript": snapshot.transcript,
                "commandRunning": snapshot.commandRunning,
            ]
            return AgentToolExecution(
                status: "success",
                summary: "已写入终端会话",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: snapshot.transcript,
                terminalOutputDelta: text,
                terminalSessionId: snapshot.sessionId,
                terminalStreamState: snapshot.commandRunning ? "running" : "idle",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: true
            )
        }
    }

    private func makeTerminalSessionReadTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "terminal_session_read",
            displayName: "Read Session Output",
            toolTitle: "读取会话输出",
            toolType: "terminal",
            serverName: nil,
            description: "Read a persistent terminal session transcript.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "session_id": schemaString("终端会话 ID。"),
                ],
                required: ["session_id"]
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let sessionId = try self.normalizedRequiredString(arguments["session_id"], name: "session_id")
            let snapshot = TerminalRuntimeCoordinator.shared.readSession(sessionId: sessionId)
            let payload: [String: Any] = [
                "sessionId": snapshot.sessionId,
                "currentDirectory": snapshot.currentDirectory,
                "transcript": snapshot.transcript,
                "commandRunning": snapshot.commandRunning,
            ]
            return AgentToolExecution(
                status: "success",
                summary: "已读取终端会话",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: snapshot.transcript,
                terminalOutputDelta: "",
                terminalSessionId: snapshot.sessionId,
                terminalStreamState: snapshot.commandRunning ? "running" : "idle",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: true
            )
        }
    }

    private func makeTerminalSessionStopTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "terminal_session_stop",
            displayName: "Stop Terminal Session",
            toolTitle: "结束终端会话",
            toolType: "terminal",
            serverName: nil,
            description: "Close a terminal session.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "session_id": schemaString("终端会话 ID。"),
                ],
                required: ["session_id"]
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let sessionId = try self.normalizedRequiredString(arguments["session_id"], name: "session_id")
            TerminalRuntimeCoordinator.shared.closeSession(sessionId: sessionId)
            let payload: [String: Any] = ["sessionId": sessionId, "closed": true]
            return AgentToolExecution(
                status: "success",
                summary: "终端会话已结束",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: sessionId,
                terminalStreamState: "closed",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: true
            )
        }
    }

    private func makeFileReadTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "file_read",
            displayName: "Read File",
            toolTitle: "读取文件",
            toolType: "workspace",
            serverName: nil,
            description: "Read a file inside the iOS workspace.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "path": schemaString("文件路径，支持 /workspace 或 omnibot:// 前缀。"),
                    "maxChars": schemaInteger("最多读取字符数，默认 8000。"),
                    "offset": schemaInteger("字符偏移。"),
                    "lineStart": schemaInteger("从第几行开始，1-based。"),
                    "lineCount": schemaInteger("读取多少行。"),
                ],
                required: ["path"]
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let payload = try self.fileReadPayload(arguments)
            return AgentToolExecution(
                status: "success",
                summary: "已读取文件",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: nil,
                terminalStreamState: "",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: true
            )
        }
    }

    private func makeFileWriteTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "file_write",
            displayName: "Write File",
            toolTitle: "写入文件",
            toolType: "workspace",
            serverName: nil,
            description: "Create or overwrite a file inside the iOS workspace.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "path": schemaString("目标文件路径。"),
                    "content": schemaString("要写入的文本内容。"),
                    "append": schemaBoolean("是否追加写入。"),
                ],
                required: ["path", "content"]
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let payload = try self.fileWritePayload(arguments)
            return AgentToolExecution(
                status: "success",
                summary: "文件已写入",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: nil,
                terminalStreamState: "",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [self.fileArtifact(from: payload)],
                actions: [],
                success: true
            )
        }
    }

    private func makeFileEditTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "file_edit",
            displayName: "Edit File",
            toolTitle: "编辑文件",
            toolType: "workspace",
            serverName: nil,
            description: "Replace text in an existing file.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "path": schemaString("目标文件路径。"),
                    "oldText": schemaString("要替换的原始文本。"),
                    "newText": schemaString("替换后的文本。"),
                    "replaceAll": schemaBoolean("是否替换全部匹配。"),
                ],
                required: ["path", "oldText", "newText"]
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let payload = try self.fileEditPayload(arguments)
            return AgentToolExecution(
                status: "success",
                summary: "文件已更新",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: nil,
                terminalStreamState: "",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [self.fileArtifact(from: payload)],
                actions: [],
                success: true
            )
        }
    }

    private func makeFileListTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "file_list",
            displayName: "List Files",
            toolTitle: "列出文件",
            toolType: "workspace",
            serverName: nil,
            description: "List files inside the iOS workspace.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "path": schemaString("目录路径，默认 /workspace。"),
                    "recursive": schemaBoolean("是否递归。"),
                    "maxDepth": schemaInteger("递归最大深度，默认 2。"),
                    "limit": schemaInteger("返回条数上限，默认 200。"),
                ],
                required: []
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let payload = try self.fileListPayload(arguments)
            return AgentToolExecution(
                status: "success",
                summary: "已列出文件",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: nil,
                terminalStreamState: "",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: true
            )
        }
    }

    private func makeFileSearchTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "file_search",
            displayName: "Search Files",
            toolTitle: "搜索文件",
            toolType: "workspace",
            serverName: nil,
            description: "Search file names and text content inside the iOS workspace.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "path": schemaString("搜索根目录，默认 /workspace。"),
                    "query": schemaString("搜索关键词。"),
                    "caseSensitive": schemaBoolean("是否区分大小写。"),
                    "maxResults": schemaInteger("最多返回多少结果，默认 50。"),
                ],
                required: ["query"]
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let payload = try self.fileSearchPayload(arguments)
            return AgentToolExecution(
                status: "success",
                summary: "已完成文件搜索",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: nil,
                terminalStreamState: "",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: true
            )
        }
    }

    private func makeFileStatTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "file_stat",
            displayName: "Inspect File",
            toolTitle: "查看文件信息",
            toolType: "workspace",
            serverName: nil,
            description: "Inspect file metadata.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "path": schemaString("目标路径。"),
                ],
                required: ["path"]
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let payload = try self.fileStatPayload(arguments)
            return AgentToolExecution(
                status: "success",
                summary: "已查看文件信息",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: nil,
                terminalStreamState: "",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: true
            )
        }
    }

    private func makeFileMoveTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "file_move",
            displayName: "Move File",
            toolTitle: "移动文件",
            toolType: "workspace",
            serverName: nil,
            description: "Move or rename a file inside the iOS workspace.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "sourcePath": schemaString("源路径。"),
                    "targetPath": schemaString("目标路径。"),
                    "overwrite": schemaBoolean("是否覆盖目标文件。"),
                ],
                required: ["sourcePath", "targetPath"]
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let payload = try self.fileMovePayload(arguments)
            return AgentToolExecution(
                status: "success",
                summary: "文件已移动",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: nil,
                terminalStreamState: "",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [self.fileArtifact(from: payload)],
                actions: [],
                success: true
            )
        }
    }

    private func makeSkillsListTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "skills_list",
            displayName: "List Skills",
            toolTitle: "列出 Skills",
            toolType: "skill",
            serverName: nil,
            description: "List current skills on iOS.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "query": schemaString("可选关键词。"),
                    "limit": schemaInteger("返回数量上限。"),
                ],
                required: []
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let payload = self.skillsListPayload(arguments)
            return AgentToolExecution(
                status: "success",
                summary: "已列出 Skills",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: nil,
                terminalStreamState: "",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: true
            )
        }
    }

    private func makeSkillsReadTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "skills_read",
            displayName: "Read Skill",
            toolTitle: "读取 Skill",
            toolType: "skill",
            serverName: nil,
            description: "Read an installed skill manifest and SKILL.md.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "skillId": schemaString("skill 的 id、名称或路径。"),
                    "maxChars": schemaInteger("最多返回多少字符。"),
                ],
                required: ["skillId"]
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let payload = try self.skillsReadPayload(arguments)
            return AgentToolExecution(
                status: "success",
                summary: "已读取 Skill",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: nil,
                terminalStreamState: "",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: true
            )
        }
    }

    private func makeScheduleTaskCreateTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "schedule_task_create",
            displayName: "Create Scheduled Task",
            toolTitle: "创建定时任务",
            toolType: "schedule",
            serverName: nil,
            description: "Create a workspace scheduled task.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "title": schemaString("任务标题。"),
                    "targetKind": schemaEnum(["vlm", "subagent"], description: "目标类型。"),
                    "goal": schemaString("vlm 任务目标。"),
                    "packageName": schemaString("可选包名。"),
                    "subagentConversationId": schemaString("subagent 线程 ID。"),
                    "subagentPrompt": schemaString("subagent 提示词。"),
                    "notificationEnabled": schemaBoolean("是否启用通知。"),
                    "scheduleType": schemaEnum(["fixed_time", "countdown"], description: "调度类型。"),
                    "fixedTime": schemaString("固定时间，例如 09:30。"),
                    "countdownMinutes": schemaInteger("倒计时分钟数。"),
                    "repeatDaily": schemaBoolean("是否每日重复。"),
                    "enabled": schemaBoolean("是否启用。"),
                ],
                required: ["title", "targetKind", "scheduleType", "repeatDaily"]
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let payload = try self.scheduleCreatePayload(arguments)
            return AgentToolExecution(
                status: payload["success"] as? Bool == true ? "success" : "error",
                summary: (payload["summary"] as? String) ?? "定时任务创建完成",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: nil,
                terminalStreamState: "",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: payload["success"] as? Bool == true
            )
        }
    }

    private func makeScheduleTaskListTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "schedule_task_list",
            displayName: "List Scheduled Tasks",
            toolTitle: "查看定时任务",
            toolType: "schedule",
            serverName: nil,
            description: "List workspace scheduled tasks.",
            parameters: decorateToolParameters(baseProperties: [:], required: [])
        ) { [weak self] _ in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let payload = self.scheduleListPayload()
            return AgentToolExecution(
                status: "success",
                summary: "已列出定时任务",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: nil,
                terminalStreamState: "",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: true
            )
        }
    }

    private func makeScheduleTaskUpdateTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "schedule_task_update",
            displayName: "Update Scheduled Task",
            toolTitle: "修改定时任务",
            toolType: "schedule",
            serverName: nil,
            description: "Update a workspace scheduled task.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "taskId": schemaString("任务 ID。"),
                    "title": schemaString("任务标题。"),
                    "targetKind": schemaEnum(["vlm", "subagent"], description: "目标类型。"),
                    "fixedTime": schemaString("固定时间。"),
                    "countdownMinutes": schemaInteger("倒计时分钟数。"),
                    "repeatDaily": schemaBoolean("是否每日重复。"),
                    "enabled": schemaBoolean("是否启用。"),
                    "subagentConversationId": schemaString("subagent 线程 ID。"),
                    "subagentPrompt": schemaString("subagent 提示词。"),
                    "notificationEnabled": schemaBoolean("是否启用通知。"),
                ],
                required: ["taskId"]
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let payload = try self.scheduleUpdatePayload(arguments)
            return AgentToolExecution(
                status: payload["success"] as? Bool == true ? "success" : "error",
                summary: (payload["summary"] as? String) ?? "定时任务更新完成",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: nil,
                terminalStreamState: "",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: payload["success"] as? Bool == true
            )
        }
    }

    private func makeScheduleTaskDeleteTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "schedule_task_delete",
            displayName: "Delete Scheduled Task",
            toolTitle: "删除定时任务",
            toolType: "schedule",
            serverName: nil,
            description: "Delete a workspace scheduled task.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "taskId": schemaString("任务 ID。"),
                ],
                required: ["taskId"]
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let payload = try self.scheduleDeletePayload(arguments)
            return AgentToolExecution(
                status: payload["success"] as? Bool == true ? "success" : "error",
                summary: (payload["summary"] as? String) ?? "定时任务删除完成",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: nil,
                terminalStreamState: "",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: payload["success"] as? Bool == true
            )
        }
    }

    private func makeMemorySearchTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "memory_search",
            displayName: "Search Memory",
            toolTitle: "检索记忆",
            toolType: "memory",
            serverName: nil,
            description: "Search workspace memory.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "query": schemaString("检索语句。"),
                    "limit": schemaInteger("返回条数上限。"),
                ],
                required: ["query"]
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let payload = self.memorySearchPayload(arguments)
            return AgentToolExecution(
                status: "success",
                summary: "已检索记忆",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: nil,
                terminalStreamState: "",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: true
            )
        }
    }

    private func makeMemoryWriteDailyTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "memory_write_daily",
            displayName: "Write Daily Memory",
            toolTitle: "写入当日记忆",
            toolType: "memory",
            serverName: nil,
            description: "Append a short memory entry.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "text": schemaString("短期记忆文本。"),
                ],
                required: ["text"]
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let payload = try self.memoryWriteDailyPayload(arguments)
            return AgentToolExecution(
                status: payload["success"] as? Bool == true ? "success" : "error",
                summary: (payload["summary"] as? String) ?? "已写入短期记忆",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: nil,
                terminalStreamState: "",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: payload["success"] as? Bool == true
            )
        }
    }

    private func makeMemoryUpsertLongTermTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "memory_upsert_longterm",
            displayName: "Upsert Long-Term Memory",
            toolTitle: "沉淀长期记忆",
            toolType: "memory",
            serverName: nil,
            description: "Append stable facts to long-term memory with deduplication.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "text": schemaString("要沉淀的长期记忆内容。"),
                ],
                required: ["text"]
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let payload = try self.memoryUpsertLongTermPayload(arguments)
            return AgentToolExecution(
                status: payload["success"] as? Bool == true ? "success" : "error",
                summary: (payload["summary"] as? String) ?? "长期记忆已更新",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: nil,
                terminalStreamState: "",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: payload["success"] as? Bool == true
            )
        }
    }

    private func makeMemoryRollupTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "memory_rollup_day",
            displayName: "Roll Up Daily Memory",
            toolTitle: "整理当日记忆",
            toolType: "memory",
            serverName: nil,
            description: "Roll up short memories into long-term memory.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "date": schemaString("可选日期；当前 iOS 实现仅支持今天。"),
                ],
                required: []
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let payload = try self.memoryRollupPayload(arguments)
            return AgentToolExecution(
                status: payload["success"] as? Bool == true ? "success" : "error",
                summary: (payload["summary"] as? String) ?? "记忆整理完成",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: nil,
                terminalStreamState: "",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: payload["success"] as? Bool == true
            )
        }
    }

    private func makeBrowserSnapshotTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "browser_snapshot",
            displayName: "Browser Snapshot",
            toolTitle: "浏览器快照",
            toolType: "browser",
            serverName: nil,
            description: "Read the current in-app browser snapshot. iOS only supports read-only inspection.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "workspaceId": schemaString("可选 workspaceId。"),
                ],
                required: []
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let payload = try self.browserSnapshotPayload(arguments)
            let available = payload["available"] as? Bool == true
            return AgentToolExecution(
                status: available ? "success" : "error",
                summary: available ? "已读取浏览器快照" : "当前没有可用的浏览器快照",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: nil,
                terminalStreamState: "",
                workspaceId: normalizedOptionalString(payload["workspaceId"]),
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: available
            )
        }
    }

    private func makeSubagentDispatchTool() -> AgentToolDefinition {
        AgentToolDefinition(
            name: "subagent_dispatch",
            displayName: "Dispatch Subtasks",
            toolTitle: "分派子任务",
            toolType: "subagent",
            serverName: nil,
            description: "Run small subtasks sequentially as lightweight iOS subagents and return aggregated results.",
            parameters: decorateToolParameters(
                baseProperties: [
                    "tasks": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "需要执行的子任务列表。",
                    ],
                    "concurrency": schemaInteger("并发度，当前 iOS 会顺序执行并忽略该值。"),
                    "mergeInstruction": schemaString("结果聚合要求。"),
                ],
                required: ["tasks"]
            )
        ) { [weak self] arguments in
            guard let self else { throw CoordinatorError.invalidArguments("Coordinator unavailable") }
            let payload = try await self.subagentDispatchPayload(arguments)
            return AgentToolExecution(
                status: payload["success"] as? Bool == true ? "success" : "error",
                summary: (payload["summary"] as? String) ?? "Subagent 执行完成",
                progress: "",
                resultPreviewJSON: previewJSONString(from: payload),
                rawResultJSON: jsonString(from: payload),
                terminalOutput: "",
                terminalOutputDelta: "",
                terminalSessionId: nil,
                terminalStreamState: "",
                workspaceId: nil,
                interruptedBy: nil,
                interruptionReason: nil,
                artifacts: [],
                actions: [],
                success: payload["success"] as? Bool == true
            )
        }
    }

    private func executeTool(
        definition: AgentToolDefinition,
        arguments: [String: Any],
        cardId: String
    ) async throws -> AgentToolExecution {
        if requestedToolStops.remove(cardId) != nil {
            return interruptedExecution(cardId: cardId)
        }

        let task = Task { try await definition.handler(arguments) }
        activeToolTasks[cardId] = task
        defer {
            activeToolTasks.removeValue(forKey: cardId)
            requestedToolStops.remove(cardId)
        }

        do {
            let execution = try await task.value
            if requestedToolStops.remove(cardId) != nil {
                return interruptedExecution(cardId: cardId, previous: execution)
            }
            return execution
        } catch is CancellationError {
            return interruptedExecution(cardId: cardId)
        } catch {
            return errorExecution(message: userFacingMessage(for: error))
        }
    }

    private func toolPayload(_ definition: AgentToolDefinition) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": definition.name,
                "description": definition.description,
                "parameters": definition.parameters,
            ],
        ]
    }

    private func buildToolStartPayload(
        basePayload: [String: Any],
        cardId: String,
        definition: AgentToolDefinition,
        argumentsJSON: String,
        toolTitle: String?
    ) -> [String: Any] {
        var payload = basePayload
        payload["cardId"] = cardId
        payload["toolName"] = definition.name
        payload["displayName"] = definition.displayName
        payload["toolTitle"] = toolTitle ?? ""
        payload["toolType"] = definition.toolType
        if let serverName = definition.serverName {
            payload["serverName"] = serverName
        }
        payload["status"] = "running"
        payload["args"] = argumentsJSON
        payload["argsJson"] = argumentsJSON
        payload["summary"] = toolTitle ?? definition.toolTitle
        payload["progress"] = ""
        return payload
    }

    private func buildToolCompletePayload(
        basePayload: [String: Any],
        cardId: String,
        definition: AgentToolDefinition,
        argumentsJSON: String,
        execution: AgentToolExecution
    ) -> [String: Any] {
        var payload = basePayload
        payload["cardId"] = cardId
        payload["toolName"] = definition.name
        payload["displayName"] = definition.displayName
        payload["toolTitle"] = extractToolTitle(fromJSON: argumentsJSON) ?? ""
        payload["toolType"] = definition.toolType
        if let serverName = definition.serverName {
            payload["serverName"] = serverName
        }
        payload["status"] = execution.status
        payload["summary"] = execution.summary
        payload["progress"] = execution.progress
        payload["args"] = argumentsJSON
        payload["argsJson"] = argumentsJSON
        payload["resultPreviewJson"] = execution.resultPreviewJSON
        payload["rawResultJson"] = execution.rawResultJSON
        payload["terminalOutput"] = execution.terminalOutput
        payload["terminalOutputDelta"] = execution.terminalOutputDelta
        payload["terminalSessionId"] = execution.terminalSessionId
        payload["terminalStreamState"] = execution.terminalStreamState
        payload["success"] = execution.success
        if let workspaceId = execution.workspaceId {
            payload["workspaceId"] = workspaceId
        }
        if let interruptedBy = execution.interruptedBy {
            payload["interruptedBy"] = interruptedBy
        }
        if let interruptionReason = execution.interruptionReason {
            payload["interruptionReason"] = interruptionReason
        }
        if execution.artifacts.isEmpty == false {
            payload["artifacts"] = execution.artifacts
        }
        if execution.actions.isEmpty == false {
            payload["actions"] = execution.actions
        }
        return payload
    }

    private func toolResultMessage(toolCallID: String, execution: AgentToolExecution) -> [String: Any] {
        [
            "role": "tool",
            "tool_call_id": toolCallID,
            "content": execution.rawResultJSON.isEmpty ? execution.summary : execution.rawResultJSON,
        ]
    }

    private func persistToolCard(
        payload: [String: Any],
        cardId: String,
        conversationId: Int?,
        conversationMode: String?,
        syncConversation: @escaping (Int, String) -> Void
    ) {
        guard let conversationId, conversationId > 0 else { return }
        let mode = normalizeConversationMode(conversationMode)
        let toolType = normalizedOptionalString(payload["toolType"]) ?? "builtin"
        let cardData: [String: Any] = [
            "type": "agent_tool_summary",
            "taskId": normalizedOptionalString(payload["taskId"]) ?? "",
            "toolName": normalizedOptionalString(payload["toolName"]) ?? "",
            "displayName": normalizedOptionalString(payload["displayName"]) ?? "",
            "toolTitle": normalizedOptionalString(payload["toolTitle"]) ?? "",
            "cardId": cardId,
            "toolType": toolType,
            "serverName": payload["serverName"] ?? NSNull(),
            "status": normalizedOptionalString(payload["status"]) ?? "running",
            "summary": normalizedOptionalString(payload["summary"]) ?? "",
            "progress": normalizedOptionalString(payload["progress"]) ?? "",
            "argsJson": normalizedOptionalString(payload["argsJson"]) ?? "",
            "resultPreviewJson": normalizedOptionalString(payload["resultPreviewJson"]) ?? "",
            "rawResultJson": normalizedOptionalString(payload["rawResultJson"]) ?? "",
            "terminalOutput": normalizedOptionalString(payload["terminalOutput"]) ?? "",
            "terminalOutputDelta": normalizedOptionalString(payload["terminalOutputDelta"]) ?? "",
            "terminalSessionId": payload["terminalSessionId"] ?? NSNull(),
            "terminalStreamState": normalizedOptionalString(payload["terminalStreamState"]) ?? "",
            "workspaceId": payload["workspaceId"] ?? NSNull(),
            "interruptedBy": payload["interruptedBy"] ?? NSNull(),
            "interruptionReason": payload["interruptionReason"] ?? NSNull(),
            "artifacts": dictionaryArrayValue(payload["artifacts"]),
            "actions": dictionaryArrayValue(payload["actions"]),
            "success": boolValue(payload["success"]) ?? false,
            "showTerminalOutput": toolType == "terminal",
            "showRawResult": normalizedOptionalString(payload["rawResultJson"])?.isEmpty == false,
            "showArtifactAction": dictionaryArrayValue(payload["artifacts"]).isEmpty == false,
            "showScheduleAction": toolType == "schedule",
            "showAlarmAction": false,
        ]
        conversationArchiveStore.upsertConversationUiCard(
            conversationId: conversationId,
            mode: mode,
            entryId: cardId,
            cardData: cardData,
            createdAt: timestampMillis()
        )
        syncConversation(conversationId, mode)
    }

    private func persistThinkingCard(
        taskId: String,
        round: Int,
        thinking: String,
        stage: Int,
        conversationId: Int?,
        conversationMode: String?,
        syncConversation: @escaping (Int, String) -> Void
    ) {
        guard let conversationId, conversationId > 0 else { return }
        let mode = normalizeConversationMode(conversationMode)
        let cardId = round <= 1 ? "\(taskId)-thinking" : "\(taskId)-thinking-\(round)"
        let cardData: [String: Any] = [
            "type": "deep_thinking",
            "isLoading": stage != 4,
            "thinkingContent": thinking,
            "stage": stage,
            "taskID": taskId,
            "startTime": timestampMillis(),
            "endTime": stage == 4 ? timestampMillis() : NSNull(),
        ]
        conversationArchiveStore.upsertConversationUiCard(
            conversationId: conversationId,
            mode: mode,
            entryId: cardId,
            cardData: cardData,
            createdAt: timestampMillis()
        )
        syncConversation(conversationId, mode)
    }

    private func parseAgentRoundResponse(_ data: Data) throws -> AgentRoundResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CoordinatorError.invalidResponse("模型返回内容无法解析。")
        }

        let promptTokens = integerValue(dictionaryValue(object["usage"])?["prompt_tokens"])
        let reasoning = parseReasoning(from: object)

        if let choices = object["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = dictionaryValue(firstChoice["message"]) {
            let text = parseOpenAIMessageContent(message["content"]) ?? ""
            let toolCalls = parseToolCalls(message["tool_calls"])
            return AgentRoundResult(
                text: text,
                reasoning: reasoning,
                promptTokens: promptTokens,
                toolCalls: toolCalls,
                assistantMessage: assistantMessagePayload(message: message, fallbackText: text)
            )
        }

        if let outputText = normalizedOptionalString(object["output_text"]) {
            return AgentRoundResult(
                text: outputText,
                reasoning: reasoning,
                promptTokens: promptTokens,
                toolCalls: [],
                assistantMessage: ["role": "assistant", "content": outputText]
            )
        }

        throw CoordinatorError.invalidResponse("模型没有返回可展示的回复。")
    }

    private func parseToolCalls(_ raw: Any?) -> [ToolCall] {
        guard let toolCalls = raw as? [[String: Any]] else { return [] }
        return toolCalls.compactMap { item in
            guard let function = dictionaryValue(item["function"]),
                  let name = normalizedOptionalString(function["name"]) else {
                return nil
            }
            return ToolCall(
                id: normalizedOptionalString(item["id"]) ?? UUID().uuidString,
                name: name,
                argumentsJSON: normalizedOptionalString(function["arguments"]) ?? "{}"
            )
        }
    }

    private func assistantMessagePayload(message: [String: Any], fallbackText: String) -> [String: Any] {
        var payload: [String: Any] = ["role": "assistant"]
        if let content = message["content"] {
            payload["content"] = content
        } else {
            payload["content"] = fallbackText.isEmpty ? NSNull() : fallbackText
        }
        if let toolCalls = message["tool_calls"] {
            payload["tool_calls"] = toolCalls
        }
        return payload
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
            return CompletionResult(
                text: outputText,
                reasoning: parseReasoning(from: object),
                promptTokens: promptTokens
            )
        }

        if let choices = object["choices"] as? [[String: Any]],
           let firstChoice = choices.first {
            if let message = dictionaryValue(firstChoice["message"]),
               let content = parseOpenAIMessageContent(message["content"]) {
                return CompletionResult(
                    text: content,
                    reasoning: parseReasoning(from: object),
                    promptTokens: promptTokens
                )
            }
            if let text = normalizedOptionalString(firstChoice["text"]) {
                return CompletionResult(
                    text: text,
                    reasoning: parseReasoning(from: object),
                    promptTokens: promptTokens
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
                    promptTokens: promptTokens
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
           ]) {
            return messageReasoning
        }

        if let choices = object["choices"] as? [[String: Any]],
           let firstChoice = choices.first {
            if let delta = dictionaryValue(firstChoice["delta"]),
               let deltaReasoning = mergeNonEmptyTexts([
                   parseReasoningPayload(delta["reasoning_content"]),
                   parseReasoningPayload(delta["reasoning"]),
                   parseReasoningPayload(delta["thinking"]),
                   parseReasoningPayload(delta["content"]),
               ]) {
                return deltaReasoning
            }

            if let message = dictionaryValue(firstChoice["message"]),
               let messageReasoning = mergeNonEmptyTexts([
                   parseReasoningPayload(message["reasoning_content"]),
                   parseReasoningPayload(message["reasoning"]),
                   parseReasoningPayload(message["thinking"]),
                   parseReasoningPayload(message["content"]),
               ]) {
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
               let message = normalizedOptionalString(error["message"]) {
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

    private func decorateToolParameters(
        baseProperties: [String: Any],
        required: [String]
    ) -> [String: Any] {
        var properties = baseProperties
        properties["tool_title"] = [
            "type": "string",
            "description": "展示给用户的简短标题，建议 4-12 个字，并使用与用户相同的语言。",
        ]
        var nextRequired = required
        if nextRequired.contains("tool_title") == false {
            nextRequired.insert("tool_title", at: 0)
        }
        return [
            "type": "object",
            "properties": properties,
            "required": nextRequired,
        ]
    }

    private func schemaString(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private func schemaInteger(_ description: String) -> [String: Any] {
        ["type": "integer", "description": description]
    }

    private func schemaBoolean(_ description: String) -> [String: Any] {
        ["type": "boolean", "description": description]
    }

    private func schemaEnum(_ values: [String], description: String) -> [String: Any] {
        ["type": "string", "enum": values, "description": description]
    }

    private func toolCardId(taskId: String, toolCallId: String, fallbackIndex: Int) -> String {
        let sanitizedToolCallId = toolCallId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
        if sanitizedToolCallId.isEmpty == false {
            return "\(taskId)-tool-\(sanitizedToolCallId)"
        }
        return "\(taskId)-tool-\(fallbackIndex)"
    }

    private func extractToolTitle(from arguments: [String: Any]) -> String? {
        normalizedOptionalString(arguments["tool_title"])
    }

    private func extractToolTitle(fromJSON json: String) -> String? {
        extractToolTitle(from: parseToolArguments(json))
    }

    private func parseToolArguments(_ raw: String) -> [String: Any] {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return [:]
        }
        return dictionaryValue(object) ?? [:]
    }

    private func errorExecution(message: String) -> AgentToolExecution {
        let payload: [String: Any] = ["message": message]
        return AgentToolExecution(
            status: "error",
            summary: message,
            progress: "",
            resultPreviewJSON: previewJSONString(from: payload),
            rawResultJSON: jsonString(from: payload),
            terminalOutput: "",
            terminalOutputDelta: "",
            terminalSessionId: nil,
            terminalStreamState: "",
            workspaceId: nil,
            interruptedBy: nil,
            interruptionReason: nil,
            artifacts: [],
            actions: [],
            success: false
        )
    }

    private func interruptedExecution(cardId: String, previous: AgentToolExecution? = nil) -> AgentToolExecution {
        let payload: [String: Any] = [
            "cardId": cardId,
            "reason": "user_stop",
        ]
        return AgentToolExecution(
            status: "interrupted",
            summary: previous?.summary.isEmpty == false ? previous!.summary : "工具调用已停止",
            progress: "",
            resultPreviewJSON: previewJSONString(from: payload),
            rawResultJSON: jsonString(from: payload),
            terminalOutput: previous?.terminalOutput ?? "",
            terminalOutputDelta: "",
            terminalSessionId: previous?.terminalSessionId,
            terminalStreamState: previous?.terminalStreamState ?? "",
            workspaceId: previous?.workspaceId,
            interruptedBy: "user",
            interruptionReason: "stop_tool_call",
            artifacts: previous?.artifacts ?? [],
            actions: previous?.actions ?? [],
            success: false
        )
    }

    private func cancelToolTasks(forTaskId taskId: String) {
        let prefix = "\(taskId)-tool-"
        for (cardId, task) in activeToolTasks where cardId.hasPrefix(prefix) {
            task.cancel()
            activeToolTasks.removeValue(forKey: cardId)
        }
        requestedToolStops = requestedToolStops.filter { $0.hasPrefix(prefix) == false }
    }

    private func currentPromptTokenThreshold(conversationId: Int) -> Int {
        let payload = conversationArchiveStore
            .listConversationPayloads()
            .first(where: { integerValue($0["id"]) == conversationId })
        return integerValue(payload?["promptTokenThreshold"]) ?? 128_000
    }

    private func resolvedWorkspaceURL(for rawPath: String?) throws -> URL {
        let normalized = normalizedOptionalString(rawPath) ?? "/workspace"
        let shellPath: String
        if normalized.hasPrefix("omnibot://") {
            let suffix = normalized.replacingOccurrences(of: "omnibot://", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            shellPath = "/workspace/.omnibot/\(suffix)"
        } else {
            shellPath = IOSWorkspaceSupport.normalizedShellPath(normalized)
        }
        let url = IOSWorkspaceSupport.hostURL(forShellPath: shellPath).standardizedFileURL
        let workspaceRoot = IOSWorkspaceSupport.workspaceRootURL.standardizedFileURL.path
        guard url.path.hasPrefix(workspaceRoot) else {
            throw CoordinatorError.invalidArguments("路径超出 workspace 范围：\(normalized)")
        }
        return url
    }

    private func fileReadPayload(_ arguments: [String: Any]) throws -> [String: Any] {
        let path = try normalizedRequiredString(arguments["path"], name: "path")
        let url = try resolvedWorkspaceURL(for: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CoordinatorError.fileNotFound(path)
        }
        let rawContent = try String(contentsOf: url, encoding: .utf8)
        let maxChars = max(128, min(integerValue(arguments["maxChars"]) ?? 8_000, 64_000))
        let offset = max(0, integerValue(arguments["offset"]) ?? 0)
        let lineStart = max(1, integerValue(arguments["lineStart"]) ?? 1)
        let lineCount = max(1, integerValue(arguments["lineCount"]) ?? 0)

        let content: String
        if arguments["lineStart"] != nil || arguments["lineCount"] != nil {
            let lines = rawContent.components(separatedBy: .newlines)
            let startIndex = min(max(0, lineStart - 1), max(0, lines.count - 1))
            let count = lineCount > 0 ? lineCount : lines.count
            let slice = Array(lines.dropFirst(startIndex).prefix(count))
            content = slice.joined(separator: "\n")
        } else {
            let startIndex = min(offset, rawContent.count)
            let start = rawContent.index(rawContent.startIndex, offsetBy: startIndex)
            content = String(rawContent[start...].prefix(maxChars))
        }

        return [
            "path": IOSWorkspaceSupport.shellPath(for: url),
            "hostPath": url.path,
            "content": content,
            "truncated": content.count < rawContent.count,
            "characterCount": rawContent.count,
        ]
    }

    private func fileWritePayload(_ arguments: [String: Any]) throws -> [String: Any] {
        let path = try normalizedRequiredString(arguments["path"], name: "path")
        let content = try normalizedRequiredString(arguments["content"], name: "content")
        let append = boolValue(arguments["append"]) ?? false
        let url = try resolvedWorkspaceURL(for: path)
        IOSWorkspaceSupport.createDirectoryIfNeeded(url.deletingLastPathComponent())
        if append, FileManager.default.fileExists(atPath: url.path) {
            let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try "\(existing)\(content)".write(to: url, atomically: true, encoding: .utf8)
        } else {
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        return [
            "path": IOSWorkspaceSupport.shellPath(for: url),
            "hostPath": url.path,
            "append": append,
            "size": (try? Data(contentsOf: url).count) ?? content.count,
        ]
    }

    private func fileEditPayload(_ arguments: [String: Any]) throws -> [String: Any] {
        let path = try normalizedRequiredString(arguments["path"], name: "path")
        let oldText = try normalizedRequiredString(arguments["oldText"], name: "oldText")
        let newText = try normalizedRequiredString(arguments["newText"], name: "newText")
        let replaceAll = boolValue(arguments["replaceAll"]) ?? false
        let url = try resolvedWorkspaceURL(for: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CoordinatorError.fileNotFound(path)
        }
        let existing = try String(contentsOf: url, encoding: .utf8)
        guard existing.contains(oldText) else {
            throw CoordinatorError.invalidArguments("oldText 未在文件中找到")
        }
        let updated = replaceAll
            ? existing.replacingOccurrences(of: oldText, with: newText)
            : existing.replacingOccurrences(of: oldText, with: newText, options: [], range: existing.range(of: oldText))
        try updated.write(to: url, atomically: true, encoding: .utf8)
        return [
            "path": IOSWorkspaceSupport.shellPath(for: url),
            "hostPath": url.path,
            "replaceAll": replaceAll,
            "updated": true,
        ]
    }

    private func fileListPayload(_ arguments: [String: Any]) throws -> [String: Any] {
        let url = try resolvedWorkspaceURL(for: normalizedOptionalString(arguments["path"]) ?? "/workspace")
        let recursive = boolValue(arguments["recursive"]) ?? false
        let maxDepth = max(1, min(integerValue(arguments["maxDepth"]) ?? 2, 6))
        let limit = max(1, min(integerValue(arguments["limit"]) ?? 200, 1_000))
        var items = [[String: Any]]()

        if recursive {
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            while let next = enumerator?.nextObject() as? URL, items.count < limit {
                let depth = next.path.replacingOccurrences(of: url.path, with: "")
                    .split(separator: "/")
                    .count
                if depth > maxDepth {
                    enumerator?.skipDescendants()
                    continue
                }
                items.append(fileEntryPayload(for: next))
            }
        } else {
            let children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            items = children.prefix(limit).map(fileEntryPayload)
        }

        return [
            "path": IOSWorkspaceSupport.shellPath(for: url),
            "items": items,
            "recursive": recursive,
        ]
    }

    private func fileSearchPayload(_ arguments: [String: Any]) throws -> [String: Any] {
        let query = try normalizedRequiredString(arguments["query"], name: "query")
        let url = try resolvedWorkspaceURL(for: normalizedOptionalString(arguments["path"]) ?? "/workspace")
        let caseSensitive = boolValue(arguments["caseSensitive"]) ?? false
        let maxResults = max(1, min(integerValue(arguments["maxResults"]) ?? 50, 200))
        let normalizedQuery = caseSensitive ? query : query.lowercased()
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var results = [[String: Any]]()
        while let next = enumerator?.nextObject() as? URL, results.count < maxResults {
            let entry = fileEntryPayload(for: next)
            let shellPath = (entry["path"] as? String) ?? ""
            let nameHaystack = caseSensitive ? shellPath : shellPath.lowercased()
            if nameHaystack.contains(normalizedQuery) {
                results.append(entry.merging(["match": "path"], uniquingKeysWith: { _, new in new }))
                continue
            }

            let fileSize = (entry["size"] as? Int) ?? 0
            let isDirectory = entry["isDirectory"] as? Bool == true
            if isDirectory || fileSize > 256_000 {
                continue
            }
            if let content = try? String(contentsOf: next, encoding: .utf8) {
                let haystack = caseSensitive ? content : content.lowercased()
                if haystack.contains(normalizedQuery) {
                    let preview = snippet(for: content, query: query, caseSensitive: caseSensitive)
                    results.append(entry.merging(["match": "content", "preview": preview], uniquingKeysWith: { _, new in new }))
                }
            }
        }

        return [
            "query": query,
            "path": IOSWorkspaceSupport.shellPath(for: url),
            "results": results,
        ]
    }

    private func fileStatPayload(_ arguments: [String: Any]) throws -> [String: Any] {
        let path = try normalizedRequiredString(arguments["path"], name: "path")
        let url = try resolvedWorkspaceURL(for: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CoordinatorError.fileNotFound(path)
        }
        return fileEntryPayload(for: url)
    }

    private func fileMovePayload(_ arguments: [String: Any]) throws -> [String: Any] {
        let sourcePath = try normalizedRequiredString(arguments["sourcePath"], name: "sourcePath")
        let targetPath = try normalizedRequiredString(arguments["targetPath"], name: "targetPath")
        let overwrite = boolValue(arguments["overwrite"]) ?? false
        let sourceURL = try resolvedWorkspaceURL(for: sourcePath)
        let targetURL = try resolvedWorkspaceURL(for: targetPath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw CoordinatorError.fileNotFound(sourcePath)
        }
        IOSWorkspaceSupport.createDirectoryIfNeeded(targetURL.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: targetURL.path) {
            guard overwrite else {
                throw CoordinatorError.invalidArguments("目标文件已存在")
            }
            try FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.moveItem(at: sourceURL, to: targetURL)
        return [
            "sourcePath": IOSWorkspaceSupport.shellPath(for: sourceURL),
            "targetPath": IOSWorkspaceSupport.shellPath(for: targetURL),
            "hostTargetPath": targetURL.path,
            "overwrite": overwrite,
        ]
    }

    private func skillsListPayload(_ arguments: [String: Any]) -> [String: Any] {
        let query = normalizedOptionalString(arguments["query"])?.lowercased()
        let limit = max(1, min(integerValue(arguments["limit"]) ?? 50, 200))
        let items = agentSkillStore.listSkillsPayload()
            .filter { item in
                guard let query else { return true }
                let haystack = [
                    normalizedOptionalString(item["id"]) ?? "",
                    normalizedOptionalString(item["name"]) ?? "",
                    normalizedOptionalString(item["description"]) ?? "",
                    normalizedOptionalString(item["skillFilePath"]) ?? "",
                ].joined(separator: "\n").lowercased()
                return haystack.contains(query)
            }
            .prefix(limit)
        return ["items": Array(items)]
    }

    private func skillsReadPayload(_ arguments: [String: Any]) throws -> [String: Any] {
        let skillId = try normalizedRequiredString(arguments["skillId"], name: "skillId")
        let maxChars = max(512, min(integerValue(arguments["maxChars"]) ?? 16_000, 64_000))
        let items = agentSkillStore.listSkillsPayload()
        guard let match = items.first(where: { item in
            let candidates = [
                normalizedOptionalString(item["id"]) ?? "",
                normalizedOptionalString(item["name"]) ?? "",
                normalizedOptionalString(item["rootPath"]) ?? "",
                normalizedOptionalString(item["skillFilePath"]) ?? "",
            ]
            return candidates.contains(skillId)
        }) else {
            throw CoordinatorError.invalidArguments("未找到对应的 Skill：\(skillId)")
        }
        let skillFilePath = normalizedOptionalString(match["skillFilePath"]) ?? ""
        let content = skillFilePath.isEmpty ? "" : ((try? String(contentsOfFile: skillFilePath, encoding: .utf8)) ?? "")
        return match.merging(["content": String(content.prefix(maxChars))], uniquingKeysWith: { _, new in new })
    }

    private func scheduleCreatePayload(_ arguments: [String: Any]) throws -> [String: Any] {
        let title = try normalizedRequiredString(arguments["title"], name: "title")
        let targetKind = normalizedOptionalString(arguments["targetKind"]) ?? "vlm"
        guard targetKind == "vlm" || targetKind == "subagent" else {
            throw CoordinatorError.invalidArguments("targetKind 仅支持 vlm 或 subagent")
        }
        let scheduleType = normalizedOptionalString(arguments["scheduleType"]) ?? "fixed_time"
        let rawTask: [String: Any] = [
            "id": UUID().uuidString,
            "title": title,
            "packageName": normalizedOptionalString(arguments["packageName"]) ?? "",
            "nodeId": "",
            "suggestionId": "",
            "targetKind": targetKind,
            "subagentConversationId": normalizedOptionalString(arguments["subagentConversationId"]) ?? NSNull(),
            "subagentPrompt": normalizedOptionalString(arguments["subagentPrompt"]) ?? NSNull(),
            "notificationEnabled": boolValue(arguments["notificationEnabled"]) ?? true,
            "type": scheduleType == "countdown" ? "countdown" : "fixedTime",
            "fixedTime": normalizedOptionalString(arguments["fixedTime"]) ?? NSNull(),
            "countdownMinutes": integerValue(arguments["countdownMinutes"]) ?? NSNull(),
            "repeatDaily": boolValue(arguments["repeatDaily"]) ?? false,
            "isEnabled": boolValue(arguments["enabled"]) ?? true,
            "createdAt": timestampMillis(),
            "nextExecutionTime": NSNull(),
            "suggestionData": buildScheduleSuggestionData(arguments, targetKind: targetKind),
            "appIconUrl": NSNull(),
            "typeIconUrl": NSNull(),
        ]
        let task = scheduledTaskStore.upsertTask(rawTask)
        return [
            "success": true,
            "taskId": normalizedOptionalString(task["id"]) ?? "",
            "summary": "已创建定时任务“\(title)”",
            "task": task,
        ]
    }

    private func scheduleListPayload() -> [String: Any] {
        ["tasks": scheduledTaskStore.listTasks()]
    }

    private func scheduleUpdatePayload(_ arguments: [String: Any]) throws -> [String: Any] {
        let taskId = try normalizedRequiredString(arguments["taskId"], name: "taskId")
        guard var existing = scheduledTaskStore.listTasks().first(where: {
            normalizedOptionalString($0["id"]) == taskId
        }) else {
            throw CoordinatorError.taskNotFound("未找到对应的定时任务")
        }
        for (key, value) in arguments where key != "tool_title" && key != "taskId" {
            if value is NSNull {
                existing[key] = NSNull()
            } else {
                existing[key] = value
            }
        }
        if let targetKind = normalizedOptionalString(existing["targetKind"]) {
            existing["suggestionData"] = buildScheduleSuggestionData(existing, targetKind: targetKind)
        }
        let task = scheduledTaskStore.upsertTask(existing)
        return [
            "success": true,
            "taskId": taskId,
            "summary": "已更新定时任务“\(normalizedOptionalString(task["title"]) ?? taskId)”",
            "task": task,
        ]
    }

    private func scheduleDeletePayload(_ arguments: [String: Any]) throws -> [String: Any] {
        let taskId = try normalizedRequiredString(arguments["taskId"], name: "taskId")
        guard let existing = scheduledTaskStore.listTasks().first(where: {
            normalizedOptionalString($0["id"]) == taskId
        }) else {
            throw CoordinatorError.taskNotFound("未找到对应的定时任务")
        }
        let deleted = scheduledTaskStore.deleteTask(taskId: taskId)
        guard deleted else {
            throw CoordinatorError.invalidResponse("定时任务删除失败")
        }
        return [
            "success": true,
            "taskId": taskId,
            "summary": "已删除定时任务“\(normalizedOptionalString(existing["title"]) ?? taskId)”",
            "task": existing,
        ]
    }

    private func buildScheduleSuggestionData(_ raw: [String: Any], targetKind: String) -> Any {
        if targetKind == "subagent" {
            let prompt = normalizedOptionalString(raw["subagentPrompt"]) ?? ""
            if prompt.isEmpty {
                return NSNull()
            }
            return [
                "targetKind": "subagent",
                "subagentPrompt": prompt,
            ]
        }
        let goal = normalizedOptionalString(raw["goal"])
        guard let goal, goal.isEmpty == false else {
            return NSNull()
        }
        return [
            "goal": goal,
            "packageName": normalizedOptionalString(raw["packageName"]) ?? "",
            "needSummary": false,
            "targetKind": "vlm",
        ]
    }

    private func memorySearchPayload(_ arguments: [String: Any]) -> [String: Any] {
        let query = normalizedOptionalString(arguments["query"]) ?? ""
        let limit = max(1, min(integerValue(arguments["limit"]) ?? 8, 20))
        return [
            "query": query,
            "results": memoryStore.searchMemory(query: query, limit: limit),
        ]
    }

    private func memoryWriteDailyPayload(_ arguments: [String: Any]) throws -> [String: Any] {
        let text = try normalizedRequiredString(arguments["text"], name: "text")
        let item = memoryStore.appendShortMemory(text)
        guard let item else {
            throw CoordinatorError.invalidResponse("短期记忆写入失败")
        }
        return [
            "success": true,
            "summary": "已写入当日记忆",
            "item": item,
        ]
    }

    private func memoryUpsertLongTermPayload(_ arguments: [String: Any]) throws -> [String: Any] {
        let text = try normalizedRequiredString(arguments["text"], name: "text")
        let current = memoryStore.getLongMemoryPayload()["content"] as? String ?? ""
        let normalizedEntry = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedEntry.isEmpty == false else {
            throw CoordinatorError.invalidArguments("text is empty")
        }

        let existingBullets = Set(
            current
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.hasPrefix("- ") }
                .map { String($0.dropFirst(2)).lowercased() }
        )
        var next = current.trimmingCharacters(in: .newlines)
        let inserted = existingBullets.contains(normalizedEntry.lowercased()) == false
        if inserted {
            if next.isEmpty {
                next = "# MEMORY\n\n## Long-Term Memory"
            }
            if next.hasSuffix("\n") == false {
                next.append("\n")
            }
            next.append("- \(normalizedEntry)\n")
            _ = memoryStore.saveLongMemory(next)
        }

        return [
            "success": true,
            "summary": inserted ? "已沉淀长期记忆" : "长期记忆已存在，未重复写入",
            "inserted": inserted,
            "content": memoryStore.getLongMemoryPayload()["content"] ?? "",
        ]
    }

    private func memoryRollupPayload(_ arguments: [String: Any]) throws -> [String: Any] {
        if let date = normalizedOptionalString(arguments["date"]) {
            let today = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            _ = today
            if date.isEmpty == false {
                let canonicalToday = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date())).prefix(10)
                if date != canonicalToday {
                    throw CoordinatorError.invalidArguments("当前 iOS 实现仅支持整理今天的记忆")
                }
            }
        }
        return memoryStore.runRollupNowPayload()
    }

    private func browserSnapshotPayload(_ arguments: [String: Any]) throws -> [String: Any] {
        let workspaceId = normalizedOptionalString(arguments["workspaceId"])
        let snapshot: BrowserSessionSnapshotMessage
        if let workspaceId,
           let workspaceSnapshot = BrowserSessionStore.shared.snapshot(for: workspaceId) {
            snapshot = workspaceSnapshot
        } else {
            snapshot = BrowserSessionStore.shared.currentSnapshot()
        }
        return [
            "available": snapshot.available,
            "workspaceId": snapshot.workspaceId,
            "activeTabId": snapshot.activeTabId ?? NSNull(),
            "currentUrl": snapshot.currentUrl,
            "title": snapshot.title,
            "userAgentProfile": snapshot.userAgentProfile ?? NSNull(),
        ]
    }

    private func subagentDispatchPayload(_ arguments: [String: Any]) async throws -> [String: Any] {
        let tasks = stringArrayValue(arguments["tasks"]).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { $0.isEmpty == false }
        guard tasks.isEmpty == false else {
            throw CoordinatorError.invalidArguments("tasks is empty")
        }
        let mergeInstruction = normalizedOptionalString(arguments["mergeInstruction"]) ?? ""
        var results = [[String: Any]]()

        for task in tasks {
            let conversation = conversationArchiveStore.createConversation(
                title: String(task.prefix(20)),
                summary: nil,
                mode: "subagent"
            )
            let conversationId = integerValue(conversation["id"]) ?? 0
            if conversationId > 0 {
                conversationArchiveStore.upsertUserMessage(
                    conversationId: conversationId,
                    conversationMode: "subagent",
                    entryId: UUID().uuidString,
                    text: task
                )
            }
            let prompt = mergeInstruction.isEmpty
                ? task
                : "\(task)\n\n聚合要求：\(mergeInstruction)"
            let reply = try await postLLMChat(
                text: prompt,
                modelScene: "scene.dispatch.model"
            )
            if conversationId > 0 {
                conversationArchiveStore.upsertAssistantMessage(
                    conversationId: conversationId,
                    conversationMode: "subagent",
                    entryId: "\(conversationId)-assistant",
                    text: reply
                )
                _ = try? conversationArchiveStore.completeConversation(conversationId: conversationId)
            }
            results.append([
                "task": task,
                "conversationId": conversationId,
                "response": reply,
            ])
        }

        return [
            "success": true,
            "summary": "已完成 \(results.count) 个 subagent 子任务。",
            "results": results,
        ]
    }

    private func fileEntryPayload(for url: URL) -> [String: Any] {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        return [
            "path": IOSWorkspaceSupport.shellPath(for: url),
            "hostPath": url.path,
            "name": url.lastPathComponent,
            "isDirectory": values?.isDirectory == true,
            "size": values?.fileSize ?? 0,
            "modifiedAt": Int((values?.contentModificationDate ?? Date()).timeIntervalSince1970 * 1000),
        ]
    }

    private func fileArtifact(from payload: [String: Any]) -> [String: Any] {
        [
            "type": "file",
            "path": normalizedOptionalString(payload["path"]) ?? "",
            "hostPath": normalizedOptionalString(payload["hostPath"]) ?? "",
        ]
    }

    private func snippet(for content: String, query: String, caseSensitive: Bool) -> String {
        let haystack = caseSensitive ? content : content.lowercased()
        let needle = caseSensitive ? query : query.lowercased()
        guard let range = haystack.range(of: needle) else {
            return String(content.prefix(200))
        }
        let lowerBound = max(0, haystack.distance(from: haystack.startIndex, to: range.lowerBound) - 80)
        let upperBound = min(content.count, haystack.distance(from: haystack.startIndex, to: range.upperBound) + 120)
        let start = content.index(content.startIndex, offsetBy: lowerBound)
        let end = content.index(content.startIndex, offsetBy: upperBound)
        return String(content[start..<end])
    }

    private func trimmedContext(_ value: String, limit: Int) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)) + "…"
    }

    private func jsonString(from object: Any) -> String {
        if JSONSerialization.isValidJSONObject(object),
           let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        if let string = object as? String {
            return string
        }
        return "{}"
    }

    private func previewJSONString(from object: Any) -> String {
        let raw = jsonString(from: object)
        return raw.count > 1_600 ? String(raw.prefix(1_600)) + "..." : raw
    }

    private func timestampMillis() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
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
        case let int64 as Int64:
            return Int(int64)
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
            return number.boolValue
        case let string as String:
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
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

    private func stringDictionaryValue(_ raw: Any?) -> [String: String] {
        guard let dictionary = dictionaryValue(raw) else { return [:] }
        return dictionary.reduce(into: [String: String]()) { partialResult, entry in
            if let value = normalizedOptionalString(entry.value) {
                partialResult[entry.key] = value
            }
        }
    }

    private func stringArrayValue(_ raw: Any?) -> [String] {
        guard let array = raw as? [Any] else { return [] }
        return array.compactMap(normalizedOptionalString)
    }
}
