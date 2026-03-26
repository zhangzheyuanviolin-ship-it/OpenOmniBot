package cn.com.omnimind.bot.agent

import android.content.Context
import cn.com.omnimind.bot.mcp.RemoteMcpDiscoveryRegistry
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.UUID

class OmniAgentExecutor(
    private val context: Context,
    private val scope: CoroutineScope,
    private val scheduleToolBridge: AgentScheduleToolBridge
) {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
        explicitNulls = false
        prettyPrint = true
    }
    private val agentModelScene = "scene.dispatch.model"

    suspend fun processUserMessage(
        userMessage: String,
        conversationHistory: List<Map<String, Any?>>,
        runtimeContextRepository: AgentRuntimeContextRepository,
        currentPackageName: String?,
        attachments: List<Map<String, Any?>>,
        conversationId: Long?,
        conversationMode: String,
        modelOverride: AgentModelOverride?,
        terminalEnvironment: Map<String, String>,
        callback: AgentCallback
    ): AgentResult {
        val agentRunId = UUID.randomUUID().toString()
        val workspaceManager = AgentWorkspaceManager(context)
        val memoryService = WorkspaceMemoryService(context, workspaceManager)
        val workspaceDescriptor = workspaceManager.buildWorkspaceDescriptor(
            conversationId = conversationId,
            agentRunId = agentRunId
        )
        val promptMemoryContext = runCatching {
            memoryService.buildPromptContext()
        }.getOrNull()
        val skillIndexService = SkillIndexService(context, workspaceManager)
        val skillLoader = SkillLoader(workspaceManager)
        val installedSkills = skillIndexService.listInstalledSkills()
        val resolvedSkills = SkillTriggerMatcher.resolveMatches(
            userMessage = userMessage,
            entries = installedSkills
        ).mapNotNull { match ->
            val compatibility = SkillCompatibilityChecker.evaluate(match.entry)
            if (!compatibility.available) {
                null
            } else {
                skillLoader.load(match.entry, match.triggerReason)
            }
        }
        val discoveredServers = RemoteMcpDiscoveryRegistry.discoverEnabledServers()
        val toolRegistry = AgentToolRegistry(
            discoveredServers = discoveredServers
        )
        val initialMessages = buildInitialMessages(
            conversationHistory = conversationHistory,
            userMessage = userMessage,
            attachments = attachments,
            workspaceDescriptor = workspaceDescriptor,
            installedSkills = installedSkills,
            skillsRootShellPath = workspaceManager.shellPathForAndroid(workspaceManager.skillsRoot())
                ?: workspaceManager.skillsRoot().absolutePath,
            skillsRootAndroidPath = workspaceManager.skillsRoot().absolutePath,
            resolvedSkills = resolvedSkills,
            memoryContext = promptMemoryContext
        )

        val llmClient = HttpAgentLlmClient(
            scope = scope,
            json = json,
            modelOverride = modelOverride
        )
        val toolRouter = AgentToolRouter(
            context = context,
            scope = scope,
            scheduleToolBridge = scheduleToolBridge,
            workspaceManager = workspaceManager
        )
        val eventAdapter = AgentEventAdapter(json)
        val orchestrator = AgentOrchestrator(
            llmClient = llmClient,
            toolRegistry = toolRegistry,
            toolRouter = toolRouter,
            eventAdapter = eventAdapter,
            model = agentModelScene
        )

        return try {
            orchestrator.run(
                AgentOrchestrator.Input(
                    callback = callback,
                    initialMessages = initialMessages,
                    executionEnv = AgentToolRouter.ExecutionEnvironment(
                        agentRunId = agentRunId,
                        userMessage = userMessage,
                        currentPackageName = currentPackageName,
                        runtimeContextRepository = runtimeContextRepository,
                        workspaceDescriptor = workspaceDescriptor,
                        resolvedSkills = resolvedSkills,
                        workspaceManager = workspaceManager,
                        workspaceMemoryService = memoryService,
                        conversationMode = conversationMode,
                        terminalEnvironment = terminalEnvironment
                    )
                )
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            callback.onError("Agent execution failed: ${e.message}")
            AgentResult.Error("Agent execution failed", e as? Exception)
        } finally {
            runCatching { toolRouter.dispose() }
        }
    }

    private fun buildInitialMessages(
        conversationHistory: List<Map<String, Any?>>,
        userMessage: String,
        attachments: List<Map<String, Any?>>,
        workspaceDescriptor: AgentWorkspaceDescriptor,
        installedSkills: List<SkillIndexEntry>,
        skillsRootShellPath: String,
        skillsRootAndroidPath: String,
        resolvedSkills: List<ResolvedSkillContext>,
        memoryContext: WorkspaceMemoryPromptContext?
    ): List<cn.com.omnimind.baselib.llm.ChatCompletionMessage> {
        val historyMessages = normalizeConversationHistory(conversationHistory).toMutableList()
        if (historyMessages.lastOrNull()?.role == "user") {
            historyMessages.removeLast()
        }
        val messages = mutableListOf<cn.com.omnimind.baselib.llm.ChatCompletionMessage>()
        messages.add(
            cn.com.omnimind.baselib.llm.ChatCompletionMessage(
                role = "system",
                content = JsonPrimitive(
                    AgentSystemPrompt.build(
                        workspace = workspaceDescriptor,
                        installedSkills = installedSkills,
                        skillsRootShellPath = skillsRootShellPath,
                        skillsRootAndroidPath = skillsRootAndroidPath,
                        resolvedSkills = resolvedSkills,
                        memoryContext = memoryContext
                    )
                )
            )
        )
        messages.addAll(historyMessages)
        messages.add(buildCurrentUserMessage(userMessage, attachments))
        return messages
    }

    private fun normalizeConversationHistory(
        conversationHistory: List<Map<String, Any?>>
    ): List<cn.com.omnimind.baselib.llm.ChatCompletionMessage> {
        if (conversationHistory.isEmpty()) return emptyList()
        return conversationHistory.mapNotNull { raw ->
            val role = raw["role"]?.toString()?.trim()?.lowercase().orEmpty()
            if (role !in setOf("system", "user", "assistant")) return@mapNotNull null
            val rawContent = raw["content"] ?: return@mapNotNull null
            val content = mapToJsonElement(rawContent)
            if (content is JsonPrimitive && content.content.isBlank()) return@mapNotNull null
            cn.com.omnimind.baselib.llm.ChatCompletionMessage(
                role = role,
                content = content
            )
        }
    }

    private fun buildCurrentUserMessage(
        userMessage: String,
        attachments: List<Map<String, Any?>>
    ): cn.com.omnimind.baselib.llm.ChatCompletionMessage {
        val normalizedAttachments = normalizeAttachments(attachments)
        val imageParts = normalizedAttachments
            .filter { it.isImage }
            .mapNotNull { attachment ->
                val imageUrl = resolveImageAttachmentUrl(attachment)
                if (imageUrl.isBlank()) {
                    null
                } else {
                    buildJsonObject {
                        put("type", "image_url")
                        put("image_url", buildJsonObject {
                            put("url", imageUrl)
                        })
                    }
                }
            }
        val rawText = userMessage
        val content = if (imageParts.isEmpty()) {
            JsonPrimitive(rawText)
        } else {
            buildJsonArray {
                if (rawText.isNotBlank()) {
                    add(
                        buildJsonObject {
                            put("type", "text")
                            put("text", rawText)
                        }
                    )
                }
                imageParts.forEach { add(it) }
            }
        }
        return cn.com.omnimind.baselib.llm.ChatCompletionMessage(
            role = "user",
            content = content
        )
    }

    private data class PromptAttachment(
        val isImage: Boolean,
        val url: String?,
        val dataUrl: String?
    )

    private fun normalizeAttachments(attachments: List<Map<String, Any?>>): List<PromptAttachment> {
        return attachments.map { item ->
            val mimeType = item["mimeType"]?.toString()?.trim()
            val explicitImage = item["isImage"]?.toString()?.toBooleanStrictOrNull()
            val isImage = explicitImage ?: mimeType.orEmpty().lowercase().startsWith("image/")
            PromptAttachment(
                isImage = isImage,
                url = item["url"]?.toString(),
                dataUrl = item["dataUrl"]?.toString()
            )
        }
    }

    private fun resolveImageAttachmentUrl(attachment: PromptAttachment): String {
        val dataUrl = attachment.dataUrl.orEmpty().trim()
        if (dataUrl.startsWith("data:")) return dataUrl

        val remoteUrl = attachment.url.orEmpty().trim()
        if (remoteUrl.startsWith("https://") || remoteUrl.startsWith("http://") || remoteUrl.startsWith("data:")) {
            return remoteUrl
        }
        return ""
    }

    private fun mapToJsonElement(value: Any?): JsonElement {
        return when (value) {
            null -> JsonNull
            is JsonElement -> value
            is Map<*, *> -> JsonObject(
                value.entries.associate { (key, item) ->
                    key.toString() to mapToJsonElement(item)
                }
            )
            is List<*> -> JsonArray(value.map { mapToJsonElement(it) })
            is Boolean -> JsonPrimitive(value)
            is Number -> JsonPrimitive(value)
            else -> JsonPrimitive(value.toString())
        }
    }
}
