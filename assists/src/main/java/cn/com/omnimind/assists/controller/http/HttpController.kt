package cn.com.omnimind.assists.controller.http

import cn.com.omnimind.assists.api.bean.TaskParams
import cn.com.omnimind.assists.task.vlmserver.SceneChatCompletionResponse
import cn.com.omnimind.assists.task.vlmserver.SceneChatCompletionStreamHandle
import cn.com.omnimind.assists.api.bean.ResultBean
import cn.com.omnimind.baselib.llm.AssistantToolCall
import cn.com.omnimind.baselib.llm.AssistantToolCallFunction
import cn.com.omnimind.baselib.llm.ChatCompletionMessage
import cn.com.omnimind.baselib.llm.ChatCompletionRequest
import cn.com.omnimind.baselib.llm.ChatCompletionStreamOptions
import cn.com.omnimind.baselib.llm.ModelProviderConfig
import cn.com.omnimind.baselib.llm.ModelProviderConfigStore
import cn.com.omnimind.baselib.util.OmniLog
import cn.com.omnimind.baselib.llm.ModelSceneRegistry
import cn.com.omnimind.baselib.llm.ProviderModelOption
import cn.com.omnimind.baselib.llm.SceneModelBindingStore
import cn.com.omnimind.omniintelligence.models.AgentRequest.Payload
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonArray as KxJsonArray
import kotlinx.serialization.json.JsonObject as KxJsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.sse.EventSource
import okhttp3.sse.EventSourceListener
import okhttp3.sse.EventSources
import org.json.JSONObject
import org.json.JSONArray

/**
 * AI HTTP 控制器，用于处理 LLM 和 VLM 相关的网络请求
 */
object HttpController {
    private const val TAG = "HttpController"
    private const val RESPONSE_LOG_CHUNK_SIZE = 3500
    private const val ROUTE_CUSTOM_OPENAI_COMPAT = "custom_openai_compat"

    private data class ResolvedSceneRequest(
        val requestedModel: String,
        val resolvedModel: String,
        val sceneProfile: ModelSceneRegistry.SceneRuntimeProfile?,
        val effectiveTransport: ModelSceneRegistry.SceneTransport,
        val responseParser: ModelSceneRegistry.ResponseParser,
        val apiBase: String?,
        val apiKey: String?,
        val providerProfileId: String?,
        val providerProfileName: String?,
        val routeTag: String?,
        val customApiBaseApplied: Boolean,
        val bindingApplied: Boolean,
        val bindingProfileMissing: Boolean,
        val overrideApplied: Boolean,
        val overrideModel: String?
    )

    data class ModelAvailabilityCheckResult(
        val available: Boolean,
        val code: Int? = null,
        val message: String
    )

    private val openClawStreamClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(60, java.util.concurrent.TimeUnit.SECONDS)
            .readTimeout(0, java.util.concurrent.TimeUnit.SECONDS)
            .writeTimeout(60, java.util.concurrent.TimeUnit.SECONDS)
            .build()
    }

    private val completionJson = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
        explicitNulls = false
    }

    private fun createLoggingEventListener(
        label: String,
        delegate: EventSourceListener
    ): EventSourceListener {
        val fullContent = StringBuilder()
        return object : EventSourceListener() {
            override fun onOpen(eventSource: EventSource, response: okhttp3.Response) {
                delegate.onOpen(eventSource, response)
            }

            override fun onEvent(
                eventSource: EventSource,
                id: String?,
                type: String?,
                data: String
            ) {
                appendStreamLogChunk(fullContent, data)
                delegate.onEvent(eventSource, id, type, data)
            }

            override fun onClosed(eventSource: EventSource) {
                if (fullContent.isNotEmpty()) {
                    logResponseBody(label, fullContent.toString())
                }
                delegate.onClosed(eventSource)
            }

            override fun onFailure(
                eventSource: EventSource,
                t: Throwable?,
                response: okhttp3.Response?
            ) {
                if (fullContent.isNotEmpty()) {
                    logResponseBody("$label (partial)", fullContent.toString())
                }
                delegate.onFailure(eventSource, t, response)
            }
        }
    }

    private fun appendStreamLogChunk(buffer: StringBuilder, data: String) {
        val chunk = extractStreamLogChunk(data)
        if (chunk.isBlank()) return
        buffer.append(chunk)
    }

    private fun extractStreamLogChunk(data: String): String {
        val trimmed = data.trim()
        if (trimmed.isEmpty() || trimmed == "[DONE]") {
            return ""
        }

        return runCatching {
            val json = JSONObject(trimmed)
            when {
                json.has("text") -> json.optString("text")
                json.has("message") && json.opt("message") is String -> json.optString("message")
                json.has("choices") -> {
                    val firstChoice = json.optJSONArray("choices")?.optJSONObject(0)
                    val delta = firstChoice?.optJSONObject("delta")
                    val message = firstChoice?.optJSONObject("message")

                    when {
                        delta != null -> {
                            extractTextPayload(delta.opt("content")).ifBlank {
                                listOf(
                                    delta.opt("reasoning_content"),
                                    delta.opt("reasoning"),
                                    delta.opt("thinking")
                                )
                                    .asSequence()
                                    .map { extractTextPayload(it) }
                                    .firstOrNull { it.isNotBlank() }
                                    .orEmpty()
                            }
                        }
                        message != null -> {
                            extractTextPayload(message.opt("content")).ifBlank {
                                listOf(
                                    message.opt("reasoning_content"),
                                    message.opt("reasoning"),
                                    message.opt("thinking")
                                )
                                    .asSequence()
                                    .map { extractTextPayload(it) }
                                    .firstOrNull { it.isNotBlank() }
                                    .orEmpty()
                            }
                        }
                        else -> trimmed
                    }
                }
                else -> trimmed
            }
        }.getOrElse { trimmed }
    }

    private fun logResponseBody(label: String, body: String?) {
        val normalized = body?.trim()?.takeIf { it.isNotEmpty() } ?: "<empty>"
        val chunks = normalized.chunked(RESPONSE_LOG_CHUNK_SIZE)
        chunks.forEachIndexed { index, chunk ->
            val suffix = if (chunks.size == 1) "" else " (${index + 1}/${chunks.size})"
            OmniLog.i(TAG, "$label Response Body$suffix: $chunk")
        }
    }

    private fun logSceneProfile(resolved: ResolvedSceneRequest) {
        val profile = resolved.sceneProfile ?: return
        OmniLog.i(
            TAG,
            "scene_profile scene=${profile.sceneId} model=${resolved.resolvedModel} transport=${resolved.effectiveTransport.wireValue} parser=${resolved.responseParser.wireValue} source=${profile.modelSource.wireValue} config_source=${profile.configSource.wireValue} override_group=${profile.overrideGroup.orEmpty()} custom_api_base=${resolved.customApiBaseApplied} binding_applied=${resolved.bindingApplied} binding_profile=${resolved.providerProfileId.orEmpty()} binding_profile_missing=${resolved.bindingProfileMissing} override_applied=${resolved.overrideApplied} override_model=${resolved.overrideModel.orEmpty()}"
        )
    }

    private fun resolveSceneRequest(
        modelOrScene: String,
        explicitApiBase: String? = null,
        explicitApiKey: String? = null,
        explicitModel: String? = null,
        @Suppress("UNUSED_PARAMETER") defaultTransport: ModelSceneRegistry.SceneTransport = ModelSceneRegistry.SceneTransport.OPENAI_COMPATIBLE
    ): ResolvedSceneRequest {
        val requestedModel = modelOrScene.trim()
        val sceneProfile = if (ModelSceneRegistry.isSceneId(requestedModel)) {
            ModelSceneRegistry.getRuntimeProfile(requestedModel)
        } else {
            null
        }
        val defaultResolvedModel = when {
            sceneProfile != null -> sceneProfile.model
            requestedModel.startsWith("scene.") -> ModelSceneRegistry.resolveModel(requestedModel)
            else -> requestedModel
        }

        val explicitBase = explicitApiBase?.let(::normalizeApiBase)
        val explicitKey = explicitApiKey?.trim()?.takeIf { it.isNotEmpty() }
        val explicitResolvedModel = explicitModel?.trim()?.takeIf { it.isNotEmpty() }
        val providerConfig = if (explicitBase == null) {
            ModelProviderConfigStore.getConfig()
        } else {
            ModelProviderConfig(baseUrl = explicitBase, apiKey = explicitKey.orEmpty(), source = "explicit")
        }
        val sceneBinding = sceneProfile?.sceneId?.let(SceneModelBindingStore::getBinding)
        val boundProfile = sceneBinding?.providerProfileId?.let(ModelProviderConfigStore::getProfile)
        val bindingApplied =
            explicitBase == null &&
                explicitResolvedModel == null &&
                sceneBinding != null &&
                boundProfile?.isConfigured() == true
        val bindingProfileMissing =
            explicitBase == null &&
                explicitResolvedModel == null &&
                sceneBinding != null &&
                boundProfile == null
        val overrideModel = when {
            explicitResolvedModel != null -> explicitResolvedModel
            bindingApplied -> sceneBinding?.modelId
            else -> null
        }
        val overrideApplied =
            explicitBase != null || explicitResolvedModel != null || bindingApplied

        val providerBase = when {
            explicitBase != null -> explicitBase
            bindingApplied -> boundProfile?.baseUrl
            providerConfig.isConfigured() -> providerConfig.baseUrl
            else -> null
        }
        val providerKey = when {
            explicitBase != null -> explicitKey
            bindingApplied -> boundProfile?.apiKey?.takeIf { it.isNotBlank() }
            providerBase != null -> providerConfig.apiKey.takeIf { it.isNotBlank() }
            else -> null
        }
        val effectiveTransport = sceneProfile?.transport ?: defaultTransport
        val responseParser = sceneProfile?.responseParser ?: when (effectiveTransport) {
            ModelSceneRegistry.SceneTransport.OPENAI_COMPATIBLE,
            ModelSceneRegistry.SceneTransport.VLM_CHAT,
            ModelSceneRegistry.SceneTransport.CONVERSATION_CHAT -> ModelSceneRegistry.ResponseParser.TEXT_CONTENT
        }
        val routeTag = when {
            overrideApplied -> ROUTE_CUSTOM_OPENAI_COMPAT
            effectiveTransport == ModelSceneRegistry.SceneTransport.OPENAI_COMPATIBLE -> "openai_compatible"
            effectiveTransport == ModelSceneRegistry.SceneTransport.VLM_CHAT -> "vlm_chat"
            effectiveTransport == ModelSceneRegistry.SceneTransport.CONVERSATION_CHAT -> "conversation_chat"
            else -> null
        }

        return ResolvedSceneRequest(
            requestedModel = requestedModel,
            resolvedModel = when {
                explicitResolvedModel != null -> explicitResolvedModel
                bindingApplied -> sceneBinding?.modelId.orEmpty()
                else -> defaultResolvedModel
            },
            sceneProfile = sceneProfile,
            effectiveTransport = effectiveTransport,
            responseParser = responseParser,
            apiBase = providerBase,
            apiKey = providerKey,
            providerProfileId = if (bindingApplied) boundProfile?.id else null,
            providerProfileName = if (bindingApplied) boundProfile?.name else null,
            routeTag = routeTag,
            customApiBaseApplied = !providerBase.isNullOrBlank(),
            bindingApplied = bindingApplied,
            bindingProfileMissing = bindingProfileMissing,
            overrideApplied = overrideApplied,
            overrideModel = overrideModel
        )
    }

    private fun normalizeApiBase(input: String): String? {
        return ModelProviderConfigStore.normalizeBaseUrl(input)
    }

    private fun buildOpenAIChatCompletionsUrl(apiBase: String): String {
        val base = apiBase.trim().trimEnd('/')
        return if (base.endsWith("/v1", ignoreCase = true)) {
            "$base/chat/completions"
        } else {
            "$base/v1/chat/completions"
        }
    }

    private fun buildOpenAIModelsUrl(apiBase: String): String {
        val base = apiBase.trim().trimEnd('/')
        return if (base.endsWith("/v1", ignoreCase = true)) {
            "$base/models"
        } else {
            "$base/v1/models"
        }
    }

    private fun buildOpenAIRequestBuilder(
        url: String,
        requestBody: okhttp3.RequestBody? = null,
        apiKey: String? = null
    ): Request.Builder {
        val builder = Request.Builder()
            .url(url)
            .addHeader("Content-Type", "application/json")
        if (!apiKey.isNullOrBlank()) {
            builder.addHeader("Authorization", "Bearer ${apiKey.trim()}")
        }
        if (requestBody != null) {
            builder.post(requestBody)
        }
        return builder
    }

    private fun openAIStreamClient(): OkHttpClient {
        return OkHttpClient.Builder()
            .connectTimeout(60, java.util.concurrent.TimeUnit.SECONDS)
            .readTimeout(0, java.util.concurrent.TimeUnit.SECONDS)
            .writeTimeout(60, java.util.concurrent.TimeUnit.SECONDS)
            .build()
    }

    private fun createChatRequestFromText(
        resolved: ResolvedSceneRequest,
        text: String
    ): ChatCompletionRequest {
        return ChatCompletionRequest(
            model = resolved.resolvedModel,
            messages = listOf(
                ChatCompletionMessage(
                    role = "user",
                    content = JsonPrimitive(text)
                )
            )
        )
    }

    private fun createChatRequestFromMessages(
        resolved: ResolvedSceneRequest,
        messages: List<Map<String, Any>>,
        enableThinking: Boolean? = null
    ): ChatCompletionRequest {
        val chatMessages = messages.map { message ->
            ChatCompletionMessage(
                role = message["role"]?.toString().orEmpty().ifBlank { "user" },
                content = parseChatMessageContent(message["content"]),
                toolCalls = parseAssistantToolCalls(message["tool_calls"] ?: message["toolCalls"]),
                toolCallId = parseOptionalText(message["tool_call_id"] ?: message["toolCallId"]),
                name = parseOptionalText(message["name"])
            )
        }
        return ChatCompletionRequest(
            model = resolved.resolvedModel,
            messages = chatMessages,
            enableThinking = enableThinking,
            streamOptions = ChatCompletionStreamOptions(includeUsage = true),
        )
    }

    private fun parseChatMessageContent(raw: Any?): JsonElement? {
        return when (raw) {
            null -> null
            is String -> JsonPrimitive(raw)
            is List<*> -> {
                val blocks = parseContentBlocks(raw)
                if (blocks.isNotEmpty()) {
                    blocks
                } else {
                    JsonPrimitive(raw.joinToString("\n") { item ->
                        when (item) {
                            is Map<*, *> -> {
                                val text = item["text"]?.toString().orEmpty()
                                if (text.isNotBlank()) text else item.toString()
                            }
                            else -> item?.toString().orEmpty()
                        }
                    }.trim())
                }
            }
            else -> JsonPrimitive(raw.toString())
        }
    }

    private fun parseAssistantToolCalls(raw: Any?): List<AssistantToolCall>? {
        if (raw !is List<*>) return null
        var fallbackIndex = 0
        val parsed = raw.mapNotNull { item ->
            val map = item as? Map<*, *> ?: return@mapNotNull null
            val function = map["function"] as? Map<*, *> ?: return@mapNotNull null
            val name = parseOptionalText(function["name"]) ?: return@mapNotNull null
            val arguments = when (val rawArguments = function["arguments"]) {
                null -> "{}"
                is String -> rawArguments
                else -> JSONObject.wrap(rawArguments)?.toString() ?: rawArguments.toString()
            }
            AssistantToolCall(
                id = parseOptionalText(map["id"]).orEmpty().ifBlank {
                    "tool_call_${fallbackIndex++}"
                },
                type = parseOptionalText(map["type"]).orEmpty().ifBlank { "function" },
                function = AssistantToolCallFunction(
                    name = name,
                    arguments = arguments
                )
            )
        }
        return parsed.ifEmpty { null }
    }

    private fun parseOptionalText(raw: Any?): String? {
        val normalized = raw?.toString()?.trim().orEmpty()
        return normalized.takeIf { it.isNotEmpty() }
    }

    private fun parseContentBlocks(raw: List<*>): KxJsonArray {
        val blocks = mutableListOf<KxJsonObject>()
        raw.forEach { item ->
            when (item) {
                is Map<*, *> -> {
                    val typeRaw = item["type"]?.toString()?.trim()?.lowercase().orEmpty()
                    val type = when {
                        typeRaw.isNotEmpty() -> typeRaw
                        item.containsKey("image_url") || item.containsKey("url") -> "image_url"
                        item.containsKey("text") -> "text"
                        else -> ""
                    }
                    when (type) {
                        "text", "input_text" -> {
                            val text = item["text"]?.toString().orEmpty()
                            if (text.isNotBlank()) {
                                blocks.add(
                                    buildJsonObject {
                                        put("type", JsonPrimitive("text"))
                                        put("text", JsonPrimitive(text))
                                    }
                                )
                            }
                        }
                        "image_url", "input_image", "image" -> {
                            val imageUrl = parseImageUrlFromAny(
                                item["image_url"] ?: item["url"] ?: item["imageUrl"]
                            )
                            if (imageUrl.isNotBlank()) {
                                blocks.add(buildImageContent(imageUrl))
                            }
                        }
                    }
                }
            }
        }
        return KxJsonArray(blocks)
    }

    private fun parseImageUrlFromAny(raw: Any?): String {
        return when (raw) {
            is String -> raw.trim()
            is Map<*, *> -> {
                val url = raw["url"]?.toString()?.trim().orEmpty()
                if (url.isNotBlank()) {
                    url
                } else {
                    raw["data"]?.toString()?.trim().orEmpty()
                }
            }
            else -> ""
        }
    }

    private fun createChatRequestFromVlmPayload(
        resolved: ResolvedSceneRequest,
        payload: Payload.VLMChatPayload
    ): ChatCompletionRequest {
        val contentBlocks = mutableListOf<KxJsonObject>()
        payload.text.trim().takeIf { it.isNotEmpty() }?.let {
            contentBlocks.add(
                buildJsonObject {
                    put("type", JsonPrimitive("text"))
                    put("text", JsonPrimitive(it))
                }
            )
        }
        payload.images.forEach { image ->
            contentBlocks.add(buildImageContent(image))
        }
        return ChatCompletionRequest(
            model = resolved.resolvedModel,
            messages = listOf(
                ChatCompletionMessage(
                    role = "user",
                    content = KxJsonArray(contentBlocks)
                )
            )
        )
    }

    private fun buildImageContent(rawImage: String): KxJsonObject {
        val imageUrl = if (
            rawImage.startsWith("http://", ignoreCase = true) ||
            rawImage.startsWith("https://", ignoreCase = true) ||
            rawImage.startsWith("data:", ignoreCase = true)
        ) {
            rawImage
        } else {
            "data:image/png;base64,$rawImage"
        }
        return buildJsonObject {
            put("type", JsonPrimitive("image_url"))
            put(
                "image_url",
                buildJsonObject {
                    put("url", JsonPrimitive(imageUrl))
                }
            )
        }
    }

    private fun buildRequestBodyWithResolvedModel(
        requestBodyJson: String,
        resolvedModel: String,
        includeLegacyMirrors: Boolean,
        mirrorLegacyTokenFields: Boolean = true
    ): String {
        return JSONObject(requestBodyJson).apply {
            if (resolvedModel.isNotEmpty()) {
                put("model", resolvedModel)
            }
            val toolsArray = optJSONArray("tools")
            if (toolsArray != null && toolsArray.length() == 0) {
                remove("tools")
            }
            val hasMaxCompletionTokens = has("max_completion_tokens")
            val hasMaxTokens = has("max_tokens")
            if (mirrorLegacyTokenFields && hasMaxCompletionTokens && !hasMaxTokens) {
                put("max_tokens", opt("max_completion_tokens"))
            } else if (!hasMaxCompletionTokens && hasMaxTokens) {
                put("max_completion_tokens", opt("max_tokens"))
            } else if (!mirrorLegacyTokenFields && hasMaxTokens) {
                remove("max_tokens")
            }
            if (includeLegacyMirrors && has("tools") && !has("functions")) {
                val currentToolsArray = optJSONArray("tools")
                if (currentToolsArray != null && currentToolsArray.length() > 0) {
                    val functionsArray = JSONArray()
                    for (i in 0 until currentToolsArray.length()) {
                        val toolObj = currentToolsArray.optJSONObject(i) ?: continue
                        val functionObj = toolObj.optJSONObject("function") ?: continue
                        val legacyFunction = JSONObject()
                        if (functionObj.has("name")) {
                            legacyFunction.put("name", functionObj.opt("name"))
                        }
                        if (functionObj.has("description")) {
                            legacyFunction.put("description", functionObj.opt("description"))
                        }
                        if (functionObj.has("parameters")) {
                            legacyFunction.put("parameters", functionObj.opt("parameters"))
                        }
                        if (legacyFunction.length() > 0) {
                            functionsArray.put(legacyFunction)
                        }
                    }
                    if (functionsArray.length() > 0) {
                        put("functions", functionsArray)
                        if (!has("function_call")) {
                            when (val toolChoice = opt("tool_choice")) {
                                is String -> {
                                    put(
                                        "function_call",
                                        if (toolChoice.equals("required", ignoreCase = true)) {
                                            "auto"
                                        } else {
                                            toolChoice
                                        }
                                    )
                                }
                                is JSONObject -> {
                                    val functionName = toolChoice.optJSONObject("function")
                                        ?.optString("name")
                                        ?.takeIf { it.isNotBlank() }
                                    if (functionName != null) {
                                        put("function_call", JSONObject().put("name", functionName))
                                    } else {
                                        put("function_call", "auto")
                                    }
                                }
                                else -> put("function_call", "auto")
                            }
                        }
                    }
                }
            }
        }.toString()
    }

    private suspend fun postOpenAIStreamRequestAsFlow(
        chatRequest: ChatCompletionRequest,
        apiBase: String?,
        apiKey: String?,
        event: EventSourceListener,
        routeTag: String? = null
    ): EventSource = withContext(Dispatchers.IO) {
        val base = normalizeApiBase(apiBase ?: "")
            ?: throw IllegalArgumentException("Invalid apiBase")
        val requestJson = encodeChatCompletionRequest(chatRequest.copy(stream = true))
        val requestBody = requestJson.toRequestBody("application/json".toMediaType())
        val request = buildOpenAIRequestBuilder(
            url = buildOpenAIChatCompletionsUrl(base),
            requestBody = requestBody,
            apiKey = apiKey
        )
            .addHeader("Accept", "text/event-stream")
            .build()
        EventSources.createFactory(openAIStreamClient()).newEventSource(
            request,
            createLoggingEventListener(
                "[openai_compatible stream model=${chatRequest.model} route=${routeTag.orEmpty()}]",
                event
            )
        )
    }

    private suspend fun postOpenAIChatCompletionsStreamRequest(
        resolved: ResolvedSceneRequest,
        requestBodyJson: String,
        event: EventSourceListener
    ): EventSource = withContext(Dispatchers.IO) {
        val base = normalizeApiBase(resolved.apiBase ?: "")
            ?: throw IllegalArgumentException("Invalid apiBase")
        val requestBody = buildRequestBodyWithResolvedModel(
            requestBodyJson = requestBodyJson,
            resolvedModel = resolved.resolvedModel,
            includeLegacyMirrors = false,
            mirrorLegacyTokenFields = false
        ).toRequestBody("application/json".toMediaType())
        val request = buildOpenAIRequestBuilder(
            url = buildOpenAIChatCompletionsUrl(base),
            requestBody = requestBody,
            apiKey = resolved.apiKey
        )
            .addHeader("Accept", "text/event-stream")
            .build()
        EventSources.createFactory(openAIStreamClient()).newEventSource(
            request,
            createLoggingEventListener(
                "[openai_compatible chat-completions model=${resolved.resolvedModel}]",
                event
            )
        )
    }

    private fun sanitizeShortMessage(raw: String?, maxLen: Int = 200): String {
        val normalized = raw?.replace(Regex("\\s+"), " ")?.trim().orEmpty()
        if (normalized.isEmpty()) {
            return "请求失败"
        }
        return if (normalized.length <= maxLen) normalized else "${normalized.take(maxLen)}..."
    }

    private fun extractAvailabilityMessage(responseBody: String?): String {
        if (responseBody.isNullOrBlank()) return "请求失败"
        return try {
            val json = JSONObject(responseBody)
            val errorObj = json.optJSONObject("error")
            val errorMsg = errorObj?.optString("message", "")?.takeIf { it.isNotBlank() }
            val topMsg = json.optString("message", "").takeIf { it.isNotBlank() }
            sanitizeShortMessage(errorMsg ?: topMsg ?: responseBody)
        } catch (_: Exception) {
            sanitizeShortMessage(responseBody)
        }
    }



    /**
     * 发送 LLM 请求并处理流式响应 (SSE格式)
     *
     * @param text 请求文本
     * @param onStreamData 接收流式数据的回调函数，参数为解析后的文本内容
     */
    /**
     * 发送 LLM 请求并处理流式响应 (SSE格式)，返回Flow
     *
     * @param text 请求文本
     * @return Flow 流，发射解析后的文本内容
     */
    suspend fun postLLMStreamRequestAsFlow(
        model: String, text: String, event: EventSourceListener
    ): EventSource {
        val resolved = resolveSceneRequest(model)
        logSceneProfile(resolved)
        return postOpenAIStreamRequestAsFlow(
            chatRequest = createChatRequestFromText(resolved, text),
            apiBase = resolved.apiBase,
            apiKey = resolved.apiKey,
            event = event,
            routeTag = resolved.routeTag
        )
    }

    /**
     * 发送 LLM 请求并处理流式响应 (SSE格式)，返回Flow，并且支持对话上下文功能
     *
     * @param model 模型名称
     * @param messages 对话消息列表
     * @param event 事件监听器
     * @return EventSource 事件源
     */
    suspend fun postLLMStreamRequestWithContextAsFlow(
        model: String,
        messages: List<Map<String, Any>>,
        event: EventSourceListener,
        enableThinking: Boolean? = null
    ): EventSource {
        val resolved = resolveSceneRequest(model)
        logSceneProfile(resolved)
        return postOpenAIStreamRequestAsFlow(
            chatRequest = createChatRequestFromMessages(
                resolved = resolved,
                messages = messages,
                enableThinking = enableThinking
            ),
            apiBase = resolved.apiBase,
            apiKey = resolved.apiKey,
            event = event,
            routeTag = resolved.routeTag
        )
    }

    /**
     * 发送标准 Chat Completions Tool Calling 请求（SSE）
     *
     * 请求体由调用方按标准字段构造，例如：
     * messages / model / max_completion_tokens / stream / stream_options / tools
     */
    suspend fun postChatCompletionsStreamRequest(
        model: String,
        requestBodyJson: String,
        event: EventSourceListener,
        explicitApiBase: String? = null,
        explicitApiKey: String? = null,
        explicitModel: String? = null
    ): EventSource {
        val resolved = resolveSceneRequest(
            modelOrScene = model,
            explicitApiBase = explicitApiBase,
            explicitApiKey = explicitApiKey,
            explicitModel = explicitModel
        )
        logSceneProfile(resolved)
        return postOpenAIChatCompletionsStreamRequest(
            resolved = resolved,
            requestBodyJson = requestBodyJson,
            event = event
        )
    }

    /**
     * 发送 OpenClaw 的 OpenAI 兼容流式请求（/v1/chat/completions）
     *
     * @param openClawConfig OpenClaw 配置（baseUrl/token/userId/sessionKey）
     * @param messages 对话消息列表
     * @param event 事件监听器
     * @return EventSource 事件源
     */
    suspend fun postOpenClawChatCompletionsStream(
        openClawConfig: TaskParams.OpenClawConfig,
        messages: List<Map<String, Any>>,
        event: EventSourceListener
    ): EventSource {
        val baseUrl = openClawConfig.baseUrl.trim().trimEnd('/')
        val url = "$baseUrl/v1/chat/completions"
        val authToken = openClawConfig.token?.trim()

        OmniLog.i(
            "HttpController",
            "OpenClaw stream url=$url messages=${messages.size} user=${openClawConfig.userId?.trim()} auth=${!authToken.isNullOrBlank()} sessionKey=${!openClawConfig.sessionKey.isNullOrBlank()}"
        )

        val jsonObject = JSONObject()
        val messagesArray = JSONArray()
        for (message in messages) {
            val messageObject = JSONObject()
            for ((key, value) in message) {
                messageObject.put(key, value)
            }
            messagesArray.put(messageObject)
        }
        jsonObject.put("model", "openclaw")
        jsonObject.put("stream", true)
        jsonObject.put("messages", messagesArray)
        val userId = openClawConfig.userId?.trim()
        if (!userId.isNullOrEmpty()) {
            jsonObject.put("user", userId)
        }

        val requestBody = jsonObject.toString().toRequestBody("application/json".toMediaType())
        val requestBuilder = Request.Builder()
            .url(url)
            .addHeader("Accept", "text/event-stream")
            .addHeader("Content-Type", "application/json")

        if (!authToken.isNullOrEmpty()) {
            requestBuilder.addHeader("Authorization", "Bearer $authToken")
        }

        val sessionKey = openClawConfig.sessionKey?.trim()
        if (!sessionKey.isNullOrEmpty()) {
            requestBuilder.addHeader("X-OpenClaw-Session-Key", sessionKey)
        }

        val request = requestBuilder.post(requestBody).build()
        OmniLog.i(
            "HttpController",
            "OpenClaw request ready bodyBytes=${jsonObject.toString().length}"
        )

        return EventSources.createFactory(openClawStreamClient)
            .newEventSource(
                request,
                createLoggingEventListener("[openclaw/v1/chat/completions]", event)
            )
    }


    /**
     * 发送 LLM 请求并获取响应（普通返回）
     *
     * @param url 请求地址
     * @param jsonBody JSON 请求体
     * @param headers 请求头
     * @return 服务器响应内容
     */
    suspend fun postLLMRequest(
        model: String, text: String
    ): ResultBean = withContext(Dispatchers.IO) {
        val resolved = resolveSceneRequest(model)
        logSceneProfile(resolved)
        val response = postSceneChatCompletionInternal(
            resolved = resolved,
            request = createChatRequestFromText(resolved, text),
            retryOnBadRequest = false
        )
        if (!response.success) {
            throw IllegalStateException(response.message.ifBlank { "LLM request failed" })
        }
        return@withContext ResultBean(response.content.ifBlank { response.message })
    }

    /**
     * 发送 VLM 请求并上传文件
     * @param text 文本内容
     * @param images 图片内容
     */
    suspend fun postVLMRequest(
        payload: Payload.VLMChatPayload
    ): ResultBean = withContext(Dispatchers.IO) {
        val resolved = resolveSceneRequest(
            modelOrScene = payload.model,
            defaultTransport = ModelSceneRegistry.SceneTransport.VLM_CHAT
        )
        logSceneProfile(resolved)
        val response = postSceneChatCompletionInternal(
            resolved = resolved,
            request = createChatRequestFromVlmPayload(resolved, payload),
            retryOnBadRequest = false
        )
        return@withContext ResultBean(response.content.ifBlank { response.message })
    }

    suspend fun postVLMStreamRequestAsFlow(
        model: String, text: String, image: String, event: EventSourceListener

    ): EventSource {
        val images = ArrayList<String>();
        images.add(image)
        val resolved = resolveSceneRequest(
            modelOrScene = model,
            defaultTransport = ModelSceneRegistry.SceneTransport.VLM_CHAT
        )
        logSceneProfile(resolved)
        return postOpenAIStreamRequestAsFlow(
            chatRequest = createChatRequestFromVlmPayload(
                resolved,
                Payload.VLMChatPayload(model, images, text)
            ),
            apiBase = resolved.apiBase,
            apiKey = resolved.apiKey,
            event = event,
            routeTag = resolved.routeTag
        )
    }

    suspend fun postVLMStreamRequestAsFlow(
        model: String, text: String, images: ArrayList<String>, event: EventSourceListener

    ): EventSource {
        val resolved = resolveSceneRequest(
            modelOrScene = model,
            defaultTransport = ModelSceneRegistry.SceneTransport.VLM_CHAT
        )
        logSceneProfile(resolved)
        return postOpenAIStreamRequestAsFlow(
            chatRequest = createChatRequestFromVlmPayload(
                resolved,
                Payload.VLMChatPayload(model, images, text)
            ),
            apiBase = resolved.apiBase,
            apiKey = resolved.apiKey,
            event = event,
            routeTag = resolved.routeTag
        )
    }

    suspend fun postSceneChatCompletion(
        chatRequest: ChatCompletionRequest
    ): SceneChatCompletionResponse {
        val resolved = resolveSceneRequest(
            modelOrScene = chatRequest.model
        )
        logSceneProfile(resolved)
        OmniLog.i(
            TAG,
            "postSceneChatCompletion scene=${chatRequest.model} resolvedModel=${resolved.resolvedModel} parser=${resolved.responseParser.wireValue} tools=${chatRequest.tools.size} messages=${chatRequest.messages.size}"
        )
        return postSceneChatCompletionInternal(
            resolved = resolved,
            request = chatRequest.copy(model = resolved.resolvedModel, stream = false),
            retryOnBadRequest = chatRequest.tools.isNotEmpty()
        )
    }

    suspend fun postSceneChatCompletionStream(
        chatRequest: ChatCompletionRequest,
        event: EventSourceListener
    ): SceneChatCompletionStreamHandle {
        val resolved = resolveSceneRequest(
            modelOrScene = chatRequest.model
        )
        logSceneProfile(resolved)
        OmniLog.i(
            TAG,
            "postSceneChatCompletionStream scene=${chatRequest.model} resolvedModel=${resolved.resolvedModel} parser=${resolved.responseParser.wireValue} tools=${chatRequest.tools.size} messages=${chatRequest.messages.size}"
        )
        val eventSource = postOpenAIChatCompletionsStreamRequest(
            resolved = resolved,
            requestBodyJson = encodeChatCompletionRequest(
                chatRequest.copy(
                    model = resolved.resolvedModel,
                    stream = true
                )
            ),
            event = event
        )
        return SceneChatCompletionStreamHandle(
            eventSource = eventSource,
            parser = resolved.responseParser,
            route = resolved.routeTag,
            resolvedModel = resolved.resolvedModel
        )
    }

    private data class CompletionRequestVariant(
        val name: String,
        val request: ChatCompletionRequest
    )

    private suspend fun postSceneChatCompletionInternal(
        resolved: ResolvedSceneRequest,
        request: ChatCompletionRequest,
        retryOnBadRequest: Boolean
    ): SceneChatCompletionResponse = withContext(Dispatchers.IO) {
        val base = normalizeApiBase(resolved.apiBase ?: "")
        if (base == null) {
            return@withContext buildFailureSceneResponse(
                code = "500",
                message = "Invalid apiBase",
                parser = resolved.responseParser,
                routeTag = resolved.routeTag
            )
        }

        val url = buildOpenAIChatCompletionsUrl(base)
        val variants = if (retryOnBadRequest) {
            buildSceneRequestVariants(request.copy(model = resolved.resolvedModel, stream = false))
        } else {
            listOf(CompletionRequestVariant("default", request.copy(model = resolved.resolvedModel, stream = false)))
        }

        var lastFailure: SceneChatCompletionResponse? = null
        for ((index, variant) in variants.withIndex()) {
            if (index > 0) {
                OmniLog.w(
                    TAG,
                    "retry scene completion variant=${variant.name} model=${resolved.resolvedModel} parser=${resolved.responseParser.wireValue}"
                )
            }

            val requestJson = encodeChatCompletionRequest(variant.request)
            OmniLog.d(TAG, "=== OpenAI Request Debug ===")
            OmniLog.d(TAG, "URL: $url")
            OmniLog.d(TAG, "Model: ${variant.request.model}, hasApiKey=${!resolved.apiKey.isNullOrBlank()}, variant=${variant.name}")
            OmniLog.d(TAG, "Request Body: ${requestJson.take(2000)}")
            OmniLog.d(TAG, "============================")

            val requestBody = requestJson.toRequestBody("application/json".toMediaType())
            val requestCall = buildOpenAIRequestBuilder(
                url = url,
                requestBody = requestBody,
                apiKey = resolved.apiKey
            ).build()

            val response = OkHttpClient().newCall(requestCall).execute()
            val responseBody = response.body?.string()
            OmniLog.d(TAG, "Response Status: ${response.code}")
            logResponseBody("[openai_compatible model=${variant.request.model}]", responseBody)

            if (!response.isSuccessful) {
                val failure = buildFailureSceneResponse(
                    code = response.code.toString(),
                    message = extractAvailabilityMessage(responseBody),
                    parser = resolved.responseParser,
                    routeTag = resolved.routeTag,
                    rawResponseBody = responseBody
                )
                lastFailure = failure
                if (retryOnBadRequest && response.code == 400 && index < variants.lastIndex) {
                    OmniLog.w(TAG, "scene completion 400 on variant=${variant.name}: ${failure.message}")
                    continue
                }
                return@withContext failure
            }

            return@withContext parseStructuredSceneResponse(
                response = responseBody,
                parser = resolved.responseParser,
                routeTag = resolved.routeTag
            )
        }

        return@withContext lastFailure ?: buildFailureSceneResponse(
            code = "500",
            message = "Request failed",
            parser = resolved.responseParser,
            routeTag = resolved.routeTag
        )
    }

    /**
     * 检测自定义 OpenAI-compatible 模型可用性
     */
    suspend fun checkVlmModelAvailability(
        model: String,
        apiBase: String,
        apiKey: String?
    ): ModelAvailabilityCheckResult = withContext(Dispatchers.IO) {
        val normalizedModel = model.trim()
        if (normalizedModel.isEmpty()) {
            return@withContext ModelAvailabilityCheckResult(
                available = false,
                code = null,
                message = "模型名不能为空"
            )
        }

        val normalizedApiBase = normalizeApiBase(apiBase)
            ?: return@withContext ModelAvailabilityCheckResult(
                available = false,
                code = null,
                message = "URL 非法，请输入 http(s) 地址"
            )
        val url = buildOpenAIChatCompletionsUrl(normalizedApiBase)

        return@withContext try {
            val requestJson = JSONObject().apply {
                put("model", normalizedModel)
                put("stream", false)
                put("temperature", 0)
                put("max_tokens", 1)
                put(
                    "messages",
                    JSONArray().put(
                        JSONObject().apply {
                            put("role", "user")
                            put("content", "ping")
                        }
                    )
                )
            }

            val requestBody = requestJson.toString().toRequestBody("application/json".toMediaType())
            val response = OkHttpClient().newCall(
                buildOpenAIRequestBuilder(url, requestBody, apiKey).build()
            ).execute()
            val responseBody = response.body?.string()
            if (!response.isSuccessful) {
                return@withContext ModelAvailabilityCheckResult(
                    available = false,
                    code = response.code,
                    message = extractAvailabilityMessage(responseBody)
                )
            }

            val hasChoices = try {
                val json = JSONObject(responseBody ?: "{}")
                val choices = json.optJSONArray("choices")
                choices != null && choices.length() > 0
            } catch (_: Exception) {
                false
            }

            if (hasChoices) {
                ModelAvailabilityCheckResult(
                    available = true,
                    code = response.code,
                    message = "OK"
                )
            } else {
                ModelAvailabilityCheckResult(
                    available = false,
                    code = response.code,
                    message = "响应不符合 OpenAI 结构（缺少 choices）"
                )
            }
        } catch (e: Exception) {
            ModelAvailabilityCheckResult(
                available = false,
                code = null,
                message = sanitizeShortMessage(e.message ?: "请求异常")
            )
        }
    }

    suspend fun checkProviderModelAvailability(
        model: String,
        apiBase: String,
        apiKey: String?
    ): ModelAvailabilityCheckResult {
        return checkVlmModelAvailability(model, apiBase, apiKey)
    }

    suspend fun fetchProviderModels(
        apiBase: String,
        apiKey: String?
    ): List<ProviderModelOption> = withContext(Dispatchers.IO) {
        val normalizedApiBase = normalizeApiBase(apiBase)
            ?: return@withContext emptyList()
        val response = OkHttpClient().newCall(
            buildOpenAIRequestBuilder(
                url = buildOpenAIModelsUrl(normalizedApiBase),
                apiKey = apiKey
            ).get().build()
        ).execute()
        val responseBody = response.body?.string()
        if (!response.isSuccessful) {
            throw IllegalStateException(
                "获取模型列表失败 (${response.code})：${extractAvailabilityMessage(responseBody)}"
            )
        }

        val data = JSONObject(responseBody ?: "{}").optJSONArray("data") ?: JSONArray()
        buildList {
            for (i in 0 until data.length()) {
                val item = data.optJSONObject(i) ?: continue
                val id = item.optString("id").trim()
                if (id.isEmpty()) continue
                add(
                    ProviderModelOption(
                        id = id,
                        displayName = item.optString("display_name").trim().ifEmpty { id },
                        ownedBy = item.optString("owned_by").trim().takeIf { it.isNotEmpty() }
                    )
                )
            }
        }.sortedBy { it.id.lowercase() }
    }

    private fun encodeChatCompletionRequest(request: ChatCompletionRequest): String {
        val requestJson = completionJson.encodeToString(request)
        return buildRequestBodyWithResolvedModel(
            requestBodyJson = requestJson,
            resolvedModel = request.model,
            includeLegacyMirrors = false
        )
    }

    private fun buildSceneRequestVariants(request: ChatCompletionRequest): List<CompletionRequestVariant> {
        val variants = mutableListOf<CompletionRequestVariant>()
        val seenPayloads = LinkedHashSet<String>()

        fun add(name: String, candidate: ChatCompletionRequest) {
            val encoded = encodeChatCompletionRequest(candidate)
            if (seenPayloads.add(encoded)) {
                variants.add(CompletionRequestVariant(name = name, request = candidate))
            }
        }

        add("default", request)

        if (request.tools.isEmpty()) {
            return variants
        }

        add("no_parallel_tool_calls", request.copy(parallelToolCalls = null))
        add(
            "no_tool_choice",
            request.copy(
                parallelToolCalls = null,
                toolChoice = null
            )
        )

        val normalizedMaxTokens = request.maxTokens ?: request.maxCompletionTokens
        add(
            "minimal_tools",
            request.copy(
                parallelToolCalls = null,
                toolChoice = null,
                temperature = null,
                topP = null,
                maxCompletionTokens = null,
                maxTokens = normalizedMaxTokens
            )
        )
        return variants
    }

    private fun buildFailureSceneResponse(
        code: String,
        message: String,
        parser: ModelSceneRegistry.ResponseParser,
        routeTag: String?,
        rawResponseBody: String? = null
    ): SceneChatCompletionResponse {
        return SceneChatCompletionResponse(
            success = false,
            code = code,
            message = message,
            parser = parser,
            route = routeTag,
            rawResponseBody = rawResponseBody
        )
    }

    private fun parseStructuredSceneResponse(
        response: String?,
        parser: ModelSceneRegistry.ResponseParser,
        routeTag: String?
    ): SceneChatCompletionResponse {
        return try {
            val jsonObject = JSONObject(response ?: "{}")
            val choices = jsonObject.optJSONArray("choices")
                ?: return buildFailureSceneResponse(
                    code = "500",
                    message = "响应不符合 OpenAI 结构（缺少 choices）",
                    parser = parser,
                    routeTag = routeTag,
                    rawResponseBody = response
                )

            val firstChoice = choices.optJSONObject(0)
                ?: return buildFailureSceneResponse(
                    code = "500",
                    message = "响应不符合 OpenAI 结构（choices[0] 无效）",
                    parser = parser,
                    routeTag = routeTag,
                    rawResponseBody = response
                )

            val message = firstChoice.optJSONObject("message")
            val content = extractTextPayload(message?.opt("content") ?: firstChoice.opt("text"))
            val reasoning = listOf(
                message?.opt("reasoning_content"),
                message?.opt("reasoning"),
                message?.opt("thinking"),
                firstChoice.opt("reasoning_content"),
                firstChoice.opt("reasoning"),
                firstChoice.opt("thinking")
            ).asSequence()
                .map { extractTextPayload(it) }
                .firstOrNull { it.isNotBlank() }
                .orEmpty()
            val finishReason = firstChoice.optString("finish_reason").trim().takeIf { it.isNotEmpty() }
            val toolCalls = parseToolCalls(firstChoice, message)

            SceneChatCompletionResponse(
                success = true,
                code = "200",
                message = "success",
                parser = parser,
                route = routeTag,
                content = content,
                reasoning = reasoning,
                finishReason = finishReason,
                toolCalls = toolCalls,
                rawResponseBody = response
            )
        } catch (e: Exception) {
            safeLogError("Failed to parse structured OpenAI response: ${e.message}")
            buildFailureSceneResponse(
                code = "500",
                message = "Parse error: ${e.message}",
                parser = parser,
                routeTag = routeTag,
                rawResponseBody = response
            )
        }
    }

    private fun parseToolCalls(
        choice: JSONObject,
        message: JSONObject?
    ): List<AssistantToolCall> {
        val toolCallsArray = message?.optJSONArray("tool_calls") ?: choice.optJSONArray("tool_calls")
        if (toolCallsArray == null || toolCallsArray.length() == 0) {
            return emptyList()
        }

        val parsed = mutableListOf<AssistantToolCall>()
        for (i in 0 until toolCallsArray.length()) {
            val toolCall = toolCallsArray.optJSONObject(i) ?: continue
            val functionObj = toolCall.optJSONObject("function") ?: continue
            val name = functionObj.optString("name").trim()
            if (name.isEmpty()) continue
            val argumentsRaw = functionObj.opt("arguments")
            val arguments = when (argumentsRaw) {
                null -> "{}"
                is String -> argumentsRaw
                is JSONObject, is JSONArray -> argumentsRaw.toString()
                else -> argumentsRaw.toString()
            }
            parsed.add(
                AssistantToolCall(
                    id = toolCall.optString("id").ifBlank { "tool_call_$i" },
                    type = toolCall.optString("type").ifBlank { "function" },
                    function = AssistantToolCallFunction(
                        name = name,
                        arguments = arguments
                    )
                )
            )
        }
        return parsed
    }

    private fun extractTextPayload(contentRaw: Any?): String {
        return when (contentRaw) {
            is String -> contentRaw
            is JSONArray -> {
                val buffer = StringBuilder()
                for (i in 0 until contentRaw.length()) {
                    val item = contentRaw.opt(i)
                    when (item) {
                        is String -> buffer.append(item)
                        is JSONObject -> {
                            val type = item.optString("type", "")
                            if (type.equals("text", ignoreCase = true)) {
                                buffer.append(item.optString("text"))
                            } else if (item.has("text")) {
                                buffer.append(item.optString("text"))
                            }
                        }
                    }
                }
                buffer.toString()
            }
            is JSONObject -> when {
                contentRaw.has("text") -> contentRaw.optString("text")
                contentRaw.has("content") -> contentRaw.optString("content")
                else -> ""
            }
            else -> ""
        }.trim()
    }

    private fun safeLogError(message: String) {
        runCatching { OmniLog.e(TAG, message) }
    }


}
