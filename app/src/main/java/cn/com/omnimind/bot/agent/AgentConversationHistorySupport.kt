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
    data class CompactionSelection(
        val entriesToCompact: List<AgentConversationEntry>,
        val cutoffEntryDbId: Long
    )

    data class RuntimeCompactionWindow(
        val existingSummary: String?,
        val messagesToCompact: List<ChatCompletionMessage>
    )

    private const val MAX_TOOL_SUMMARY_CHARS = 240
    private const val MAX_TOOL_PREVIEW_CHARS = 800
    private const val MAX_TOOL_TERMINAL_CHARS = 1200
    private const val CONTEXT_SUMMARY_SYSTEM_PREFIX = """
以下是同一会话较早历史的压缩总结。它替代了压缩点之前的原始消息，请在后续对话中将其视为既有上下文。
如果总结与压缩点之后的新消息冲突，应以后续原始消息为准。

"""

    private val gson = Gson()

    fun buildPromptSeedFromEntries(
        entries: List<AgentConversationEntry>,
        contextSummary: String? = null,
        cutoffEntryDbId: Long? = null
    ): AgentConversationHistoryRepository.PromptSeed {
        val historyMessages = mutableListOf<ChatCompletionMessage>()
        contextSummary?.trim()?.takeIf { it.isNotEmpty() }?.let { summary ->
            historyMessages += buildContextSummarySystemMessage(summary)
        }
        historyMessages += buildPromptRelevantMessages(
            entries = entries,
            cutoffEntryDbId = cutoffEntryDbId
        )
        return AgentConversationHistoryRepository.PromptSeed(historyMessages = historyMessages)
    }

    fun buildPromptRelevantMessages(
        entries: List<AgentConversationEntry>,
        cutoffEntryDbId: Long? = null
    ): List<ChatCompletionMessage> {
        val relevantEntries = entries
            .asSequence()
            .filter(::isPromptRelevantEntry)
            .filter { entry -> cutoffEntryDbId == null || entry.id > cutoffEntryDbId }
            .toList()

        val replayMessages = mutableListOf<ChatCompletionMessage>()
        val deferredAssistantEntries = mutableListOf<AgentConversationEntry>()

        fun flushDeferredAssistantEntries() {
            if (deferredAssistantEntries.isEmpty()) return
            deferredAssistantEntries.forEach { assistantEntry ->
                replayMessages += buildAssistantPromptMessages(assistantEntry)
            }
            deferredAssistantEntries.clear()
        }

        relevantEntries.forEachIndexed { index, entry ->
            when (entry.entryType) {
                AgentConversationHistoryRepository.ENTRY_TYPE_USER_MESSAGE -> {
                    flushDeferredAssistantEntries()
                    replayMessages += buildUserPromptMessages(entry)
                }

                AgentConversationHistoryRepository.ENTRY_TYPE_ASSISTANT_MESSAGE -> {
                    if (shouldReplayAssistantContentAfterTools(relevantEntries, index, entry)) {
                        deferredAssistantEntries += entry
                    } else {
                        flushDeferredAssistantEntries()
                        replayMessages += buildAssistantPromptMessages(entry)
                    }
                }

                AgentConversationHistoryRepository.ENTRY_TYPE_TOOL_EVENT -> {
                    replayMessages += buildToolReplayMessages(entry)
                }

                else -> Unit
            }
        }

        flushDeferredAssistantEntries()
        return replayMessages
    }

    fun buildContextSummarySystemMessage(summary: String): ChatCompletionMessage {
        return ChatCompletionMessage(
            role = "system",
            content = JsonPrimitive(CONTEXT_SUMMARY_SYSTEM_PREFIX + summary.trim())
        )
    }

    fun extractContextSummaryText(message: ChatCompletionMessage): String? {
        val content = message.content as? JsonPrimitive ?: return null
        if (message.role != "system" || !content.content.startsWith(CONTEXT_SUMMARY_SYSTEM_PREFIX)) {
            return null
        }
        return content.content.removePrefix(CONTEXT_SUMMARY_SYSTEM_PREFIX).trim()
    }

    fun isContextSummarySystemMessage(message: ChatCompletionMessage): Boolean {
        val content = message.content as? JsonPrimitive ?: return false
        return message.role == "system" &&
            content.content.startsWith(CONTEXT_SUMMARY_SYSTEM_PREFIX)
    }

    fun isPromptRelevantEntry(entry: AgentConversationEntry): Boolean {
        return entry.entryType == AgentConversationHistoryRepository.ENTRY_TYPE_USER_MESSAGE ||
            entry.entryType == AgentConversationHistoryRepository.ENTRY_TYPE_ASSISTANT_MESSAGE ||
            entry.entryType == AgentConversationHistoryRepository.ENTRY_TYPE_TOOL_EVENT
    }

    fun selectEntriesToCompact(
        entries: List<AgentConversationEntry>,
        cutoffEntryDbId: Long? = null
    ): CompactionSelection? {
        val relevantEntries = entries
            .asSequence()
            .filter(::isPromptRelevantEntry)
            .filter { entry -> cutoffEntryDbId == null || entry.id > cutoffEntryDbId }
            .toList()
        val lastUserIndex = relevantEntries.indexOfLast {
            it.entryType == AgentConversationHistoryRepository.ENTRY_TYPE_USER_MESSAGE
        }
        if (lastUserIndex <= 0) {
            return null
        }
        val entriesToCompact = relevantEntries.subList(0, lastUserIndex)
        val cutoff = entriesToCompact.lastOrNull()?.id ?: return null
        return CompactionSelection(
            entriesToCompact = entriesToCompact,
            cutoffEntryDbId = cutoff
        )
    }

    fun buildRuntimeCompactionWindow(
        messages: List<ChatCompletionMessage>
    ): RuntimeCompactionWindow? {
        if (messages.isEmpty()) return null
        val leadingSystemCount = messages.takeWhile { it.role == "system" }.size
        var summaryIndex = -1
        for (index in 0 until leadingSystemCount) {
            if (isContextSummarySystemMessage(messages[index])) {
                summaryIndex = index
            }
        }
        val latestUserIndex = messages.indexOfLast { it.role == "user" }
        if (latestUserIndex == -1) return null
        val compactionStartIndex = if (summaryIndex >= 0) summaryIndex + 1 else leadingSystemCount
        if (latestUserIndex <= compactionStartIndex) {
            return null
        }
        val messagesToCompact = messages.subList(compactionStartIndex, latestUserIndex)
            .filter { it.role != "system" }
        if (messagesToCompact.isEmpty()) {
            return null
        }
        val existingSummary = if (summaryIndex >= 0) {
            extractContextSummaryText(messages[summaryIndex])
        } else {
            null
        }
        return RuntimeCompactionWindow(
            existingSummary = existingSummary,
            messagesToCompact = messagesToCompact
        )
    }

    fun rebuildMessagesWithCompactedSummary(
        messages: List<ChatCompletionMessage>,
        summary: String
    ): List<ChatCompletionMessage> {
        val preservedSystemMessages = messages
            .takeWhile { it.role == "system" }
            .filterNot(::isContextSummarySystemMessage)
        val latestUserIndex = messages.indexOfLast { it.role == "user" }
        if (latestUserIndex == -1) {
            return preservedSystemMessages + buildContextSummarySystemMessage(summary)
        }
        val rebuilt = mutableListOf<ChatCompletionMessage>()
        rebuilt += preservedSystemMessages
        rebuilt += buildContextSummarySystemMessage(summary)
        rebuilt += messages[latestUserIndex]
        messages.drop(latestUserIndex + 1)
            .firstOrNull { message -> message.role == "assistant" && !message.toolCalls.isNullOrEmpty() }
            ?.let { pendingToolCallMessage ->
                rebuilt += ChatCompletionMessage(
                    role = "assistant",
                    toolCalls = pendingToolCallMessage.toolCalls,
                    name = pendingToolCallMessage.name
                )
            }
        return rebuilt
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

    private fun shouldReplayAssistantContentAfterTools(
        entries: List<AgentConversationEntry>,
        assistantIndex: Int,
        assistantEntry: AgentConversationEntry
    ): Boolean {
        val assistantTaskId = extractAssistantReplayTaskId(assistantEntry.entryId) ?: return false
        for (index in assistantIndex + 1 until entries.size) {
            val nextEntry = entries[index]
            if (nextEntry.entryType == AgentConversationHistoryRepository.ENTRY_TYPE_USER_MESSAGE) {
                break
            }
            if (nextEntry.entryType != AgentConversationHistoryRepository.ENTRY_TYPE_TOOL_EVENT) {
                continue
            }
            if (extractToolReplayTaskId(nextEntry.entryId) == assistantTaskId) {
                return true
            }
        }
        return false
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

    private fun extractAssistantReplayTaskId(entryId: String): String? {
        val marker = "-assistant"
        val index = entryId.lastIndexOf(marker)
        if (index <= 0 || index + marker.length != entryId.length) {
            return null
        }
        return entryId.substring(0, index).takeIf { it.isNotBlank() }
    }

    private fun extractToolReplayTaskId(entryId: String): String? {
        val marker = "-tool-"
        val index = entryId.indexOf(marker)
        if (index <= 0) {
            return null
        }
        return entryId.substring(0, index).takeIf { it.isNotBlank() }
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
