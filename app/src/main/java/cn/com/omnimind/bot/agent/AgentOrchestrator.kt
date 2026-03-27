package cn.com.omnimind.bot.agent

import cn.com.omnimind.baselib.llm.AssistantToolCall
import cn.com.omnimind.baselib.llm.ChatCompletionMessage
import cn.com.omnimind.baselib.llm.ChatCompletionRequest
import cn.com.omnimind.baselib.llm.ChatCompletionStreamOptions
import cn.com.omnimind.baselib.llm.contentText
import cn.com.omnimind.baselib.util.OmniLog
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

class AgentOrchestrator(
    private val llmClient: AgentLlmClient,
    private val toolRegistry: AgentToolRegistry,
    private val toolRouter: AgentToolRouter,
    private val eventAdapter: AgentEventAdapter,
    private val model: String
) {
    internal data class RecoverableToolFailure(
        val toolName: String,
        val summary: String
    )

    data class Input(
        val callback: AgentCallback,
        val initialMessages: List<ChatCompletionMessage>,
        val executionEnv: AgentToolRouter.ExecutionEnvironment,
        val conversationId: Long? = null,
        val contextCompactor: AgentConversationContextCompactor? = null
    )

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
        prettyPrint = true
    }
    private val tag = "AgentOrchestrator"

    companion object {
        private const val MAX_EXECUTION_INTENT_RETRIES = 1
        private const val MAX_TOOL_FAILURE_RECOVERY_RETRIES = 2
        internal fun extractRecoverableToolFailure(
            toolName: String,
            result: ToolExecutionResult
        ): RecoverableToolFailure? {
            val summary = when (result) {
                is ToolExecutionResult.Error -> result.message
                is ToolExecutionResult.TerminalResult -> result.summaryText.takeIf { !result.success }
                is ToolExecutionResult.ScheduleResult -> result.summaryText.takeIf { !result.success }
                is ToolExecutionResult.McpResult -> result.summaryText.takeIf { !result.success }
                is ToolExecutionResult.MemoryResult -> result.summaryText.takeIf { !result.success }
                is ToolExecutionResult.ContextResult -> result.summaryText.takeIf { !result.success }
                else -> null
            }?.trim()?.takeIf { it.isNotEmpty() }

            return summary?.let {
                RecoverableToolFailure(
                    toolName = toolName,
                    summary = it
                )
            }
        }

        internal fun buildToolFailureRetryPrompt(
            userMessage: String,
            failure: RecoverableToolFailure
        ): String {
            return buildString {
                appendLine("系统检测到你上一轮工具调用失败后，没有继续返回新的 tool_calls。")
                appendLine("请基于最近一次失败结果继续推进，而不是直接结束。")
                appendLine("优先选择以下其一：")
                appendLine("1. 若可修复，立刻返回新的 assistant.tool_calls 重试。")
                appendLine("2. 若缺少关键信息，直接向用户澄清。")
                appendLine("3. 若确认环境受限，请明确告诉用户具体缺什么以及下一步建议。")
                appendLine("最近一次失败工具：${failure.toolName}")
                appendLine("失败摘要：${failure.summary}")
                appendLine("用户原始请求：$userMessage")
            }.trim()
        }

        internal fun buildToolFailureExhaustedMessage(
            failure: RecoverableToolFailure
        ): String {
            return buildString {
                append("刚才在执行 `")
                append(failure.toolName)
                append("` 时连续失败，最近一次错误是：")
                append(failure.summary)
                append("。我先停在这里，避免继续空转；你可以让我按新方案继续重试，或者我先帮你诊断环境问题。")
            }
        }
    }

    suspend fun run(input: Input): AgentResult {
        val callback = input.callback
        var messages = input.initialMessages.toMutableList()
        val executedTools = mutableListOf<ToolExecutionResult>()
        var outputKind = AgentOutputKind.NONE
        var hasUserFacingOutput = false
        var toolExecutionCount = 0
        var lastAssistantContent = ""
        var lastFinishReason: String? = null
        var latestPromptTokens: Int? = null
        var latestPromptTokenThreshold: Int? = null
        var terminalRetryState = TerminalRetryState()
        val executionIntent = AgentExecutionIntentPolicy.isExecutionIntent(input.executionEnv.userMessage)
        var executionIntentRetryCount = 0
        var pendingRecoverableToolFailure: RecoverableToolFailure? = null
        var toolFailureRecoveryRetryCount = 0
        var completedModelRounds = 0
        var terminated = false

        try {
            roundLoop@ while (true) {
                completedModelRounds += 1
                val round = completedModelRounds
                callback.onThinkingStart()
                val toolChoiceForRound = if (messages.lastOrNull()?.role == "tool") {
                    null
                } else {
                    JsonPrimitive("auto")
                }
                OmniLog.i(
                    tag,
                    "round=$round request_tools=${toolRegistry.toolsForModel.size} tool_exec_count=$toolExecutionCount execution_intent=$executionIntent"
                )
                val turn = llmClient.streamTurn(
                    request = ChatCompletionRequest(
                        messages = messages,
                        model = model,
                        maxCompletionTokens = 16384,
                        stream = true,
                        streamOptions = ChatCompletionStreamOptions(includeUsage = true),
                        tools = toolRegistry.toolsForModel,
                        toolChoice = toolChoiceForRound,
                        parallelToolCalls = false
                    ),
                    onReasoningUpdate = { reasoning ->
                        if (reasoning.isNotBlank()) {
                            callback.onThinkingUpdate(normalizeThinkingText(reasoning))
                        }
                    },
                    onContentUpdate = { content ->
                        if (
                            content.isNotBlank() &&
                            !AgentExecutionIntentPolicy.containsPseudoToolMarkup(content)
                        ) {
                            callback.onChatMessage(content, false)
                        }
                    }
                )

                lastFinishReason = turn.finishReason
                lastAssistantContent = turn.message.contentText().trim()
                val toolCalls = turn.message.toolCalls.orEmpty()
                val hasPseudoToolMarkup =
                    AgentExecutionIntentPolicy.containsPseudoToolMarkup(lastAssistantContent)
                OmniLog.i(
                    tag,
                    "round=$round parsed_tool_calls=${toolCalls.size} finish_reason=${lastFinishReason.orEmpty()} assistant_content_len=${lastAssistantContent.length} pseudo_tool_markup=$hasPseudoToolMarkup"
                )

                messages.add(
                    ChatCompletionMessage(
                        role = "assistant",
                        content = normalizeAssistantContentForNextRound(
                            content = turn.message.content,
                            toolCalls = toolCalls
                        ),
                        toolCalls = toolCalls.ifEmpty { null }
                    )
                )
                latestPromptTokens = turn.usage?.promptTokens
                input.contextCompactor?.let { compactor ->
                    latestPromptTokenThreshold = compactor.resolvePromptTokenThreshold(input.conversationId)
                    messages = compactor.compactIfNeeded(
                        conversationId = input.conversationId,
                        conversationMode = input.executionEnv.conversationMode,
                        promptTokens = latestPromptTokens,
                        messages = messages
                    ).toMutableList()
                }

                if (toolCalls.isEmpty()) {
                    val failure = pendingRecoverableToolFailure
                    if (failure != null) {
                        if (toolFailureRecoveryRetryCount < MAX_TOOL_FAILURE_RECOVERY_RETRIES) {
                            toolFailureRecoveryRetryCount += 1
                            messages.add(
                                ChatCompletionMessage(
                                    role = "user",
                                    content = JsonPrimitive(
                                        buildToolFailureRetryPrompt(
                                            userMessage = input.executionEnv.userMessage,
                                            failure = failure
                                        )
                                    )
                                )
                            )
                            OmniLog.w(
                                tag,
                                "round=$round tool failure recovery retry=$toolFailureRecoveryRetryCount/$MAX_TOOL_FAILURE_RECOVERY_RETRIES tool=${failure.toolName}"
                            )
                            continue@roundLoop
                        }

                        val fallbackMessage = buildToolFailureExhaustedMessage(failure)
                        callback.onChatMessage(fallbackMessage, true)
                        executedTools.add(ToolExecutionResult.ChatMessage(fallbackMessage))
                        outputKind = AgentOutputKind.CHAT_MESSAGE
                        hasUserFacingOutput = true
                        terminated = true
                        break
                    }

                    if (hasPseudoToolMarkup) {
                        if (AgentExecutionIntentPolicy.shouldRetryNoToolCall(
                                executionIntent = true,
                                toolExecutionCount = toolExecutionCount,
                                retryCount = executionIntentRetryCount,
                                maxRetries = MAX_EXECUTION_INTENT_RETRIES
                            )
                        ) {
                            executionIntentRetryCount += 1
                            messages.add(
                                ChatCompletionMessage(
                                    role = "user",
                                    content = JsonPrimitive(
                                        buildPseudoToolMarkupRetryPrompt(input.executionEnv.userMessage)
                                    )
                                )
                            )
                            OmniLog.w(
                                tag,
                                "round=$round pseudo tool markup detected; retry=$executionIntentRetryCount/$MAX_EXECUTION_INTENT_RETRIES"
                            )
                            continue@roundLoop
                        }
                        val errorMessage =
                            "协议或模型不支持标准工具调用：模型输出了伪工具标签，而不是 assistant.tool_calls"
                        OmniLog.e(tag, "round=$round fail_reason=pseudo_tool_markup_in_content")
                        callback.onError(errorMessage)
                        return AgentResult.Error(
                            errorMessage,
                            IllegalStateException(errorMessage)
                        )
                    }

                    if (AgentExecutionIntentPolicy.shouldRetryNoToolCall(
                            executionIntent = executionIntent,
                            toolExecutionCount = toolExecutionCount,
                            retryCount = executionIntentRetryCount,
                            maxRetries = MAX_EXECUTION_INTENT_RETRIES
                        )
                    ) {
                        executionIntentRetryCount += 1
                        val retryPrompt = buildExecutionIntentToolCallRetryPrompt(
                            input.executionEnv.userMessage
                        )
                        messages.add(
                            ChatCompletionMessage(
                                role = "user",
                                content = JsonPrimitive(retryPrompt)
                            )
                        )
                        OmniLog.w(
                            tag,
                            "round=$round execution-intent without tool_calls; retry=$executionIntentRetryCount/$MAX_EXECUTION_INTENT_RETRIES"
                        )
                        continue@roundLoop
                    }

                    if (AgentExecutionIntentPolicy.shouldFailNoToolCall(
                            executionIntent = executionIntent,
                            toolExecutionCount = toolExecutionCount,
                            retryCount = executionIntentRetryCount,
                            maxRetries = MAX_EXECUTION_INTENT_RETRIES
                        )
                    ) {
                        val errorMessage =
                            "协议或模型不支持工具调用：执行型请求未返回 tool_calls（finish_reason=${lastFinishReason.orEmpty()}）"
                        OmniLog.e(tag, "round=$round fail_reason=no_tool_calls_for_execution_intent")
                        callback.onError(errorMessage)
                        return AgentResult.Error(
                            errorMessage,
                            IllegalStateException(errorMessage)
                        )
                    }

                    val fallbackMessage = lastAssistantContent.ifBlank {
                        "我已完成思考，但暂时无法生成回复，请重试。"
                    }
                    callback.onChatMessage(fallbackMessage, true)
                    executedTools.add(ToolExecutionResult.ChatMessage(fallbackMessage))
                    outputKind = AgentOutputKind.CHAT_MESSAGE
                    hasUserFacingOutput = true
                    terminated = true
                    break
                }

                for (toolCall in toolCalls) {
                    val descriptor = toolRegistry.runtimeDescriptor(toolCall.function.name)
                    val parsedArgs: JsonObject = try {
                        parseToolArguments(toolCall.function.arguments)
                    } catch (error: Exception) {
                        val result = ToolExecutionResult.Error(
                            toolCall.function.name,
                            error.message ?: "Invalid tool arguments JSON"
                        )
                        executedTools.add(result)
                        callback.onToolCallComplete(toolCall.function.name, result)
                        messages.add(
                            ChatCompletionMessage(
                                role = "tool",
                                toolCallId = toolCall.id,
                                content = JsonPrimitive(eventAdapter.toolResultContent(descriptor, result))
                            )
                        )
                        hasUserFacingOutput = hasUserFacingOutput || eventAdapter.hasUserVisibleOutput(result)
                        terminated = true
                        break@roundLoop
                    }

                    runCatching {
                        toolRegistry.validateArguments(toolCall.function.name, parsedArgs)
                    }.onFailure { error ->
                        val result = ToolExecutionResult.Error(
                            toolCall.function.name,
                            error.message ?: "Tool arguments validation failed"
                        )
                        executedTools.add(result)
                        callback.onToolCallComplete(toolCall.function.name, result)
                        messages.add(
                            ChatCompletionMessage(
                                role = "tool",
                                toolCallId = toolCall.id,
                                content = JsonPrimitive(eventAdapter.toolResultContent(descriptor, result))
                            )
                        )
                        hasUserFacingOutput = hasUserFacingOutput || eventAdapter.hasUserVisibleOutput(result)
                        terminated = true
                        return@onFailure
                    }
                    if (terminated) break@roundLoop

                    callback.onToolCallStart(toolCall.function.name, parsedArgs)
                    val isTerminalToolCall = toolCall.function.name == "terminal_execute"
                    val result = if (isTerminalToolCall) {
                        val retryDecision = TerminalRetryPolicy.beforeTerminalExecution(terminalRetryState)
                        terminalRetryState = retryDecision.nextState
                        if (!retryDecision.shouldExecute) {
                            callback.onToolCallProgress(
                                toolCall.function.name,
                                "终端自动修正已达到上限，返回诊断结果"
                            )
                            toolRouter.buildTerminalRetryBudgetExhaustedResult(
                                args = parsedArgs,
                                retryState = terminalRetryState
                            )
                        } else {
                            toolRouter.execute(
                                toolCall = toolCall,
                                args = parsedArgs,
                                runtimeDescriptor = descriptor,
                                env = input.executionEnv,
                                callback = callback
                            ).also { toolResult ->
                                if (toolResult is ToolExecutionResult.TerminalResult) {
                                    terminalRetryState = TerminalRetryPolicy.afterTerminalResult(
                                        terminalRetryState,
                                        toolResult.success
                                    )
                                }
                            }
                        }
                    } else {
                        toolRouter.execute(
                            toolCall = toolCall,
                            args = parsedArgs,
                            runtimeDescriptor = descriptor,
                            env = input.executionEnv,
                            callback = callback
                        )
                    }

                    executedTools.add(result)
                    toolExecutionCount += 1
                    callback.onToolCallComplete(toolCall.function.name, result)
                    extractRecoverableToolFailure(toolCall.function.name, result)?.let { failure ->
                        pendingRecoverableToolFailure = failure
                        toolFailureRecoveryRetryCount = 0
                    } ?: run {
                        pendingRecoverableToolFailure = null
                        toolFailureRecoveryRetryCount = 0
                    }
                    messages.add(
                        ChatCompletionMessage(
                            role = "tool",
                            toolCallId = toolCall.id,
                            content = JsonPrimitive(eventAdapter.toolResultContent(descriptor, result))
                        )
                    )

                    if (eventAdapter.hasUserVisibleOutput(result)) {
                        hasUserFacingOutput = true
                    }
                    val mappedKind = eventAdapter.mapOutputKind(result)
                    if (mappedKind != AgentOutputKind.NONE) {
                        outputKind = mappedKind
                    }

                    if (eventAdapter.isConversationStoppingResult(result)) {
                        terminated = true
                        break@roundLoop
                    }
                    if (isTerminalToolCall) {
                        break
                    }
                }

                if (terminated) break
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            callback.onError("Agent execution failed: ${e.message}")
            return AgentResult.Error("Agent execution failed", e as? Exception)
        }

        if (!hasUserFacingOutput) {
            val fallbackMessage = lastAssistantContent.ifBlank {
                "我已完成思考，但暂时无法生成回复，请重试。"
            }
            callback.onChatMessage(fallbackMessage, true)
            executedTools.add(ToolExecutionResult.ChatMessage(fallbackMessage))
            outputKind = AgentOutputKind.CHAT_MESSAGE
            hasUserFacingOutput = true
        }

        val finalResult = AgentResult.Success(
            response = AgentFinalResponse(
                content = lastAssistantContent,
                finishReason = lastFinishReason,
                latestPromptTokens = latestPromptTokens,
                promptTokenThreshold = latestPromptTokens?.let { latestPromptTokenThreshold }
            ),
            executedTools = executedTools,
            outputKind = outputKind.value,
            hasUserVisibleOutput = hasUserFacingOutput,
            latestPromptTokens = latestPromptTokens,
            promptTokenThreshold = latestPromptTokens?.let { latestPromptTokenThreshold }
        )
        callback.onComplete(finalResult)
        return finalResult
    }

    private fun normalizeAssistantContentForNextRound(
        content: JsonElement?,
        toolCalls: List<AssistantToolCall>
    ): JsonElement? {
        if (toolCalls.isEmpty()) {
            return content
        }
        return when (content) {
            null -> JsonPrimitive("")
            is JsonPrimitive -> {
                if (content.isString && content.content.isBlank()) {
                    JsonPrimitive("")
                } else {
                    content
                }
            }
            else -> content
        }
    }

    private fun parseToolArguments(argumentsJson: String): JsonObject {
        val normalized = argumentsJson.trim()
        if (normalized.isEmpty()) return JsonObject(emptyMap())
        val parsed = json.decodeFromString<JsonElement>(normalized)
        return parsed as? JsonObject
            ?: throw IllegalArgumentException("tool arguments must be a JSON object")
    }

    private fun normalizeThinkingText(text: String, maxLen: Int = 3000): String {
        val normalized = text.replace("\r\n", "\n").trim()
        return if (normalized.length <= maxLen) normalized else normalized.take(maxLen) + "\n..."
    }

    private fun buildExecutionIntentToolCallRetryPrompt(
        userMessage: String
    ): String {
        return buildString {
            appendLine("系统检查到你上一轮未调用工具，但该请求属于执行型任务。")
            appendLine("请在本轮严格使用原生 tool_calls，从请求的 tools 字段中选择至少一个工具执行。")
            appendLine("不要直接输出最终文本答复。若缺失关键信息，请直接向用户提问。")
            appendLine("严禁输出 <tool_call>、<function=...>、<parameter=...> 这类伪工具标签。")
            appendLine("用户原始请求：$userMessage")
        }.trim()
    }

    private fun buildPseudoToolMarkupRetryPrompt(
        userMessage: String
    ): String {
        return buildString {
            appendLine("你上一轮把工具调用写成了文本标签，这不符合协议。")
            appendLine("下一轮必须返回标准 assistant.tool_calls。")
            appendLine("禁止输出任何 <tool_call>、<function=...>、<parameter=...>、XML、HTML 或伪 JSON 工具标签。")
            appendLine("若需要使用工具，请把 function.name 和 function.arguments 放入原生 tool_calls 字段。")
            appendLine("用户原始请求：$userMessage")
        }.trim()
    }

}
