package cn.com.omnimind.bot.utg

import BaseApplication
import android.content.Context
import android.content.Intent
import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo
import cn.com.omnimind.accessibility.service.AssistsService
import cn.com.omnimind.accessibility.util.XmlTreeUtils
import cn.com.omnimind.assists.api.bean.VLMTaskPreHookResult
import cn.com.omnimind.assists.api.bean.VLMTaskRunLogPayload
import cn.com.omnimind.assists.controller.accessibility.AccessibilityController
import cn.com.omnimind.assists.detection.scenarios.stability.PageStabilityDetector
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
import cn.com.omnimind.assists.task.vlmserver.RunCompiledPathAction
import cn.com.omnimind.assists.task.vlmserver.ScrollAction
import cn.com.omnimind.assists.task.vlmserver.TypeAction
import cn.com.omnimind.assists.task.vlmserver.UIAction
import cn.com.omnimind.assists.task.vlmserver.UIStep
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
import java.io.File
import java.net.URI
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.util.concurrent.TimeUnit

/**
 * Local UTG bridge shared by the agent-side pre-hook and the Ktor callback host.
 *
 * This object keeps the OpenOmniBot-side integration thin:
 * - outbound calls to the private OmniCloud localhost service
 * - inbound host callbacks for observe / act / confirm
 * - minimal action lowering for the Python executor contract
 */
object UtgBridge {
    private const val TAG = "UtgBridge"
    private const val PREF_UTG_ENABLED = "utg_enabled"
    private const val PREF_OMNICLOUD_BASE_URL = "utg_omnicloud_base_url"
    private const val PREF_OMNICLOUD_AUTO_START = "utg_omnicloud_auto_start"
    private const val PREF_FALLBACK_TO_VLM_ON_FAILURE = "utg_fallback_to_vlm_on_failure"
    private const val PREF_OMNICLOUD_START_COMMAND = "utg_omnicloud_start_command"
    private const val PREF_OMNICLOUD_WORKING_DIRECTORY = "utg_omnicloud_working_directory"
    private const val PREF_RUN_LOG_RECORDING_ENABLED = "utg_run_log_recording_enabled"
    private const val PREF_VLM_TASK_RUN_LOG_PREFIX = "utg_vlm_task_run_log_"
    private const val DEFAULT_OMNICLOUD_BASE_URL = "http://127.0.0.1:19070"
    private const val DEFAULT_OMNICLOUD_START_COMMAND =
        "python -m src.integrations.utg_api --host 127.0.0.1 --port 19070 --utg-store-path src/templates/utg_smoke_test.json"
    private const val DEFAULT_PROVIDER_SESSION_NAME = "omnicloud_utg"
    private const val DEFAULT_PROVIDER_STDOUT_PATH = "/root/omnicloud_utg.log"
    private const val DEFAULT_PROVIDER_START_TIMEOUT_SECONDS = 20
    private const val DEFAULT_PROVIDER_HEALTH_RETRY_COUNT = 8
    private const val DEFAULT_PROVIDER_HEALTH_RETRY_DELAY_MS = 1000L
    private const val RUN_LOG_DIR_NAME = "utg"
    private const val RUN_LOG_FILE_NAME = "utg_runs.jsonl"
    private const val DEFAULT_ACTION_DELAY_MS = 800L

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
        @SerializedName("wait_to_stabilize") val waitToStabilize: Boolean = false,
    )

    data class ObservationResponse(
        @SerializedName("xml") val xml: String? = null,
        @SerializedName("package_name") val packageName: String? = null,
        @SerializedName("activity_name") val activityName: String? = null,
        @SerializedName("image_base64") val imageBase64: String? = null,
    )

    data class CompileContext(
        @SerializedName("state_node_id") val stateNodeId: String? = null,
        @SerializedName("package_name") val packageName: String? = null,
        @SerializedName("activity_name") val activityName: String? = null,
        @SerializedName("recent_path_ids") val recentPathIds: List<String>? = null,
    )

    data class CompileRequest(
        @SerializedName("goal") val goal: String,
        @SerializedName("context") val context: CompileContext? = null,
    )

    data class CompileResponse(
        @SerializedName("success") val success: Boolean = false,
        @SerializedName("decision") val decision: String? = null,
        @SerializedName("path_id") val pathId: String? = null,
        @SerializedName("slots") val slots: Map<String, String> = emptyMap(),
        @SerializedName("reason") val reason: String? = null,
        @SerializedName("candidate_path_ids") val candidatePathIds: List<String> = emptyList(),
        @SerializedName("matched_subgoal") val matchedSubgoal: String? = null,
        @SerializedName("remaining_goal") val remainingGoal: String? = null,
        @SerializedName("is_partial") val isPartial: Boolean = false,
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
        @SerializedName("terminal_state") val terminalState: Map<String, Any?>? = null,
        @SerializedName("run_log") val runLog: Map<String, Any?>? = null,
        @SerializedName("run_log_summary") val runLogSummary: Map<String, Any?>? = null,
        @SerializedName("provider_run_log_path") val providerRunLogPath: String? = null,
        @SerializedName("canonical_run_log_path") val canonicalRunLogPath: String? = null,
    ) {
        fun summaryText(goal: String): String {
            val terminalReached = terminalState?.get("terminal_page_reached") == true
            val terminalSkipped = terminalState?.get("reason") == "skipped_for_oob"
            return when {
                success && (terminalReached || terminalSkipped) -> "已通过 UTG 执行完成：$goal"
                success -> "已通过 UTG 执行：$goal"
                !errorMessage.isNullOrBlank() -> errorMessage
                !errorCode.isNullOrBlank() -> "UTG 执行失败：$errorCode"
                else -> "UTG 执行失败"
            }
        }
    }

    data class AppendRunLogRequest(
        @SerializedName("run_log") val runLog: Map<String, Any?>,
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

    data class FastPathAttempt(
        val attempted: Boolean = false,
        val source: String = "vlm_fallback",
        val status: String,
        val compile: CompileResponse? = null,
        val run: RunCompiledPathResponse? = null,
        val fallbackAllowed: Boolean = true,
        val message: String? = null,
        val runLogPath: String? = null,
    ) {
        fun isSuccess(): Boolean = attempted && status == "success" && run?.success == true

        fun compileSummary(goal: String): String {
            val pathId = compile?.pathId?.takeIf { it.isNotBlank() }
            val candidateIds = compile?.candidatePathIds.orEmpty().filter { it.isNotBlank() }
            val reasonText = compile?.reason?.takeIf { !it.isNullOrBlank() }
            return when {
                pathId != null -> "UTG compile hit: $pathId"
                candidateIds.isNotEmpty() -> "UTG compile miss: ${candidateIds.joinToString(", ")}"
                reasonText != null -> "UTG compile miss: $reasonText"
                else -> "UTG compile miss: $goal"
            }
        }

        fun plannerGuidance(goal: String): String {
            val candidateIds = compile?.candidatePathIds.orEmpty().filter { it.isNotBlank() }
            if (candidateIds.isEmpty()) return ""
            val lines = mutableListOf<String>()
            lines += "UTG compile miss. Before using generic screen reasoning, first check whether one of these compiled path ids can finish the goal directly."
            lines += "Goal: $goal"
            lines += "If an existing path fits, call the compiled path tool directly with one of these ids:"
            candidateIds.forEachIndexed { index, pathId ->
                lines += "${index + 1}. $pathId"
            }
            lines += "Only fall back to normal VLM screen actions when none of these candidate paths fit the current goal."
            return lines.joinToString("\n")
        }
    }

    fun isUtgEnabled(): Boolean {
        return mmkv.decodeBool(PREF_UTG_ENABLED, true)
    }

    fun setUtgEnabled(enabled: Boolean) {
        mmkv.encode(PREF_UTG_ENABLED, enabled)
    }

    fun omniCloudBaseUrl(): String {
        val stored = mmkv.decodeString(PREF_OMNICLOUD_BASE_URL)?.trim().orEmpty()
        val raw = if (stored.isNotBlank()) stored else DEFAULT_OMNICLOUD_BASE_URL
        return normalizeBaseUrl(raw)
    }

    fun resolvedOmniCloudBaseUrl(): String {
        val configured = omniCloudBaseUrl()
        return buildBaseUrlCandidates(configured).firstOrNull() ?: configured
    }

    fun isProviderAutoStartEnabled(): Boolean {
        return mmkv.decodeBool(PREF_OMNICLOUD_AUTO_START, true)
    }

    fun setProviderAutoStartEnabled(enabled: Boolean) {
        mmkv.encode(PREF_OMNICLOUD_AUTO_START, enabled)
    }

    fun isFallbackToVlmOnFailureEnabled(): Boolean {
        return mmkv.decodeBool(PREF_FALLBACK_TO_VLM_ON_FAILURE, true)
    }

    fun setFallbackToVlmOnFailureEnabled(enabled: Boolean) {
        mmkv.encode(PREF_FALLBACK_TO_VLM_ON_FAILURE, enabled)
    }

    fun isRunLogRecordingEnabled(): Boolean {
        return mmkv.decodeBool(PREF_RUN_LOG_RECORDING_ENABLED, true)
    }

    fun setRunLogRecordingEnabled(enabled: Boolean) {
        mmkv.encode(PREF_RUN_LOG_RECORDING_ENABLED, enabled)
    }

    fun setOmniCloudBaseUrl(baseUrl: String?) {
        val normalized = normalizeBaseUrl(baseUrl)
        if (normalized.isBlank()) {
            mmkv.removeValueForKey(PREF_OMNICLOUD_BASE_URL)
        } else {
            mmkv.encode(PREF_OMNICLOUD_BASE_URL, normalized)
        }
        lastHealthyBaseUrl = null
    }

    fun setProviderStartCommand(command: String?) {
        val normalized = command?.trim().orEmpty()
        if (normalized.isBlank()) {
            mmkv.removeValueForKey(PREF_OMNICLOUD_START_COMMAND)
        } else {
            mmkv.encode(PREF_OMNICLOUD_START_COMMAND, normalized)
        }
    }

    fun setProviderWorkingDirectory(workingDirectory: String?) {
        val normalized = workingDirectory?.trim().orEmpty()
        if (normalized.isBlank()) {
            mmkv.removeValueForKey(PREF_OMNICLOUD_WORKING_DIRECTORY)
        } else {
            mmkv.encode(PREF_OMNICLOUD_WORKING_DIRECTORY, normalized)
        }
    }

    suspend fun snapshotConfig(context: Context): Map<String, Any?> {
        val runLogFile = File(File(context.filesDir, RUN_LOG_DIR_NAME), RUN_LOG_FILE_NAME)
        val providerHealth = fetchProviderHealth()
        return linkedMapOf(
            "utgEnabled" to isUtgEnabled(),
            "omnicloudBaseUrl" to omniCloudBaseUrl(),
            "resolvedOmnicloudBaseUrl" to resolvedOmniCloudBaseUrl(),
            "providerAutoStartEnabled" to isProviderAutoStartEnabled(),
            "fallbackToVlmOnFailureEnabled" to isFallbackToVlmOnFailureEnabled(),
            "providerStartCommand" to providerStartCommand(),
            "providerWorkingDirectory" to providerWorkingDirectory(),
            "providerStdoutPath" to DEFAULT_PROVIDER_STDOUT_PATH,
            "runLogRecordingEnabled" to isRunLogRecordingEnabled(),
            "runLogPath" to runLogFile.absolutePath,
            "providerHealthy" to (providerHealth?.get("success") == true),
            "providerHealth" to providerHealth,
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
        return linkedMapOf(
            "bridgeBaseUrl" to localBridgeBaseUrl(bridgeState),
            "bridgeToken" to bridgeState.token,
            "resolvedOmnicloudBaseUrl" to resolvedOmniCloudBaseUrl(),
            "providerHealthy" to providerHealthy,
            "providerMessage" to if (providerHealthy) "ok" else "provider_unreachable",
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
                summary = "UTG 已关闭，直接使用 VLM 执行",
            )
        }
        val fallbackAllowed = isFallbackToVlmOnFailureEnabled()
        if (!ensureProviderReady(context)) {
            return if (fallbackAllowed) {
                VLMTaskPreHookResult(
                    kind = "disabled_or_fallback",
                    summary = "UTG provider 不可达，回退 VLM 执行",
                )
            } else {
                VLMTaskPreHookResult(
                    kind = "hard_fail",
                    summary = "UTG provider 不可达，任务中止",
                    fallbackAllowed = false,
                )
            }
        }
        val compile = compile(
            CompileRequest(
                goal = goal,
                context = CompileContext(
                    packageName = currentPackageName?.takeIf { it.isNotBlank() },
                ),
            )
        ) ?: return if (fallbackAllowed) {
            VLMTaskPreHookResult(
                kind = "disabled_or_fallback",
                summary = "UTG compile 请求失败，回退 VLM 执行",
            )
        } else {
            VLMTaskPreHookResult(
                kind = "hard_fail",
                summary = "UTG compile 请求失败，任务中止",
                fallbackAllowed = false,
            )
        }
        if (!compile.success || compile.pathId.isNullOrBlank()) {
            return VLMTaskPreHookResult(
                kind = "miss",
                summary = "${FastPathAttempt(
                    attempted = true,
                    status = "compile_miss",
                    compile = compile,
                ).compileSummary(goal)}，进入 VLM 推理",
                plannerGuidance = FastPathAttempt(
                    attempted = true,
                    status = "compile_miss",
                    compile = compile,
                ).plannerGuidance(goal),
            )
        }
        return VLMTaskPreHookResult(
            kind = "hit",
            summary = "UTG compile hit: ${compile.pathId}，本轮不进入 VLM 推理，直接执行 UTG path",
            pathId = compile.pathId,
            fallbackAllowed = fallbackAllowed,
        )
    }

    suspend fun tryRunFastPath(
        context: Context,
        goal: String,
        currentPackageName: String? = null,
        ensureBridgeState: suspend () -> McpServerState?,
    ): FastPathAttempt {
        if (!isUtgEnabled()) {
            return FastPathAttempt(
                attempted = false,
                status = "disabled",
                fallbackAllowed = true,
                message = "UTG pre-hook 已关闭",
                runLogPath = runLogPath(context),
            )
        }
        val fallbackAllowed = isFallbackToVlmOnFailureEnabled()
        if (!ensureProviderReady(context)) {
            OmniLog.w(TAG, "UTG provider unavailable, skip fast path")
            val attempt = FastPathAttempt(
                attempted = true,
                status = "provider_unavailable",
                fallbackAllowed = fallbackAllowed,
                message = if (fallbackAllowed) {
                    "UTG provider 不可达，已回退 VLM"
                } else {
                    "UTG provider 不可达，未回退 VLM"
                },
                runLogPath = runLogPath(context),
            )
            appendRunLog(context, goal, attempt)
            return attempt
        }
        val compile = compile(
            CompileRequest(
                goal = goal,
                context = CompileContext(
                    packageName = currentPackageName?.takeIf { it.isNotBlank() },
                ),
            )
        ) ?: run {
            val attempt = FastPathAttempt(
                attempted = true,
                status = "compile_request_failed",
                fallbackAllowed = fallbackAllowed,
                message = if (fallbackAllowed) {
                    "UTG compile 请求失败，已回退 VLM"
                } else {
                    "UTG compile 请求失败，未回退 VLM"
                },
                runLogPath = runLogPath(context),
            )
            appendRunLog(context, goal, attempt)
            return attempt
        }
        if (!compile.success || compile.pathId.isNullOrBlank()) {
            val attempt = FastPathAttempt(
                attempted = true,
                status = "compile_miss",
                compile = compile,
                fallbackAllowed = true,
                message = "UTG compile miss，已回退 VLM",
                runLogPath = runLogPath(context),
            )
            appendRunLog(context, goal, attempt)
            return attempt
        }
        val bridgeState = ensureBridgeState() ?: run {
            val attempt = FastPathAttempt(
                attempted = true,
                status = "bridge_unavailable",
                compile = compile,
                fallbackAllowed = fallbackAllowed,
                message = if (fallbackAllowed) {
                    "OOB 本地 bridge 不可达，已回退 VLM"
                } else {
                    "OOB 本地 bridge 不可达，未回退 VLM"
                },
                runLogPath = runLogPath(context),
            )
            appendRunLog(context, goal, attempt)
            return attempt
        }
        val run = runCompiledPath(
            RunCompiledPathRequest(
                goal = goal,
                pathId = compile.pathId,
                slots = compile.slots,
                bridgeBaseUrl = localBridgeBaseUrl(bridgeState),
                bridgeToken = bridgeState.token,
                context = mapOf("source" to "oob_vlm_task"),
                skipTerminalVerify = true,
            )
        ) ?: run {
            val attempt = FastPathAttempt(
                attempted = true,
                status = "run_request_failed",
                compile = compile,
                fallbackAllowed = fallbackAllowed,
                message = if (fallbackAllowed) {
                    "UTG compiled path 请求失败，已回退 VLM"
                } else {
                    "UTG compiled path 请求失败，未回退 VLM"
                },
                runLogPath = runLogPath(context),
            )
            appendRunLog(context, goal, attempt)
            return attempt
        }
        val attempt = FastPathAttempt(
            attempted = true,
            source = if (run.success) "utg_fast_path" else "vlm_fallback",
            status = if (run.success) "success" else "run_failed",
            compile = compile,
            run = run,
            fallbackAllowed = fallbackAllowed,
            message = if (run.success) {
                run.summaryText(goal)
            } else if (fallbackAllowed) {
                "UTG compiled path 执行失败，已回退 VLM"
            } else {
                "UTG compiled path 执行失败，未回退 VLM"
            },
            runLogPath = runLogPath(context),
        )
        appendRunLog(context, goal, attempt)
        return attempt
    }

    suspend fun captureObservation(request: ObservationRequest): ObservationResponse {
        if (request.waitToStabilize) {
            try {
                PageStabilityDetector.awaitStability()
            } catch (e: Exception) {
                OmniLog.w(TAG, "awaitStability failed: ${e.message}")
            }
        }
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
                    var handledByNodeClick = false
                    val rootNode = AssistsService.instance?.rootInActiveWindow
                    if (rootNode != null) {
                        val pointX = x.toInt()
                        val pointY = y.toInt()
                        val bounds = Rect()
                        val stack = ArrayDeque<AccessibilityNodeInfo>()
                        stack.add(rootNode)
                        var bestNode: AccessibilityNodeInfo? = null
                        var bestArea = Int.MAX_VALUE
                        while (stack.isNotEmpty()) {
                            val node = stack.removeLast()
                            node.getBoundsInScreen(bounds)
                            if (bounds.contains(pointX, pointY)) {
                                val supportsClick = node.isClickable ||
                                    node.actionList?.any { it.id == AccessibilityNodeInfo.ACTION_CLICK } == true
                                if (supportsClick) {
                                    val area = bounds.width() * bounds.height()
                                    if (area in 1 until bestArea) {
                                        bestNode = node
                                        bestArea = area
                                    }
                                }
                                for (index in 0 until node.childCount) {
                                    node.getChild(index)?.let { child ->
                                        stack.add(child)
                                    }
                                }
                            }
                        }
                        handledByNodeClick =
                            bestNode?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true
                    }
                    if (!handledByNodeClick) {
                        AccessibilityController.clickCoordinate(x, y)
                    }
                    postActionDelay(action.type)
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
                    postActionDelay(action.type)
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
                    postActionDelay(action.type)
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
                    postActionDelay(action.type)
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
                    postActionDelay(action.type)
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

    suspend fun compile(request: CompileRequest): CompileResponse? {
        return post(
            path = "/compile",
            payload = request,
            responseClass = CompileResponse::class.java,
        )
    }

    suspend fun runCompiledPath(request: RunCompiledPathRequest): RunCompiledPathResponse? {
        return post(
            path = "/run_compiled_path",
            payload = request,
            responseClass = RunCompiledPathResponse::class.java,
        )
    }

    suspend fun appendCanonicalRunLog(
        payload: VLMTaskRunLogPayload,
    ): AppendRunLogResponse? {
        if (!isRunLogRecordingEnabled()) {
            return null
        }
        return post(
            path = "/run_logs/append",
            payload = AppendRunLogRequest(
                runLog = buildCanonicalRunLog(payload)
            ),
            responseClass = AppendRunLogResponse::class.java,
        )
    }

    suspend fun cacheVlmTaskRunLog(taskId: String, payload: VLMTaskRunLogPayload) {
        val normalizedTaskId = taskId.trim()
        if (normalizedTaskId.isEmpty()) {
            return
        }
        runCatching {
            val appendResponse = appendCanonicalRunLog(payload)
            val snapshot = linkedMapOf<String, Any?>(
                "success" to true,
                "task_id" to normalizedTaskId,
                "goal" to payload.goal,
                "run_id" to appendResponse?.runId,
                "run_log_path" to appendResponse?.runLogPath,
                "run_log" to (appendResponse?.runLog ?: buildCanonicalRunLog(payload)),
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
        return payload["success"] == true
    }

    private fun providerStartCommand(): String {
        val stored = mmkv.decodeString(PREF_OMNICLOUD_START_COMMAND)?.trim().orEmpty()
        return if (stored.isNotBlank()) stored else DEFAULT_OMNICLOUD_START_COMMAND
    }

    private fun providerWorkingDirectory(): String? {
        return mmkv.decodeString(PREF_OMNICLOUD_WORKING_DIRECTORY)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
    }

    private fun buildProviderLaunchCommand(command: String, workingDirectory: String?): String {
        return buildString {
            if (!workingDirectory.isNullOrBlank()) {
                append("cd ")
                append(shellQuote(workingDirectory))
                append(" && ")
            }
            append(command.trim())
            append(" >> ")
            append(shellQuote(DEFAULT_PROVIDER_STDOUT_PATH))
            append(" 2>&1")
        }
    }

    private fun runLogPath(context: Context): String {
        return File(File(context.filesDir, RUN_LOG_DIR_NAME), RUN_LOG_FILE_NAME).absolutePath
    }

    private fun appendRunLog(
        context: Context,
        goal: String,
        attempt: FastPathAttempt,
    ) {
        if (!isRunLogRecordingEnabled()) {
            return
        }
        runCatching {
            val dir = File(context.filesDir, RUN_LOG_DIR_NAME)
            if (!dir.exists()) {
                dir.mkdirs()
            }
            val line = gson.toJson(
                linkedMapOf(
                    "recorded_at_ms" to System.currentTimeMillis(),
                    "goal" to goal,
                    "source" to attempt.source,
                    "status" to attempt.status,
                    "fallback_allowed" to attempt.fallbackAllowed,
                    "message" to attempt.message,
                    "run_log_path" to runLogPath(context),
                    "omnicloud_base_url" to omniCloudBaseUrl(),
                    "compile_result" to attempt.compile,
                    "act_result" to attempt.run,
                )
            )
            File(dir, RUN_LOG_FILE_NAME).appendText(
                line + "\n",
                charset = StandardCharsets.UTF_8,
            )
        }.onFailure {
            OmniLog.w(TAG, "appendRunLog failed: ${it.message}")
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
        for (candidateBaseUrl in buildBaseUrlCandidates(baseUrl ?: omniCloudBaseUrl())) {
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

    private fun buildCanonicalRunLog(
        payload: VLMTaskRunLogPayload,
    ): Map<String, Any?> {
        val compileGate = payload.compileGateResult
        val doneReason = when {
            payload.taskReport.success -> "completed"
            payload.taskReport.error.orEmpty().contains("cancel", ignoreCase = true) ||
                payload.taskReport.error.orEmpty().contains("取消") -> "user_cancelled"
            else -> "failed"
        }
        val toStringKeyedMap: (Any?) -> Map<String, Any?> = { raw ->
            val source = raw as? Map<*, *>
            if (source == null) {
                emptyMap()
            } else {
                linkedMapOf<String, Any?>().apply {
                    source.forEach { (key, value) ->
                        if (key != null) {
                            put(key.toString(), value)
                        }
                    }
                }
            }
        }
        val providerRunLog = payload.taskReport.providerRunLogJson
            ?.takeIf { it.isNotBlank() }
            ?.let {
                runCatching {
                    @Suppress("UNCHECKED_CAST")
                    gson.fromJson(it, Map::class.java) as? Map<String, Any?>
                }.getOrNull()
            }
        val providerFinalObservation = toStringKeyedMap(
            providerRunLog?.get("final_observation")
        )
        val finalXml = payload.finalXml?.takeIf { it.isNotBlank() }
            ?: providerFinalObservation["xml"]?.toString()
        val finalPackageName = payload.finalPackageName?.takeIf { it.isNotBlank() }
            ?: providerFinalObservation["package_name"]?.toString()
        val steps = if (payload.taskReport.executionTrace.isNotEmpty()) {
            payload.taskReport.executionTrace.mapIndexed { index, step ->
                buildCanonicalStep(
                    index = index,
                    step = step,
                    payload = payload,
                    isLast = index == payload.taskReport.executionTrace.lastIndex,
                )
            }
        } else if (
            compileGate?.kind == "hit" &&
            !compileGate.pathId.isNullOrBlank() &&
            providerRunLog != null
        ) {
            val providerFrames = (providerRunLog["main_action_frames"] as? List<*>)
                ?.mapNotNull { frame -> frame as? Map<*, *> }
                ?: emptyList()
            val providerExecutedActions = buildList<Map<String, Any?>> {
                providerFrames.forEach { frame ->
                    val action = toStringKeyedMap(frame["executed_action"] ?: frame["action"])
                    if (action.isNotEmpty()) {
                        add(action)
                    }
                }
                if (isEmpty()) {
                    ((providerRunLog["device_actions"] as? List<*>) ?: emptyList<Any?>()).forEach { item ->
                        val actionItem = item as? Map<*, *> ?: return@forEach
                        val kind = actionItem["kind"]?.toString().orEmpty()
                        val controllerId = actionItem["controller_id"]?.toString().orEmpty()
                        if (kind == "act" && controllerId in setOf("", "main_action")) {
                            val action = toStringKeyedMap(actionItem["action"])
                            if (action.isNotEmpty()) {
                                add(action)
                            }
                        }
                    }
                }
            }
            val beforeObservation = if (providerFrames.isNotEmpty()) {
                toStringKeyedMap(providerFrames.first()["before_observation"])
            } else {
                emptyMap()
            }
            listOf(
                linkedMapOf(
                    "step_index" to 0,
                    "observation_before_act" to linkedMapOf(
                        "xml" to beforeObservation["xml"],
                        "package_name" to beforeObservation["package_name"],
                        "activity_name" to beforeObservation["activity_name"],
                        "text" to beforeObservation["text"],
                    ),
                    "compile_result" to linkedMapOf(
                        "success" to true,
                        "path_id" to compileGate.pathId,
                        "slots" to emptyMap<String, Any?>(),
                        "mode" to compileGate.kind,
                        "reason" to compileGate.summary,
                    ),
                    "utg_context_summary" to linkedMapOf(
                        "source" to "oob_vlm_task",
                    ),
                    "plan" to linkedMapOf(
                        "tool_name" to "run_compiled_path",
                        "tool_args" to linkedMapOf(
                            "path_id" to compileGate.pathId,
                            "slots" to emptyMap<String, Any?>(),
                        ),
                        "planner_used" to false,
                        "reason" to "compile_hit",
                    ),
                    "act_request" to linkedMapOf(
                        "tool_name" to "run_compiled_path",
                        "path_id" to compileGate.pathId,
                        "slots" to emptyMap<String, Any?>(),
                    ),
                    "executed_actions" to providerExecutedActions,
                    "act_result" to linkedMapOf(
                        "success" to payload.taskReport.success,
                        "source" to "oob_vlm_task",
                        "result_summary" to linkedMapOf(
                            "message" to payload.taskReport.feedback,
                            "provider_run_log_path" to payload.taskReport.providerRunLogPath,
                            "canonical_run_log_path" to payload.taskReport.canonicalRunLogPath,
                        ),
                        "error_message" to payload.taskReport.error,
                    ),
                    "terminal_state" to linkedMapOf(
                        "terminal_page_reached" to payload.taskReport.success,
                        "reason" to "oob_vlm_task",
                    ),
                    "provider_detail" to linkedMapOf(
                        "utg_run_log" to providerRunLog,
                        "provider_run_log_path" to payload.taskReport.providerRunLogPath,
                        "canonical_run_log_path" to payload.taskReport.canonicalRunLogPath,
                        "final_observation" to linkedMapOf(
                            "xml" to finalXml,
                            "package_name" to finalPackageName,
                        ),
                    ),
                    "started_at" to (
                        providerRunLog["started_at"]?.toString()?.takeIf { it.isNotBlank() }
                            ?: isoFromMs(payload.startedAtMs)
                        ),
                    "finished_at" to (
                        providerRunLog["finished_at"]?.toString()?.takeIf { it.isNotBlank() }
                            ?: isoFromMs(payload.finishedAtMs)
                        ),
                    "duration_ms" to (
                        (providerRunLog["duration_ms"] as? Number)?.toLong()
                            ?: (payload.finishedAtMs - payload.startedAtMs).coerceAtLeast(0L)
                        ),
                )
            )
        } else {
            emptyList()
        }
        return linkedMapOf(
            "goal" to payload.goal,
            "success" to payload.taskReport.success,
            "done_reason" to doneReason,
            "started_at" to isoFromMs(payload.startedAtMs),
            "finished_at" to isoFromMs(payload.finishedAtMs),
            "duration_ms" to (payload.finishedAtMs - payload.startedAtMs).coerceAtLeast(0L),
            "step_count" to steps.size,
            "steps" to steps,
            "final_observation" to linkedMapOf(
                "xml" to finalXml,
                "package_name" to finalPackageName,
            ),
            "extra" to linkedMapOf(
                "source" to "oob_vlm_task",
                "compile_kind" to compileGate?.kind,
                "compile_summary" to compileGate?.summary,
                "error_message" to payload.taskReport.error,
                "fallback_used" to payload.taskReport.fallbackUsed,
                "screenshot_error_code" to payload.taskReport.screenshotErrorCode,
                "stabilization_wait_ms" to payload.taskReport.stabilizationWaitMs,
                "provider_run_log_path" to payload.taskReport.providerRunLogPath,
                "canonical_run_log_path" to payload.taskReport.canonicalRunLogPath,
            ),
        )
    }

    private fun buildCanonicalStep(
        index: Int,
        step: UIStep,
        payload: VLMTaskRunLogPayload,
        isLast: Boolean,
    ): Map<String, Any?> {
        val action = canonicalAction(step.action)
        val isFinished = step.action is FinishedAction
        val resultText = step.result.orEmpty()
        val stepSuccess = if (isLast) {
            payload.taskReport.success
        } else {
            !resultText.contains("失败") && !resultText.contains("错误")
        }
        return linkedMapOf(
            "step_index" to index,
            "observation_before_act" to linkedMapOf(
                "xml" to step.observationXml,
                "package_name" to step.packageName,
                "text" to step.observation,
            ),
            "compile_result" to linkedMapOf(
                "success" to false,
                "mode" to (payload.compileGateResult?.kind ?: "disabled_or_fallback"),
                "reason" to payload.compileGateResult?.summary,
            ),
            "utg_context_summary" to linkedMapOf(
                "source" to "oob_vlm_task",
            ),
            "plan" to if (isFinished) {
                linkedMapOf(
                    "tool_name" to "finish",
                    "tool_args" to emptyMap<String, Any?>(),
                    "planner_used" to true,
                    "reason" to "oob_vlm_task",
                )
            } else {
                linkedMapOf(
                    "tool_name" to "run_action",
                    "tool_args" to linkedMapOf("action" to action),
                    "planner_used" to true,
                    "reason" to "oob_vlm_task",
                )
            },
            "act_request" to if (isFinished) {
                linkedMapOf("tool_name" to "finish")
            } else {
                linkedMapOf(
                    "tool_name" to "run_action",
                    "action" to action,
                )
            },
            "act_result" to linkedMapOf(
                "success" to stepSuccess,
                "source" to "oob_vlm_task",
                "result_summary" to linkedMapOf(
                    "message" to step.result,
                    "thought" to step.thought,
                    "summary" to step.summary,
                ),
                "error_message" to if (stepSuccess) null else resultText.ifBlank { payload.taskReport.error },
            ),
            "terminal_state" to if (isLast) {
                linkedMapOf(
                    "terminal_page_reached" to payload.taskReport.success,
                    "reason" to "oob_vlm_task",
                )
            } else {
                emptyMap<String, Any?>()
            },
            "provider_detail" to linkedMapOf(
                "debug_sidecar" to linkedMapOf(
                    "text_observation" to step.observation,
                    "thought" to step.thought,
                    "summary" to step.summary,
                ),
                "final_observation" to if (isLast) {
                    linkedMapOf(
                        "xml" to payload.finalXml,
                        "package_name" to payload.finalPackageName,
                    )
                } else {
                    emptyMap<String, Any?>()
                },
            ),
            "started_at" to isoFromMs(step.startedAtMs ?: payload.startedAtMs),
            "finished_at" to isoFromMs(step.finishedAtMs ?: payload.finishedAtMs),
            "duration_ms" to (
                ((step.finishedAtMs ?: payload.finishedAtMs) - (step.startedAtMs
                    ?: payload.startedAtMs)).coerceAtLeast(0L)
                ),
        )
    }

    private fun canonicalAction(action: UIAction): Map<String, Any?> {
        return when (action) {
            is ClickAction -> linkedMapOf(
                "type" to "click",
                "params" to linkedMapOf(
                    "x" to action.x,
                    "y" to action.y,
                    "targetDescription" to action.targetDescription,
                ),
            )
            is LongPressAction -> linkedMapOf(
                "type" to "long_press",
                "params" to linkedMapOf(
                    "x" to action.x,
                    "y" to action.y,
                    "targetDescription" to action.targetDescription,
                ),
            )
            is TypeAction -> linkedMapOf(
                "type" to "type",
                "params" to linkedMapOf("text" to action.content),
            )
            is ScrollAction -> linkedMapOf(
                "type" to "scroll",
                "params" to linkedMapOf(
                    "x1" to action.x1,
                    "y1" to action.y1,
                    "x2" to action.x2,
                    "y2" to action.y2,
                    "duration_ms" to (action.duration * 1000).toLong(),
                    "targetDescription" to action.targetDescription,
                ),
            )
            is OpenAppAction -> linkedMapOf(
                "type" to "open_app",
                "params" to linkedMapOf("package_name" to action.packageName),
            )
            is RunCompiledPathAction -> linkedMapOf(
                "type" to "run_compiled_path",
                "params" to linkedMapOf("path_id" to action.pathId),
            )
            is PressHomeAction -> linkedMapOf(
                "type" to "press_key",
                "params" to linkedMapOf("key" to "HOME"),
            )
            is PressBackAction -> linkedMapOf(
                "type" to "press_key",
                "params" to linkedMapOf("key" to "BACK"),
            )
            is WaitAction -> linkedMapOf(
                "type" to "wait",
                "params" to linkedMapOf(
                    "duration_ms" to (action.durationMs ?: action.duration?.times(1000) ?: 1000L),
                ),
            )
            is FinishedAction -> linkedMapOf(
                "type" to "finished",
                "params" to linkedMapOf("content" to action.content),
            )
            is RecordAction -> linkedMapOf(
                "type" to "record",
                "params" to linkedMapOf("content" to action.content),
            )
            is FeedbackAction -> linkedMapOf(
                "type" to "feedback",
                "params" to linkedMapOf("value" to action.value),
            )
            is InfoAction -> linkedMapOf(
                "type" to "info",
                "params" to linkedMapOf("value" to action.value),
            )
            is AbortAction -> linkedMapOf(
                "type" to "abort",
                "params" to linkedMapOf("value" to action.value),
            )
            is RequireUserChoiceAction -> linkedMapOf(
                "type" to "require_user_choice",
                "params" to linkedMapOf(
                    "prompt" to action.prompt,
                    "options" to action.options,
                ),
            )
            is RequireUserConfirmationAction -> linkedMapOf(
                "type" to "require_user_confirmation",
                "params" to linkedMapOf("prompt" to action.prompt),
            )
            is HotKeyAction -> linkedMapOf(
                "type" to "press_key",
                "params" to linkedMapOf("key" to action.key),
            )
        }
    }

    private fun isoFromMs(value: Long?): String? {
        return value?.let { Instant.ofEpochMilli(it).toString() }
    }

    @Suppress("UNUSED_PARAMETER")
    private suspend fun postActionDelay(actionType: String) = Unit

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
