package cn.com.omnimind.bot.agent

import cn.com.omnimind.assists.controller.http.HttpController
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
        private const val COMPACTION_REQUEST_PROMPT = """
你是一个用户与Agent对话上下文压缩器。你的职责是把一段多轮聊天历史压缩为一份可持续累积的上下文总结，供后续对话继续参考。\n\n
# 要求：\n
1. 只输出纯文本，不要 JSON，不要 Markdown 代码块。\n
3. 保留长期目标、用户偏好、约束条件、关键文件路径、参数、工具结果、未完成任务、待确认点。\n
4. 去掉冗余寒暄、重复措辞、无关中间推理，但不能丢失会影响后续执行的重要事实。\n
5. 如果系统消息里已经给出旧的累计总结，要将其与新历史整合为一份新的累计总结，而不是简单拼接。\n
6. 不要编造不存在的事实；不确定时明确写“待确认”。\n
# 输出格式：\n
## 用户目标与约束 \n- ...\n\n## 已确认事实与已完成结果\n- ...\n\n## 关键上下文与参数\n- ...\n\n## 未完成事项与下一步\n- ...\n

"""
        private const val EXISTING_SUMMARY_PROMPT_PREFIX = """
以下是之前已经累计好的历史总结，请将它与后续原始历史合并为新的累计总结：

"""
        private const val FINAL_USER_PROMPT = "请把以上历史压缩为新的累计总结。"
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
        callback: AgentCallback? = null
    ): List<ChatCompletionMessage> {
        if (conversationId == null || conversationId <= 0L) {
            return messages
        }
        val normalizedPromptTokens = promptTokens ?: return messages
        val promptTokenThreshold = resolvePromptTokenThreshold(conversationId)
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

    private fun buildCompactionRequestMessages(
        existingSummary: String?,
        messagesToCompact: List<ChatCompletionMessage>
    ): List<Map<String, Any>> {
        val requestMessages = mutableListOf<Map<String, Any>>()
        requestMessages += mapOf(
            "role" to "system",
            "content" to COMPACTION_REQUEST_PROMPT.trim()
        )
        existingSummary?.trim()?.takeIf { it.isNotEmpty() }?.let { summary ->
            requestMessages += mapOf(
                "role" to "system",
                "content" to (EXISTING_SUMMARY_PROMPT_PREFIX.trim() + "\n\n" + summary)
            )
        }
        requestMessages += messagesToCompact.map(::toTransportMessage)
        requestMessages += mapOf(
            "role" to "user",
            "content" to FINAL_USER_PROMPT
        )
        return requestMessages
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
                event = listener
            )
            result.await()
        } finally {
            eventSource?.cancel()
        }
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
