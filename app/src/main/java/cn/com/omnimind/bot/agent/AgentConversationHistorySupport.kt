package cn.com.omnimind.bot.agent

import cn.com.omnimind.baselib.database.AgentConversationEntry
import cn.com.omnimind.baselib.llm.AssistantToolCall
import cn.com.omnimind.baselib.llm.AssistantToolCallFunction
import cn.com.omnimind.baselib.llm.ChatCompletionMessage
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

internal object AgentConversationHistorySupport {
    private const val MAX_PROMPT_RELEVANT_ENTRIES = 20
    private const val MAX_TOOL_SUMMARY_CHARS = 240
    private const val MAX_TOOL_PREVIEW_CHARS = 800
    private const val MAX_TOOL_TERMINAL_CHARS = 1200

    private val gson = Gson()

    fun buildPromptSeedFromEntries(
        entries: List<AgentConversationEntry>
    ): AgentConversationHistoryRepository.PromptSeed {
        val relevantEntries = entries
            .filter {
                it.entryType == AgentConversationHistoryRepository.ENTRY_TYPE_USER_MESSAGE ||
                    it.entryType == AgentConversationHistoryRepository.ENTRY_TYPE_ASSISTANT_MESSAGE ||
                    it.entryType == AgentConversationHistoryRepository.ENTRY_TYPE_TOOL_EVENT
            }
            .takeLast(MAX_PROMPT_RELEVANT_ENTRIES)

        val historyMessages = relevantEntries.flatMap { entry ->
            when (entry.entryType) {
                AgentConversationHistoryRepository.ENTRY_TYPE_USER_MESSAGE -> {
                    buildUserPromptMessages(entry)
                }

                AgentConversationHistoryRepository.ENTRY_TYPE_ASSISTANT_MESSAGE -> {
                    buildAssistantPromptMessages(entry)
                }

                AgentConversationHistoryRepository.ENTRY_TYPE_TOOL_EVENT -> {
                    buildToolReplayMessages(entry)
                }

                else -> emptyList()
            }
        }
        return AgentConversationHistoryRepository.PromptSeed(historyMessages = historyMessages)
    }

    fun normalizeInterruptedEntries(
        entries: List<AgentConversationEntry>
    ): List<AgentConversationEntry> {
        if (entries.isEmpty()) return entries
        return entries.map { entry ->
            if (
                entry.entryType != AgentConversationHistoryRepository.ENTRY_TYPE_TOOL_EVENT ||
                entry.status != AgentConversationHistoryRepository.STATUS_RUNNING
            ) {
                entry
            } else {
                val mergedPayload = mergeToolPayload(
                    existing = readMap(entry.payloadJson),
                    incoming = mapOf(
                        "status" to AgentConversationHistoryRepository.STATUS_INTERRUPTED,
                        "summary" to entry.summary.ifBlank { "工具调用已中断" }
                    ),
                    fallbackStatus = AgentConversationHistoryRepository.STATUS_INTERRUPTED,
                    fallbackSummary = entry.summary.ifBlank { "工具调用已中断" }
                )
                entry.copy(
                    status = AgentConversationHistoryRepository.STATUS_INTERRUPTED,
                    summary = mergedPayload["summary"]?.toString().orEmpty().ifBlank {
                        "工具调用已中断"
                    },
                    payloadJson = gson.toJson(mergedPayload),
                    updatedAt = entry.updatedAt
                )
            }
        }
    }

    fun mergeToolPayload(
        existing: Map<String, Any?>,
        incoming: Map<String, Any?>,
        fallbackStatus: String,
        fallbackSummary: String
    ): Map<String, Any?> {
        fun text(source: Map<String, Any?>, key: String): String {
            return source[key]?.toString()?.trim().orEmpty()
        }

        fun chooseText(key: String, fallback: String = ""): String {
            return text(incoming, key).ifEmpty {
                text(existing, key).ifEmpty { fallback }
            }
        }

        fun chooseAny(key: String): Any? {
            return incoming[key] ?: existing[key]
        }

        val toolType = chooseText("toolType", "builtin")
        val existingTerminalOutput = text(existing, "terminalOutput")
        val terminalOutputDelta = text(incoming, "terminalOutputDelta")
        val terminalOutput = if (toolType == "terminal") {
            text(incoming, "terminalOutput").ifEmpty {
                if (terminalOutputDelta.isNotEmpty()) {
                    existingTerminalOutput + terminalOutputDelta
                } else {
                    existingTerminalOutput
                }
            }
        } else {
            chooseText("terminalOutput")
        }

        return linkedMapOf<String, Any?>(
            "taskId" to chooseAny("taskId"),
            "toolName" to chooseText("toolName"),
            "displayName" to chooseText("displayName"),
            "toolType" to toolType,
            "serverName" to chooseAny("serverName"),
            "status" to chooseText("status", fallbackStatus),
            "summary" to chooseText("summary", fallbackSummary),
            "progress" to chooseText("progress"),
            "args" to chooseText("args"),
            "argsJson" to chooseText("argsJson"),
            "resultPreviewJson" to chooseText("resultPreviewJson"),
            "rawResultJson" to chooseText("rawResultJson"),
            "terminalOutput" to terminalOutput,
            "terminalOutputDelta" to terminalOutputDelta,
            "terminalSessionId" to chooseAny("terminalSessionId"),
            "terminalStreamState" to chooseText("terminalStreamState"),
            "workspaceId" to chooseAny("workspaceId"),
            "artifacts" to toListOfStringAnyMap(incoming["artifacts"]).ifEmpty {
                toListOfStringAnyMap(existing["artifacts"])
            },
            "actions" to toListOfStringAnyMap(incoming["actions"]).ifEmpty {
                toListOfStringAnyMap(existing["actions"])
            },
            "success" to (incoming["success"] ?: existing["success"] ?: (fallbackStatus == AgentConversationHistoryRepository.STATUS_SUCCESS))
        )
    }

    private fun buildUserPromptMessages(entry: AgentConversationEntry): List<ChatCompletionMessage> {
        val payload = readMap(entry.payloadJson)
        val content = buildPromptContentFromMessagePayload(payload) ?: return emptyList()
        if (content.isBlankJsonPrimitive()) return emptyList()
        return listOf(
            ChatCompletionMessage(
                role = "user",
                content = content
            )
        )
    }

    private fun buildAssistantPromptMessages(entry: AgentConversationEntry): List<ChatCompletionMessage> {
        val payload = readMap(entry.payloadJson)
        val content = buildPromptContentFromMessagePayload(payload) ?: return emptyList()
        if (content.isBlankJsonPrimitive()) return emptyList()
        return listOf(
            ChatCompletionMessage(
                role = "assistant",
                content = content
            )
        )
    }

    private fun buildToolReplayMessages(entry: AgentConversationEntry): List<ChatCompletionMessage> {
        val payload = readMap(entry.payloadJson)
        val toolName = payload["toolName"]?.toString()?.trim().orEmpty()
        if (toolName.isEmpty()) return emptyList()

        val toolCallId = "restored_${entry.entryId}"
        val argsJson = payload["argsJson"]?.toString()?.trim()?.ifEmpty { null } ?: "{}"
        val assistantMessage = ChatCompletionMessage(
            role = "assistant",
            toolCalls = listOf(
                AssistantToolCall(
                    id = toolCallId,
                    function = AssistantToolCallFunction(
                        name = toolName,
                        arguments = argsJson
                    )
                )
            )
        )
        val toolMessage = ChatCompletionMessage(
            role = "tool",
            toolCallId = toolCallId,
            content = JsonPrimitive(buildToolSummaryContent(entry, payload))
        )
        return listOf(assistantMessage, toolMessage)
    }

    private fun buildToolSummaryContent(
        entry: AgentConversationEntry,
        payload: Map<String, Any?>
    ): String {
        val preview = parseJsonMap(payload["resultPreviewJson"]?.toString().orEmpty())
        val content = linkedMapOf<String, Any?>(
            "toolName" to payload["toolName"]?.toString().orEmpty(),
            "displayName" to payload["displayName"]?.toString().orEmpty(),
            "toolType" to payload["toolType"]?.toString().orEmpty().ifEmpty { "builtin" },
            "status" to entry.status,
            "success" to parseBoolean(payload["success"], default = entry.status == AgentConversationHistoryRepository.STATUS_SUCCESS),
            "summary" to trimText(
                payload["summary"]?.toString()?.trim().orEmpty().ifEmpty { entry.summary.trim() },
                MAX_TOOL_SUMMARY_CHARS
            )
        )
        payload["serverName"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let {
            content["serverName"] = it
        }

        listOf("message", "question", "taskId", "goal").forEach { key ->
            preview[key]?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let { value ->
                content[key] = trimText(value, MAX_TOOL_PREVIEW_CHARS)
            }
        }
        listOf("missing", "missingFields").forEach { key ->
            val values = toStringList(preview[key])
            if (values.isNotEmpty()) {
                content[key] = values
            }
        }

        payload["resultPreviewJson"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let { raw ->
            content["previewJson"] = trimText(raw, MAX_TOOL_PREVIEW_CHARS)
        }
        payload["terminalOutput"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let { raw ->
            content["terminalOutput"] = trimText(raw, MAX_TOOL_TERMINAL_CHARS)
        }
        payload["terminalStreamState"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let {
            content["terminalStreamState"] = it
        }
        payload["terminalSessionId"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let {
            content["terminalSessionId"] = it
        }

        return gson.toJson(content)
    }

    private fun buildPromptContentFromMessagePayload(
        payload: Map<String, Any?>
    ): JsonElement? {
        val content = toStringAnyMap(payload["content"])
        val text = content["text"]?.toString().orEmpty()
        val attachments = toListOfStringAnyMap(content["attachments"])
        val imageBlocks = attachments.mapNotNull { attachment ->
            val imageUrl = resolveImageAttachmentUrl(attachment)
            if (imageUrl.isBlank()) {
                null
            } else {
                JsonObject(
                    mapOf(
                        "type" to JsonPrimitive("image_url"),
                        "image_url" to JsonObject(
                            mapOf("url" to JsonPrimitive(imageUrl))
                        )
                    )
                )
            }
        }
        if (imageBlocks.isEmpty()) {
            return JsonPrimitive(text)
        }
        val blocks = mutableListOf<JsonElement>()
        if (text.isNotBlank()) {
            blocks += JsonObject(
                mapOf(
                    "type" to JsonPrimitive("text"),
                    "text" to JsonPrimitive(text)
                )
            )
        }
        blocks += imageBlocks
        return JsonArray(blocks)
    }

    private fun resolveImageAttachmentUrl(attachment: Map<String, Any?>): String {
        val dataUrl = attachment["dataUrl"]?.toString()?.trim().orEmpty()
        if (dataUrl.startsWith("data:")) return dataUrl
        val remoteUrl = attachment["url"]?.toString()?.trim().orEmpty()
        return if (
            remoteUrl.startsWith("https://") ||
            remoteUrl.startsWith("http://") ||
            remoteUrl.startsWith("data:")
        ) {
            remoteUrl
        } else {
            ""
        }
    }

    private fun parseJsonMap(json: String): Map<String, Any?> {
        if (json.isBlank()) return emptyMap()
        return runCatching {
            gson.fromJson<Map<String, Any?>>(
                json,
                object : TypeToken<Map<String, Any?>>() {}.type
            )
        }.getOrElse { emptyMap() }
    }

    private fun readMap(json: String): Map<String, Any?> {
        return parseJsonMap(json)
    }

    private fun toStringAnyMap(value: Any?): Map<String, Any?> {
        if (value !is Map<*, *>) return emptyMap()
        return value.entries.associate { (key, rawValue) ->
            key.toString() to rawValue
        }
    }

    private fun toListOfStringAnyMap(value: Any?): List<Map<String, Any?>> {
        if (value !is List<*>) return emptyList()
        return value.mapNotNull { item -> item?.let(::toStringAnyMap).takeIf { !it.isNullOrEmpty() } }
    }

    private fun toStringList(value: Any?): List<String> {
        if (value !is List<*>) return emptyList()
        return value.mapNotNull { item ->
            item?.toString()?.trim()?.takeIf { it.isNotEmpty() }
        }
    }

    private fun trimText(value: String, maxChars: Int): String {
        val normalized = value.trim()
        return if (normalized.length <= maxChars) normalized else normalized.take(maxChars) + "..."
    }

    private fun parseBoolean(value: Any?, default: Boolean): Boolean {
        return when (value) {
            is Boolean -> value
            is String -> value.equals("true", ignoreCase = true)
            else -> default
        }
    }

    private fun JsonElement.isBlankJsonPrimitive(): Boolean {
        return this is JsonPrimitive && this.isString && this.content.isBlank()
    }
}
