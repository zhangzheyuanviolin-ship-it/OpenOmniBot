package cn.com.omnimind.bot.agent

import cn.com.omnimind.assists.controller.http.HttpController
import cn.com.omnimind.baselib.i18n.AppLocaleManager
import cn.com.omnimind.baselib.llm.AssistantToolCall
import cn.com.omnimind.baselib.llm.ChatCompletionMessage
import cn.com.omnimind.baselib.util.OmniLog
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import okhttp3.Response
import okhttp3.sse.EventSource
import okhttp3.sse.EventSourceListener
import java.util.concurrent.atomic.AtomicBoolean

open class AgentConversationContextCompactor(
    private val historyRepository: AgentConversationHistoryRepository,
    private val json: Json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
        explicitNulls = false
    }
) {
    companion object {
        const val DEFAULT_PROMPT_TOKEN_THRESHOLD = 128_000
        private const val CHAT_COMPACTOR_SCENE = "scene.compactor.context.chat"
        private const val TAG = "AgentConversationContextCompactor"
        private val EPHEMERAL_CACHE_CONTROL = mapOf("type" to "ephemeral")

        private fun compactionRequestPrompt(): String {
            return when (AppLocaleManager.currentPromptLocale()) {
                cn.com.omnimind.baselib.i18n.PromptLocale.ZH_CN -> """
                    /no_think
                    你是一个用户与Agent对话上下文压缩器。你的职责是把一段多轮聊天历史压缩为一份可持续累积的上下文总结，供后续对话继续参考。

                    # 要求：
                    1. 只输出纯文本，不要 JSON，不要 Markdown 代码块。
                    2. 使用固定结构，保留明确的小节标题。
                    3. 保留长期目标、用户偏好、约束条件、关键文件路径、参数、工具结果、未完成任务、待确认点。
                    4. 去掉冗余寒暄、重复措辞、无关中间推理，但不能丢失会影响后续执行的重要事实。
                    5. 如果系统消息里已经给出旧的累计总结，要将其与新历史整合为一份新的累计总结，而不是简单拼接。
                    6. 不要编造不存在的事实；不确定时明确写“待确认”。

                    # 输出格式：
                    ## 用户目标与约束
                    - ...

                    ## 已确认事实与已完成结果
                    - ...

                    ## 关键上下文与参数
                    - ...

                    ## 未完成事项与下一步
                    - ...
                """.trimIndent()
                cn.com.omnimind.baselib.i18n.PromptLocale.EN_US -> """
                    /no_think
                    You are a conversation context compactor for a user-agent dialogue. Your job is to compress a multi-turn chat history into an accumulated context summary that can be carried forward into later turns.

                    # Requirements:
                    1. Output plain text only. Do not output JSON or Markdown code fences.
                    2. Use a fixed structure and keep clear section headings.
                    3. Preserve long-term goals, user preferences, constraints, important file paths, parameters, tool results, unfinished work, and items still awaiting confirmation.
                    4. Remove redundant pleasantries, repeated phrasing, and irrelevant intermediate reasoning, but do not drop facts that matter for future execution.
                    5. If the system message already contains an accumulated summary, merge it with the new raw history into one updated accumulated summary instead of concatenating blindly.
                    6. Do not invent facts. When something is uncertain, mark it as pending confirmation.

                    # Output format:
                    ## User Goals And Constraints
                    - ...

                    ## Confirmed Facts And Completed Results
                    - ...

                    ## Key Context And Parameters
                    - ...

                    ## Open Items And Next Steps
                    - ...
                """.trimIndent()
            }
        }

        private fun existingSummaryPromptPrefix(): String {
            return when (AppLocaleManager.currentPromptLocale()) {
                cn.com.omnimind.baselib.i18n.PromptLocale.ZH_CN ->
                    "以下是之前已经累计好的历史总结，请将它与后续原始历史合并为新的累计总结："
                cn.com.omnimind.baselib.i18n.PromptLocale.EN_US ->
                    "Below is the previously accumulated summary. Merge it with the following raw history into a new accumulated summary:"
            }
        }

        private fun finalUserPrompt(): String {
            return when (AppLocaleManager.currentPromptLocale()) {
                cn.com.omnimind.baselib.i18n.PromptLocale.ZH_CN ->
                    "请把以上历史压缩为新的累计总结。"
                cn.com.omnimind.baselib.i18n.PromptLocale.EN_US ->
                    "Compress the history above into a new accumulated summary."
            }
        }

        internal fun buildCompactionRequestMessages(
            existingSummary: String?,
            messagesToCompact: List<ChatCompletionMessage>
        ): List<Map<String, Any>> {
            val requestMessages = mutableListOf<Map<String, Any>>()
            requestMessages += mapOf(
                "role" to "system",
                "content" to buildTextContentBlocks(
                    text = compactionRequestPrompt().trim(),
                    cacheControl = EPHEMERAL_CACHE_CONTROL
                )
            )
            existingSummary?.trim()?.takeIf { it.isNotEmpty() }?.let { summary ->
                requestMessages += mapOf(
                    "role" to "system",
                    "content" to (existingSummaryPromptPrefix().trim() + "\n\n" + summary)
                )
            }
            requestMessages += messagesToCompact.map(::toTransportMessage)
            requestMessages += mapOf(
                "role" to "user",
                "content" to finalUserPrompt()
            )
            return requestMessages
        }

        private fun buildTextContentBlocks(
            text: String,
            cacheControl: Map<String, String>? = null
        ): List<Map<String, Any>> {
            val block = linkedMapOf<String, Any>(
                "type" to "text",
                "text" to text
            )
            if (cacheControl != null) {
                block["cache_control"] = cacheControl
            }
            return listOf(block)
        }

        private fun toTransportMessage(message: ChatCompletionMessage): Map<String, Any> {
            val payload = linkedMapOf<String, Any>(
                "role" to message.role
            )
            val content = message.content?.let(::jsonElementToTransportValue)
            if (content != null) {
                payload["content"] = content
            }
            message.toolCalls?.takeIf { it.isNotEmpty() }?.let { toolCalls ->
                payload["tool_calls"] = toolCalls.map(::toolCallToTransportMap)
            }
            message.toolCallId?.takeIf { it.isNotBlank() }?.let { toolCallId ->
                payload["tool_call_id"] = toolCallId
            }
            message.name?.takeIf { it.isNotBlank() }?.let { name ->
                payload["name"] = name
            }
            return payload
        }

        private fun toolCallToTransportMap(toolCall: AssistantToolCall): Map<String, Any> {
            return linkedMapOf(
                "id" to toolCall.id,
                "type" to toolCall.type,
                "function" to linkedMapOf(
                    "name" to toolCall.function.name,
                    "arguments" to toolCall.function.arguments
                )
            )
        }

        private fun jsonElementToTransportValue(element: JsonElement): Any? {
            return when (element) {
                is JsonPrimitive -> {
                    element.contentOrNull
                        ?: element.booleanOrNull
                        ?: element.toString()
                }

                is JsonArray -> element.mapNotNull(::jsonElementToTransportValue)
                is JsonObject -> element.entries.associate { (key, value) ->
                    key to (jsonElementToTransportValue(value) ?: "")
                }
            }
        }
    }

    open suspend fun resolvePromptTokenThreshold(conversationId: Long?): Int {
        if (conversationId == null || conversationId <= 0L) {
            return DEFAULT_PROMPT_TOKEN_THRESHOLD
        }
        val conversation = historyRepository.getConversation(conversationId)
        val storedThreshold = conversation?.promptTokenThreshold ?: DEFAULT_PROMPT_TOKEN_THRESHOLD
        return storedThreshold.coerceAtLeast(1)
    }

    open suspend fun compactIfNeeded(
        conversationId: Long?,
        conversationMode: String,
        promptTokens: Int?,
        messages: List<ChatCompletionMessage>,
        promptTokenThresholdOverride: Int? = null,
        callback: AgentCallback? = null
    ): List<ChatCompletionMessage> {
        if (conversationId == null || conversationId <= 0L) {
            return messages
        }
        val normalizedPromptTokens = promptTokens ?: return messages
        val promptTokenThreshold = promptTokenThresholdOverride?.coerceAtLeast(1)
            ?: resolvePromptTokenThreshold(conversationId)
        historyRepository.updatePromptTokenUsage(
            conversationId = conversationId,
            promptTokens = normalizedPromptTokens,
            threshold = promptTokenThreshold
        )
        if (normalizedPromptTokens <= promptTokenThreshold) {
            return messages
        }
        val candidate = historyRepository.getContextCompactionCandidate(
            conversationId = conversationId,
            conversationMode = conversationMode
        ) ?: return messages
        val runtimeWindow = AgentConversationHistorySupport.buildRuntimeCompactionWindow(messages)
            ?: return messages

        callback?.onContextCompactionStateChanged(
            isCompacting = true,
            latestPromptTokens = normalizedPromptTokens,
            promptTokenThreshold = promptTokenThreshold
        )
        try {
            return runCatching {
                val requestMessages = buildCompactionRequestMessages(
                    existingSummary = runtimeWindow.existingSummary
                        ?: candidate.conversation.contextSummary,
                    messagesToCompact = runtimeWindow.messagesToCompact
                )
                val summary = requestCompactedSummary(requestMessages)
                if (summary.isBlank()) {
                    OmniLog.w(TAG, "conversation=$conversationId compaction returned blank summary")
                    messages
                } else {
                    historyRepository.updateContextSummary(
                        conversationId = conversationId,
                        summary = summary,
                        cutoffEntryDbId = candidate.cutoffEntryDbId
                    )
                    AgentConversationHistorySupport.rebuildMessagesWithCompactedSummary(
                        messages = messages,
                        summary = summary
                    )
                }
            }.getOrElse { error ->
                OmniLog.w(
                    TAG,
                    "conversation=$conversationId compaction failed: ${error.message}"
                )
                messages
            }
        } finally {
            callback?.onContextCompactionStateChanged(
                isCompacting = false,
                latestPromptTokens = normalizedPromptTokens,
                promptTokenThreshold = promptTokenThreshold
            )
        }
    }

    private suspend fun requestCompactedSummary(
        messages: List<Map<String, Any>>
    ): String = withContext(Dispatchers.IO) {
        val completed = AtomicBoolean(false)
        val result = CompletableDeferred<String>()
        val accumulator = AgentLlmStreamAccumulator(json)
        var eventSource: EventSource? = null

        fun completeStream(source: EventSource? = null) {
            if (!completed.compareAndSet(false, true)) return
            runCatching {
                accumulator.buildTurn().message.contentText().trim()
            }.onSuccess { summary ->
                result.complete(summary)
            }.onFailure { error ->
                result.completeExceptionally(error)
            }
            source?.cancel()
        }

        val listener = object : EventSourceListener() {
            override fun onEvent(
                eventSource: EventSource,
                id: String?,
                type: String?,
                data: String
            ) {
                if (completed.get()) return
                runCatching {
                    val done = accumulator.consume(data)
                    if (done) {
                        completeStream(eventSource)
                    }
                }.onFailure { error ->
                    if (completed.compareAndSet(false, true)) {
                        result.completeExceptionally(error)
                    }
                }
            }

            override fun onClosed(eventSource: EventSource) {
                completeStream(eventSource)
            }

            override fun onFailure(eventSource: EventSource, t: Throwable?, response: Response?) {
                if (!completed.compareAndSet(false, true)) return
                val reason = buildString {
                    append(t?.message?.trim().orEmpty())
                    val responseBody = runCatching { response?.body?.string() }.getOrNull()
                        ?.trim()
                        .orEmpty()
                    if (responseBody.isNotEmpty()) {
                        if (isNotEmpty()) append(" ")
                        append(responseBody.take(500))
                    }
                }.trim().ifEmpty { "unknown compaction stream failure" }
                result.completeExceptionally(IllegalStateException(reason))
            }
        }

        try {
            eventSource = HttpController.postLLMStreamRequestWithContextAsFlow(
                model = CHAT_COMPACTOR_SCENE,
                messages = messages,
                event = listener,
                enableThinking = false
            )
            result.await()
        } finally {
            eventSource?.cancel()
        }
    }

}
