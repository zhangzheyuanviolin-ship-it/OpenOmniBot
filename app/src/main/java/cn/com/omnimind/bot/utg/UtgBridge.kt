package cn.com.omnimind.bot.utg

import BaseApplication
import android.content.Context
import android.content.Intent
import cn.com.omnimind.accessibility.service.AssistsService
import cn.com.omnimind.accessibility.util.XmlTreeUtils
import cn.com.omnimind.assists.api.bean.VLMTaskPreHookResult
import cn.com.omnimind.assists.api.bean.VLMTaskRunLogPayload
import cn.com.omnimind.assists.controller.accessibility.AccessibilityController
import cn.com.omnimind.assists.task.vlmserver.AbortAction
import cn.com.omnimind.assists.task.vlmserver.ClickAction
import cn.com.omnimind.assists.task.vlmserver.FeedbackAction
import cn.com.omnimind.assists.task.vlmserver.FinishedAction
import cn.com.omnimind.assists.task.vlmserver.HotKeyAction
import cn.com.omnimind.assists.task.vlmserver.InfoAction
import cn.com.omnimind.assists.task.vlmserver.LongPressAction
import cn.com.omnimind.assists.task.vlmserver.OpenAppAction
import cn.com.omnimind.assists.task.vlmserver.PressBackAction
import cn.com.omnimind.assists.task.vlmserver.PressHomeAction
import cn.com.omnimind.assists.task.vlmserver.RecordAction
import cn.com.omnimind.assists.task.vlmserver.RequireUserChoiceAction
import cn.com.omnimind.assists.task.vlmserver.RequireUserConfirmationAction
import cn.com.omnimind.assists.task.vlmserver.ScrollAction
import cn.com.omnimind.assists.task.vlmserver.TypeAction
import cn.com.omnimind.assists.task.vlmserver.UIAction
import cn.com.omnimind.assists.task.vlmserver.WaitAction
import cn.com.omnimind.baselib.util.ImageQuality
import cn.com.omnimind.baselib.util.OmniLog
import cn.com.omnimind.bot.manager.AssistsCoreManager
import cn.com.omnimind.bot.mcp.McpServerManager
import cn.com.omnimind.bot.mcp.McpServerState
import cn.com.omnimind.bot.termux.TermuxCommandRunner
import cn.com.omnimind.bot.termux.TermuxCommandSpec
import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import com.tencent.mmkv.MMKV
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.URI
import java.util.concurrent.TimeUnit

/**
 * Local UTG bridge shared by the agent-side pre-hook and the Ktor callback host.
 *
 * This object keeps the OpenOmniBot-side integration thin:
 * - outbound calls to the private OmniFlow localhost service
 * - inbound host callbacks for observe / act / confirm
 * - minimal action lowering for the Python executor contract
 */
object UtgBridge {
    private const val TAG = "UtgBridge"
    private const val EXPECTED_PROVIDER_ID = "omniflow_utg"
    private const val PREF_UTG_ENABLED = "utg_enabled"
    private const val PREF_OMNIFLOW_BASE_URL = "utg_omniflow_base_url"
    private const val PREF_OMNIFLOW_AUTO_START = "utg_omniflow_auto_start"
    private const val PREF_OMNIFLOW_START_COMMAND = "utg_omniflow_start_command"
    private const val PREF_OMNIFLOW_WORKING_DIRECTORY = "utg_omniflow_working_directory"
    private const val PREF_VLM_TASK_RUN_LOG_PREFIX = "utg_vlm_task_run_log_"
    private const val DEFAULT_OMNIFLOW_BASE_URL = "http://127.0.0.1:19070"
    private const val DEFAULT_PROVIDER_SESSION_NAME = EXPECTED_PROVIDER_ID
    private const val DEFAULT_PROVIDER_START_TIMEOUT_SECONDS = 20
    private const val DEFAULT_PROVIDER_HEALTH_RETRY_COUNT = 8
    private const val DEFAULT_PROVIDER_HEALTH_RETRY_DELAY_MS = 1000L

    private val gson = Gson()
    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()
    private val mmkv by lazy { MMKV.defaultMMKV() }
    @Volatile
    private var lastHealthyBaseUrl: String? = null
    private val httpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(4, TimeUnit.SECONDS)
            .readTimeout(120, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .build()
    }

    data class ObservationRequest(
        @SerializedName("xml") val xml: Boolean = false,
        @SerializedName("app_info") val appInfo: Boolean = false,
        @SerializedName("screenshot") val screenshot: Boolean = false,
    )

    data class ObservationResponse(
        @SerializedName("xml") val xml: String? = null,
        @SerializedName("package_name") val packageName: String? = null,
        @SerializedName("activity_name") val activityName: String? = null,
        @SerializedName("image_base64") val imageBase64: String? = null,
    )

    data class RunCompiledPathRequest(
        @SerializedName("goal") val goal: String,
        @SerializedName("path_id") val pathId: String,
        @SerializedName("slots") val slots: Map<String, String> = emptyMap(),
        @SerializedName("bridge_base_url") val bridgeBaseUrl: String,
        @SerializedName("bridge_token") val bridgeToken: String,
        @SerializedName("context") val context: Map<String, Any?> = emptyMap(),
        @SerializedName("skip_terminal_verify") val skipTerminalVerify: Boolean = false,
    )

    data class RunCompiledPathResponse(
        @SerializedName("success") val success: Boolean = false,
        @SerializedName("error_code") val errorCode: String? = null,
        @SerializedName("error_message") val errorMessage: String? = null,
        @SerializedName("summary") val summary: String? = null,
        @SerializedName("terminal_state") val terminalState: Map<String, Any?>? = null,
        @SerializedName("run_log") val runLog: Map<String, Any?>? = null,
        @SerializedName("run_log_summary") val runLogSummary: Map<String, Any?>? = null,
        @SerializedName("provider_run_log_path") val providerRunLogPath: String? = null,
        @SerializedName("canonical_run_log_path") val canonicalRunLogPath: String? = null,
    )

    data class VlmPreHookRequest(
        @SerializedName("goal") val goal: String,
        @SerializedName("current_package_name") val currentPackageName: String? = null,
    )

    data class VlmPreHookResponse(
        @SerializedName("kind") val kind: String = "",
        @SerializedName("summary") val summary: String = "",
        @SerializedName("path_id") val pathId: String? = null,
        @SerializedName("planner_guidance") val plannerGuidance: String = "",
        @SerializedName("execution_route") val executionRoute: String = "",
    )

    data class AppendRunLogRequest(
        @SerializedName("run_log") val runLog: Map<String, Any?>,
    )

    data class IngestRequest(
        @SerializedName("goal") val goal: String,
        @SerializedName("steps") val steps: List<StepRecord>,
        @SerializedName("auto_import") val autoImport: Boolean = true,
    )

    data class StepRecord(
        @SerializedName("observation") val observation: ObservationRecord,
        @SerializedName("tool_call") val toolCall: ToolCallRecord,
    )

    data class ObservationRecord(
        @SerializedName("xml") val xml: String?,
        @SerializedName("package_name") val packageName: String?,
    )

    data class ToolCallRecord(
        @SerializedName("name") val name: String,
        @SerializedName("params") val params: Map<String, Any?> = emptyMap(),
    )

    data class AppendRunLogResponse(
        @SerializedName("success") val success: Boolean = false,
        @SerializedName("run_id") val runId: String? = null,
        @SerializedName("run_log_path") val runLogPath: String? = null,
        @SerializedName("run_log") val runLog: Map<String, Any?>? = null,
    )

    data class ActionEnvelope(
        @SerializedName("type") val type: String,
        @SerializedName("params") val params: Map<String, Any?> = emptyMap(),
    )

    data class ActRequest(
        @SerializedName("action") val action: ActionEnvelope,
    )

    data class ActResponse(
        @SerializedName("success") val success: Boolean = false,
        @SerializedName("message") val message: String? = null,
        @SerializedName("data") val data: Map<String, Any?>? = null,
    )

    data class ConfirmRequest(
        @SerializedName("prompt") val prompt: String,
    )

    data class ConfirmResponse(
        @SerializedName("success") val success: Boolean = false,
        @SerializedName("confirmed") val confirmed: Boolean = false,
    )

    fun isUtgEnabled(): Boolean {
        return mmkv.decodeBool(PREF_UTG_ENABLED, true)
    }

    fun setUtgEnabled(enabled: Boolean) {
        mmkv.encode(PREF_UTG_ENABLED, enabled)
    }

    fun omniFlowBaseUrl(): String {
        val stored = mmkv.decodeString(PREF_OMNIFLOW_BASE_URL)?.trim().orEmpty()
        val raw = if (stored.isNotBlank()) stored else DEFAULT_OMNIFLOW_BASE_URL
        return normalizeBaseUrl(raw)
    }

    fun resolvedOmniFlowBaseUrl(): String {
        val configured = omniFlowBaseUrl()
        return buildBaseUrlCandidates(configured).firstOrNull() ?: configured
    }

    fun isProviderAutoStartEnabled(): Boolean {
        return mmkv.decodeBool(PREF_OMNIFLOW_AUTO_START, true)
    }

    fun setProviderAutoStartEnabled(enabled: Boolean) {
        mmkv.encode(PREF_OMNIFLOW_AUTO_START, enabled)
    }

    fun setOmniFlowBaseUrl(baseUrl: String?) {
        val normalized = normalizeBaseUrl(baseUrl)
        if (normalized.isBlank()) {
            mmkv.removeValueForKey(PREF_OMNIFLOW_BASE_URL)
        } else {
            mmkv.encode(PREF_OMNIFLOW_BASE_URL, normalized)
        }
        lastHealthyBaseUrl = null
    }

    fun setProviderStartCommand(command: String?) {
        val normalized = command?.trim().orEmpty()
        if (normalized.isBlank()) {
            mmkv.removeValueForKey(PREF_OMNIFLOW_START_COMMAND)
        } else {
            mmkv.encode(PREF_OMNIFLOW_START_COMMAND, normalized)
        }
    }

    fun setProviderWorkingDirectory(workingDirectory: String?) {
        val normalized = workingDirectory?.trim().orEmpty()
        if (normalized.isBlank()) {
            mmkv.removeValueForKey(PREF_OMNIFLOW_WORKING_DIRECTORY)
        } else {
            mmkv.encode(PREF_OMNIFLOW_WORKING_DIRECTORY, normalized)
        }
    }

    @Suppress("UNUSED_PARAMETER")
    suspend fun snapshotConfig(context: Context): Map<String, Any?> {
        val configuredStartCommand = providerStartCommand()
        val providerHealth = fetchProviderHealth()
        val providerHealthy = isCompatibleProviderHealth(providerHealth)
        return linkedMapOf(
            "utgEnabled" to isUtgEnabled(),
            "omniflowBaseUrl" to omniFlowBaseUrl(),
            "resolvedOmniflowBaseUrl" to resolvedOmniFlowBaseUrl(),
            "providerExpectedStorePath" to expectedProviderStorePath(),
            "providerAutoStartEnabled" to isProviderAutoStartEnabled(),
            "providerStartCommand" to configuredStartCommand,
            "providerStartCommandConfigured" to configuredStartCommand.isNotBlank(),
            "providerWorkingDirectory" to providerWorkingDirectory(),
            "providerHealthy" to providerHealthy,
            "providerHealth" to providerHealth,
            "providerHealthStatus" to providerHealthStatus(providerHealth),
            "providerRunLogPath" to providerHealth?.get("provider_run_log_path"),
            "canonicalRunLogPath" to providerHealth?.get("canonical_run_log_path"),
        )
    }

    suspend fun controlProvider(context: Context, action: String): Map<String, Any?> {
        val normalizedAction = action.trim().lowercase()
        if (normalizedAction !in setOf("start", "stop", "restart")) {
            return linkedMapOf(
                "success" to false,
                "action" to normalizedAction,
                "message" to "unsupported provider action",
            )
        }
        val success = when (normalizedAction) {
            "start" -> ensureProviderReady(context, ignoreAutoStartPolicy = true)
            "stop" -> {
                val command = providerStartCommand().trim()
                val shellCommand = buildString {
                    append("if command -v tmux >/dev/null 2>&1; then\n")
                    append("  tmux kill-session -t ")
                    append(DEFAULT_PROVIDER_SESSION_NAME)
                    append(" 2>/dev/null || true\n")
                    append("else\n")
                    if (command.isNotBlank()) {
                        append("  pkill -f ")
                        append(shellQuote(command))
                        append(" 2>/dev/null || true\n")
                    }
                    append("fi")
                }
                val result = TermuxCommandRunner.execute(
                    context = context,
                    spec = TermuxCommandSpec(
                        command = shellCommand,
                        timeoutSeconds = DEFAULT_PROVIDER_START_TIMEOUT_SECONDS,
                    ),
                )
                if (!result.success) {
                    OmniLog.w(
                        TAG,
                        "UTG provider stop failed: ${result.errorMessage ?: result.stderr.ifBlank { result.stdout }}"
                    )
                }
                delay(500L)
                !isProviderHealthy()
            }
            else -> {
                controlProvider(context, "stop")
                ensureProviderReady(context, ignoreAutoStartPolicy = true)
            }
        }
        val snapshot = linkedMapOf<String, Any?>()
        snapshot.putAll(snapshotConfig(context))
        snapshot["success"] = success
        snapshot["action"] = normalizedAction
        snapshot["message"] = when {
            success -> "provider_${normalizedAction}_ok"
            else -> "provider_${normalizedAction}_failed"
        }
        return snapshot
    }

    suspend fun restoreProviderIfEnabled(context: Context) {
        if (!isUtgEnabled()) {
            return
        }
        if (!isProviderAutoStartEnabled()) {
            return
        }
        ensureProviderReady(context)
    }

    fun localBridgeBaseUrl(state: McpServerState): String {
        return "http://127.0.0.1:${state.port}/utg"
    }

    suspend fun snapshotManualRunContext(context: Context): Map<String, Any?> {
        val bridgeState = McpServerManager.ensureRunning(context)
        val providerHealthy = ensureProviderReady(context, ignoreAutoStartPolicy = true)
        val providerHealth = fetchProviderHealth()
        return linkedMapOf(
            "bridgeBaseUrl" to localBridgeBaseUrl(bridgeState),
            "bridgeToken" to bridgeState.token,
            "resolvedOmniflowBaseUrl" to resolvedOmniFlowBaseUrl(),
            "providerExpectedStorePath" to expectedProviderStorePath(),
            "providerHealthy" to providerHealthy,
            "providerMessage" to if (providerHealthy) "ok" else providerHealthStatus(providerHealth),
        )
    }

    suspend fun prepareVlmTaskExecution(
        context: Context,
        goal: String,
        currentPackageName: String? = null,
    ): VLMTaskPreHookResult {
        if (!isUtgEnabled()) {
            return VLMTaskPreHookResult(
                kind = "disabled_or_fallback",
                summary = "OmniFlow 已关闭，直接使用 VLM 执行",
            )
        }
        if (!ensureProviderReady(context)) {
            return VLMTaskPreHookResult(
                kind = "hard_fail",
                summary = "OmniFlow provider 不可达，任务中止",
                executionRoute = "blocked",
            )
        }
        val response = post(
            path = "/vlm/pre_hook",
            payload = VlmPreHookRequest(
                goal = goal,
                currentPackageName = currentPackageName?.takeIf { it.isNotBlank() },
            ),
            responseClass = VlmPreHookResponse::class.java,
        ) ?: return VLMTaskPreHookResult(
            kind = "hard_fail",
            summary = "OmniFlow compile 请求失败，任务中止",
            executionRoute = "blocked",
        )
        return VLMTaskPreHookResult(
            kind = response.kind.ifBlank { "hard_fail" },
            summary = response.summary,
            pathId = response.pathId,
            plannerGuidance = response.plannerGuidance,
            executionRoute = response.executionRoute,
        )
    }

    suspend fun captureObservation(request: ObservationRequest): ObservationResponse {
        val rootNode = AssistsService.instance?.rootInActiveWindow
        val xml = if (request.xml) {
            try {
                rootNode?.let { XmlTreeUtils.buildXmlTree(it) }?.let { XmlTreeUtils.serializeXml(it) }
                    ?: AccessibilityController.getCaptureScreenShotXml(true)
            } catch (e: Exception) {
                OmniLog.w(TAG, "captureObservation xml fallback to AccessibilityController: ${e.message}")
                AccessibilityController.getCaptureScreenShotXml(true)
            }
        } else {
            null
        }
        val packageName = if (request.appInfo) {
            rootNode?.packageName?.toString()?.takeIf { it.isNotBlank() }
                ?: AccessibilityController.getPackageName()
        } else {
            null
        }
        val activityName = if (request.appInfo) {
            rootNode?.className?.toString()?.takeIf { it.isNotBlank() }
                ?: AccessibilityController.getCurrentActivity()
        } else {
            null
        }
        val imageBase64 = if (request.screenshot) {
            try {
                AccessibilityController.captureScreenshotImage(
                    isBitmap = false,
                    isBase64 = true,
                    isFile = false,
                    isFilterOverlay = true,
                    isCheckSingleColor = false,
                    compressQuality = ImageQuality.LOW,
                ).imageBase64
            } catch (t: Throwable) {
                OmniLog.e(TAG, "captureObservation screenshot failed: ${t.message}")
                null
            }
        } else {
            null
        }
        return ObservationResponse(
            xml = xml,
            packageName = packageName,
            activityName = activityName,
            imageBase64 = imageBase64,
        )
    }

    suspend fun executeAction(request: ActRequest): ActResponse {
        val action = request.action
        val params = action.params
        return try {
            when (action.type.trim()) {
                "click" -> {
                    val x = params.doubleValue("x")?.toFloat()
                    val y = params.doubleValue("y")?.toFloat()
                    if (x == null || y == null) {
                        return ActResponse(success = false, message = "missing click coordinates")
                    }
                    AccessibilityController.clickCoordinate(x, y)
                    ActResponse(success = true, message = "clicked")
                }

                "long_press" -> {
                    val x = params.doubleValue("x")?.toFloat()
                    val y = params.doubleValue("y")?.toFloat()
                    val durationMs = params.longValue("duration_ms") ?: 1000L
                    if (x == null || y == null) {
                        return ActResponse(success = false, message = "missing long_press coordinates")
                    }
                    AccessibilityController.longClickCoordinate(x, y, durationMs)
                    ActResponse(success = true, message = "long pressed")
                }

                "input_text" -> {
                    val text = params.stringValue("text")
                    if (text.isNullOrBlank()) {
                        return ActResponse(success = false, message = "missing input text")
                    }
                    AccessibilityController.inputTextToFocusedNode(text)
                    ActResponse(success = true, message = "text input")
                }

                "swipe" -> {
                    val x = params.doubleValue("x")?.toFloat()
                    val y = params.doubleValue("y")?.toFloat()
                    val distance = params.doubleValue("distance")?.toFloat()
                    val directionName = params.stringValue("direction")
                    val durationMs = params.longValue("duration_ms") ?: 500L
                    val direction = when (directionName?.trim()?.lowercase()) {
                        "up" -> cn.com.omnimind.omniintelligence.models.ScrollDirection.UP
                        "down" -> cn.com.omnimind.omniintelligence.models.ScrollDirection.DOWN
                        "left" -> cn.com.omnimind.omniintelligence.models.ScrollDirection.LEFT
                        "right" -> cn.com.omnimind.omniintelligence.models.ScrollDirection.RIGHT
                        else -> null
                    }
                    if (x == null || y == null || distance == null || direction == null) {
                        return ActResponse(success = false, message = "invalid swipe params")
                    }
                    AccessibilityController.scrollCoordinate(x, y, direction, distance, durationMs)
                    ActResponse(success = true, message = "swiped")
                }

                "open_app" -> {
                    val packageName = params.stringValue("package_name")
                    if (packageName.isNullOrBlank()) {
                        return ActResponse(success = false, message = "missing package_name")
                    }
                    val launchIntent = runCatching {
                        BaseApplication.instance.packageManager.getLaunchIntentForPackage(packageName)
                    }.getOrNull()
                    if (launchIntent != null) {
                        launchIntent.addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
                        )
                        BaseApplication.instance.startActivity(launchIntent)
                    } else {
                        AccessibilityController.launchApplication(packageName) { clickX, clickY ->
                            AccessibilityController.clickCoordinate(clickX, clickY)
                        }
                    }
                    ActResponse(
                        success = true,
                        message = "app opened",
                        data = mapOf(
                            "current_package_name" to packageName,
                            "current_activity_name" to null,
                        )
                    )
                }

                "press_key" -> {
                    val key = params.stringValue("key")?.trim()?.uppercase()
                    if (key.isNullOrBlank()) {
                        return ActResponse(success = false, message = "missing key")
                    }
                    AccessibilityController.pressHotKey(key)
                    ActResponse(success = true, message = "key pressed")
                }

                "wait" -> {
                    val durationMs = params.longValue("duration_ms")
                        ?: ((params.doubleValue("time_s") ?: 1.0) * 1000).toLong()
                    delay(durationMs.coerceAtLeast(0L))
                    ActResponse(success = true, message = "waited ${durationMs}ms")
                }

                "finished" -> {
                    ActResponse(
                        success = true,
                        message = params.stringValue("content") ?: "finished"
                    )
                }

                else -> {
                    ActResponse(success = false, message = "unsupported action type: ${action.type}")
                }
            }
        } catch (e: Exception) {
            OmniLog.e(TAG, "executeAction failed: ${e.message}")
            ActResponse(success = false, message = e.message ?: "act failed")
        }
    }

    suspend fun requestConfirmation(prompt: String): ConfirmResponse {
        val manager = AssistsCoreManager.currentInstance()
        if (manager == null) {
            return ConfirmResponse(success = false, confirmed = false)
        }
        return try {
            val confirmed = manager.requestUtgConfirmation(prompt)
            ConfirmResponse(success = true, confirmed = confirmed)
        } catch (e: Exception) {
            OmniLog.e(TAG, "requestConfirmation failed: ${e.message}")
            ConfirmResponse(success = false, confirmed = false)
        }
    }

    suspend fun runCompiledPath(request: RunCompiledPathRequest): RunCompiledPathResponse? {
        return post(
            path = "/run_compiled_path",
            payload = request,
            responseClass = RunCompiledPathResponse::class.java,
        )
    }

    suspend fun ingestVlmTaskRunLog(
        payload: VLMTaskRunLogPayload,
    ): AppendRunLogResponse? {
        if (payload.compileGateResult?.kind == "hit") {
            val providerRunLog = parseJsonMap(payload.taskReport.providerRunLogJson)
            return AppendRunLogResponse(
                success = providerRunLog != null || !payload.taskReport.canonicalRunLogPath.isNullOrBlank(),
                runId = providerRunLog?.stringValue("run_id"),
                runLogPath = payload.taskReport.canonicalRunLogPath ?: payload.taskReport.providerRunLogPath,
                runLog = providerRunLog,
            )
        }
        return post(
            path = "/run_logs/ingest",
            payload = buildIngestPayload(payload),
            responseClass = AppendRunLogResponse::class.java,
        )
    }

    suspend fun cacheVlmTaskRunLog(taskId: String, payload: VLMTaskRunLogPayload) {
        val normalizedTaskId = taskId.trim()
        if (normalizedTaskId.isEmpty()) {
            return
        }
        runCatching {
            val appendResponse = ingestVlmTaskRunLog(payload)
            val providerPersisted = appendResponse?.success == true
            val ingestPayload = buildIngestPayload(payload)
            val snapshot = linkedMapOf<String, Any?>(
                "success" to providerPersisted,
                "cached_locally" to true,
                "provider_persisted" to providerPersisted,
                "task_id" to normalizedTaskId,
                "goal" to payload.goal,
                "run_id" to appendResponse?.runId,
                "run_log_path" to appendResponse?.runLogPath,
                "run_log" to appendResponse?.runLog,
                "ingest_payload" to ingestPayload,
                "error_message" to if (providerPersisted) {
                    null
                } else {
                    "provider ingest unavailable; using local cached ingest_payload snapshot"
                },
            )
            mmkv.encode(
                PREF_VLM_TASK_RUN_LOG_PREFIX + normalizedTaskId,
                gson.toJson(snapshot),
            )
        }.onFailure {
            OmniLog.w(TAG, "cacheVlmTaskRunLog failed: ${it.message}")
        }
    }

    fun getCachedVlmTaskRunLog(taskId: String): Map<String, Any?> {
        val normalizedTaskId = taskId.trim()
        if (normalizedTaskId.isEmpty()) {
            return linkedMapOf(
                "success" to false,
                "task_id" to normalizedTaskId,
                "error_message" to "taskId 不能为空",
            )
        }
        val encoded = mmkv.decodeString(PREF_VLM_TASK_RUN_LOG_PREFIX + normalizedTaskId)
        if (encoded.isNullOrBlank()) {
            return linkedMapOf(
                "success" to false,
                "task_id" to normalizedTaskId,
                "error_message" to "未找到对应的 run_log",
            )
        }
        @Suppress("UNCHECKED_CAST")
        val decoded = runCatching {
            gson.fromJson(encoded, Map::class.java) as? Map<String, Any?>
        }.getOrNull()
        if (decoded == null) {
            return linkedMapOf(
                "success" to false,
                "task_id" to normalizedTaskId,
                "error_message" to "run_log 解析失败",
            )
        }
        return linkedMapOf<String, Any?>("success" to true).apply {
            putAll(decoded)
        }
    }

    suspend fun fetchProviderHealth(): Map<String, Any?>? {
        return get("/health")
    }

    suspend fun requestJson(
        method: String,
        path: String,
        payload: Any? = null,
        baseUrl: String? = null,
    ): Map<String, Any?>? {
        return requestMap(
            method = method,
            path = path,
            payload = payload,
            baseUrl = baseUrl,
        )
    }

    private suspend fun ensureProviderReady(
        context: Context,
        ignoreAutoStartPolicy: Boolean = false,
    ): Boolean {
        if (isProviderHealthy()) {
            return true
        }
        if (!ignoreAutoStartPolicy && !isProviderAutoStartEnabled()) {
            return false
        }
        val command = providerStartCommand()
        if (command.isBlank()) {
            OmniLog.w(TAG, "UTG provider auto-start skipped: empty startup command")
            return false
        }
        val launchCommand = buildProviderLaunchCommand(command, providerWorkingDirectory())
        val shellCommand = buildString {
            append("if command -v tmux >/dev/null 2>&1; then\n")
            append("  tmux kill-session -t ")
            append(DEFAULT_PROVIDER_SESSION_NAME)
            append(" 2>/dev/null || true\n")
            append("  tmux new-session -d -s ")
            append(DEFAULT_PROVIDER_SESSION_NAME)
            append(" ")
            append(shellQuote(launchCommand))
            append("\n")
            append("else\n")
            append("  pkill -f ")
            append(shellQuote(command.trim()))
            append(" 2>/dev/null || true\n")
            append("  nohup sh -lc ")
            append(shellQuote(launchCommand))
            append(" >/dev/null 2>&1 < /dev/null &\n")
            append("fi")
        }
        val result = TermuxCommandRunner.execute(
            context = context,
            spec = TermuxCommandSpec(
                command = shellCommand,
                timeoutSeconds = DEFAULT_PROVIDER_START_TIMEOUT_SECONDS,
            ),
        )
        if (!result.success) {
            OmniLog.w(
                TAG,
                "UTG provider auto-start failed: ${result.errorMessage ?: result.stderr.ifBlank { result.stdout }}"
            )
            return false
        }
        repeat(DEFAULT_PROVIDER_HEALTH_RETRY_COUNT) {
            if (isProviderHealthy()) {
                return true
            }
            delay(DEFAULT_PROVIDER_HEALTH_RETRY_DELAY_MS)
        }
        OmniLog.w(TAG, "UTG provider started but /health still unavailable")
        return isProviderHealthy()
    }

    private suspend fun isProviderHealthy(): Boolean {
        val payload = fetchProviderHealth() ?: return false
        return isCompatibleProviderHealth(payload)
    }

    private fun isCompatibleProviderHealth(payload: Map<String, Any?>?): Boolean {
        if (payload?.get("success") != true) {
            return false
        }
        val providerId = payload["provider"]?.toString()?.trim().orEmpty()
        val aliases = payload["provider_aliases"] as? List<*>
        val providerMatches = providerId == EXPECTED_PROVIDER_ID || aliases.orEmpty().any { alias ->
            alias?.toString()?.trim() == EXPECTED_PROVIDER_ID
        }
        if (!providerMatches) {
            return false
        }
        val expectedStorePath = expectedProviderStorePath()
        if (expectedStorePath.isNullOrBlank()) {
            return true
        }
        val actualStorePath = payload["utg_store_path"]?.toString()?.trim().orEmpty()
        return actualStorePath == expectedStorePath
    }

    private fun providerHealthStatus(payload: Map<String, Any?>?): String {
        if (payload == null) {
            return "provider_unreachable"
        }
        if (isCompatibleProviderHealth(payload)) {
            return payload["status"]?.toString()?.takeIf { it.isNotBlank() } ?: "ok"
        }
        if (payload["success"] == true) {
            val actualProvider = payload["provider"]?.toString()?.trim().orEmpty()
            val expectedStorePath = expectedProviderStorePath()
            val actualStorePath = payload["utg_store_path"]?.toString()?.trim().orEmpty()
            return if (actualProvider.isBlank()) {
                "provider_incompatible"
            } else if (
                actualProvider == EXPECTED_PROVIDER_ID &&
                !expectedStorePath.isNullOrBlank() &&
                actualStorePath != expectedStorePath
            ) {
                "provider_store_mismatch:$actualStorePath"
            } else {
                "provider_mismatch:$actualProvider"
            }
        }
        return payload["status"]?.toString()?.takeIf { it.isNotBlank() } ?: "provider_unreachable"
    }

    private fun providerStartCommand(): String {
        return mmkv.decodeString(PREF_OMNIFLOW_START_COMMAND)?.trim().orEmpty()
    }

    private fun providerWorkingDirectory(): String? {
        return mmkv.decodeString(PREF_OMNIFLOW_WORKING_DIRECTORY)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
    }

    private fun expectedProviderStorePath(): String? {
        val command = providerStartCommand()
        if (command.isBlank()) {
            return null
        }
        val match = Regex("""--utg-store-path(?:=|\s+)('([^']*)'|"([^"]*)"|(\S+))""")
            .find(command)
            ?: return null
        return listOf(2, 3, 4)
            .asSequence()
            .mapNotNull { index -> match.groups[index]?.value }
            .map { it.trim() }
            .firstOrNull { it.isNotEmpty() }
    }

    private fun buildProviderLaunchCommand(command: String, workingDirectory: String?): String {
        return buildString {
            if (!workingDirectory.isNullOrBlank()) {
                append("cd ")
                append(shellQuote(workingDirectory))
                append(" && ")
            }
            append(command.trim())
        }
    }

    private suspend fun get(path: String, baseUrl: String? = null): Map<String, Any?>? {
        return requestMap(
            method = "GET",
            path = path,
            payload = null,
            baseUrl = baseUrl,
        )
    }

    private suspend fun <T : Any> post(
        path: String,
        payload: Any,
        responseClass: Class<T>,
        baseUrl: String? = null,
    ): T? {
        return requestObject(
            method = "POST",
            path = path,
            payload = payload,
            responseClass = responseClass,
            baseUrl = baseUrl,
        )
    }

    private suspend fun requestMap(
        method: String,
        path: String,
        payload: Any? = null,
        baseUrl: String? = null,
    ): Map<String, Any?>? = withContext(Dispatchers.IO) {
        val raw = requestRaw(
            method = method,
            path = path,
            payload = payload,
            baseUrl = baseUrl,
        ) ?: return@withContext null
        @Suppress("UNCHECKED_CAST")
        gson.fromJson(raw, Map::class.java) as? Map<String, Any?>
    }

    private suspend fun <T : Any> requestObject(
        method: String,
        path: String,
        payload: Any? = null,
        responseClass: Class<T>,
        baseUrl: String? = null,
    ): T? = withContext(Dispatchers.IO) {
        val raw = requestRaw(
            method = method,
            path = path,
            payload = payload,
            baseUrl = baseUrl,
        ) ?: return@withContext null
        gson.fromJson(raw, responseClass)
    }

    private fun normalizeBaseUrl(baseUrl: String?): String {
        return baseUrl?.trim().orEmpty().removeSuffix("/")
    }

    private fun buildBaseUrlCandidates(baseUrl: String?): List<String> {
        val normalized = normalizeBaseUrl(baseUrl)
        if (normalized.isBlank()) {
            return emptyList()
        }
        val uri = runCatching { URI(normalized) }.getOrNull() ?: return listOf(normalized)
        val scheme = uri.scheme ?: return listOf(normalized)
        val host = uri.host ?: return listOf(normalized)
        val port = if (uri.port >= 0) uri.port else uri.toURL().defaultPort
        if (port <= 0) {
            return listOf(normalized)
        }
        val authorityCandidates = when (host.lowercase()) {
            "127.0.0.1", "localhost" -> listOf("127.0.0.1", "10.0.2.2", "localhost")
            "10.0.2.2" -> listOf("10.0.2.2", "127.0.0.1", "localhost")
            else -> listOf(host)
        }
        val candidates = mutableListOf<String>()
        val remembered = normalizeBaseUrl(lastHealthyBaseUrl)
        if (remembered.isNotBlank()) {
            candidates += remembered
        }
        authorityCandidates.forEach { candidateHost ->
            candidates += "$scheme://$candidateHost:$port"
        }
        candidates += normalized
        return candidates
            .map(::normalizeBaseUrl)
            .filter { it.isNotBlank() }
            .distinct()
    }

    private fun rememberHealthyBaseUrl(baseUrl: String) {
        lastHealthyBaseUrl = normalizeBaseUrl(baseUrl)
    }

    private suspend fun requestRaw(
        method: String,
        path: String,
        payload: Any? = null,
        baseUrl: String? = null,
    ): String? = withContext(Dispatchers.IO) {
        val normalizedMethod = method.trim().uppercase()
        for (candidateBaseUrl in buildBaseUrlCandidates(baseUrl ?: omniFlowBaseUrl())) {
            val url = "$candidateBaseUrl$path"
            val body = payload?.let { gson.toJson(it).toRequestBody(jsonMediaType) }
            val builder = Request.Builder()
                .url(url)
                .header("Connection", "close")
            val request = when (normalizedMethod) {
                "GET" -> builder.get().build()
                "POST" -> builder.post(body ?: "{}".toRequestBody(jsonMediaType)).build()
                "DELETE" -> {
                    if (body == null) {
                        builder.delete().build()
                    } else {
                        builder.delete(body).build()
                    }
                }
                else -> {
                    OmniLog.w(TAG, "Unsupported UTG HTTP method: $normalizedMethod")
                    return@withContext null
                }
            }
            val raw = runCatching {
                httpClient.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) {
                        OmniLog.w(TAG, "UTG HTTP ${response.code} for $url")
                        return@use null
                    }
                    response.body?.string().orEmpty().takeIf { it.isNotBlank() }
                }
            }.onFailure {
                httpClient.connectionPool.evictAll()
                OmniLog.w(TAG, "UTG request failed for $url: ${it.message}")
            }.getOrNull()
            if (!raw.isNullOrBlank()) {
                rememberHealthyBaseUrl(candidateBaseUrl)
                return@withContext raw
            }
        }
        null
    }

    private fun buildIngestPayload(payload: VLMTaskRunLogPayload): IngestRequest {
        val steps = payload.taskReport.executionTrace.map { step ->
            StepRecord(
                observation = ObservationRecord(
                    xml = step.observationXml,
                    packageName = step.packageName,
                ),
                toolCall = uiActionToToolCall(step.action),
            )
        }
        return IngestRequest(goal = payload.goal, steps = steps)
    }

    private fun uiActionToToolCall(action: UIAction): ToolCallRecord {
        return when (action) {
            is ClickAction -> ToolCallRecord(
                "click",
                mapOf("x" to action.x, "y" to action.y, "target_description" to action.targetDescription)
            )
            is TypeAction -> ToolCallRecord("input_text", mapOf("text" to action.content))
            is ScrollAction -> ToolCallRecord(
                "swipe",
                mapOf(
                    "x1" to action.x1,
                    "y1" to action.y1,
                    "x2" to action.x2,
                    "y2" to action.y2,
                    "target_description" to action.targetDescription,
                )
            )
            is LongPressAction -> ToolCallRecord(
                "long_press",
                mapOf("x" to action.x, "y" to action.y, "target_description" to action.targetDescription)
            )
            is OpenAppAction -> ToolCallRecord("open_app", mapOf("package_name" to action.packageName))
            is PressHomeAction -> ToolCallRecord("press_key", mapOf("key" to "HOME"))
            is PressBackAction -> ToolCallRecord("press_key", mapOf("key" to "BACK"))
            is WaitAction -> ToolCallRecord(
                "wait",
                mapOf("duration_ms" to (action.durationMs ?: (action.duration?.times(1000))))
            )
            is FinishedAction -> ToolCallRecord("finished", mapOf("content" to action.content))
            is RecordAction -> ToolCallRecord("record", mapOf("content" to action.content))
            is InfoAction -> ToolCallRecord("info", mapOf("value" to action.value))
            is FeedbackAction -> ToolCallRecord("feedback", mapOf("value" to action.value))
            is AbortAction -> ToolCallRecord("abort", mapOf("value" to action.value))
            is HotKeyAction -> ToolCallRecord("press_key", mapOf("key" to action.key))
            is RequireUserChoiceAction -> ToolCallRecord(
                "require_user_choice",
                mapOf("prompt" to action.prompt, "options" to action.options)
            )
            is RequireUserConfirmationAction -> ToolCallRecord(
                "require_user_confirmation",
                mapOf("prompt" to action.prompt)
            )
        }
    }

    private fun parseJsonMap(raw: String?): Map<String, Any?>? {
        if (raw.isNullOrBlank()) {
            return null
        }
        return runCatching {
            @Suppress("UNCHECKED_CAST")
            gson.fromJson(raw, Map::class.java) as? Map<String, Any?>
        }.getOrNull()
    }

    private fun Map<String, Any?>.mapValue(key: String): Map<String, Any?> {
        val raw = this[key] as? Map<*, *> ?: return emptyMap()
        return linkedMapOf<String, Any?>().apply {
            raw.forEach { (itemKey, value) ->
                if (itemKey != null) {
                    put(itemKey.toString(), value)
                }
            }
        }
    }

    private fun Map<String, Any?>.stringValue(key: String): String? {
        return this[key]?.toString()
    }

    private fun Map<String, Any?>.doubleValue(key: String): Double? {
        val value = this[key] ?: return null
        return when (value) {
            is Number -> value.toDouble()
            else -> value.toString().toDoubleOrNull()
        }
    }

    private fun Map<String, Any?>.longValue(key: String): Long? {
        val value = this[key] ?: return null
        return when (value) {
            is Number -> value.toLong()
            else -> value.toString().toLongOrNull()
        }
    }

    private fun shellQuote(value: String): String {
        return "'" + value.replace("'", "'\"'\"'") + "'"
    }
}
