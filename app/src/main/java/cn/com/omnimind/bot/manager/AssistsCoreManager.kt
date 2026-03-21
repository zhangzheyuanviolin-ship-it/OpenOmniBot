package cn.com.omnimind.bot.manager

import android.content.Context
import cn.com.omnimind.accessibility.api.Constant
import cn.com.omnimind.assists.AssistsCore
import cn.com.omnimind.assists.api.bean.TaskParams
import cn.com.omnimind.assists.api.interfaces.OnMessagePushListener
import cn.com.omnimind.assists.controller.accessibility.AccessibilityController
import cn.com.omnimind.assists.task.scheduled.worker.ScheduledStates
import cn.com.omnimind.assists.task.scheduled.worker.toScheduledVLMOperationTaskParamsData
import cn.com.omnimind.baselib.database.DatabaseHelper
import cn.com.omnimind.baselib.database.Conversation
import cn.com.omnimind.baselib.http.Http429Exception
import cn.com.omnimind.baselib.llm.ModelProviderConfig
import cn.com.omnimind.baselib.llm.ModelProviderProfile
import cn.com.omnimind.baselib.llm.ModelProviderConfigStore
import cn.com.omnimind.baselib.llm.ModelSceneRegistry
import cn.com.omnimind.baselib.llm.ProviderModelOption
import cn.com.omnimind.baselib.llm.SceneCatalogItem
import cn.com.omnimind.baselib.llm.SceneModelBindingEntry
import cn.com.omnimind.baselib.llm.SceneModelBindingStore
import cn.com.omnimind.baselib.llm.SceneModelOverrideEntry
import cn.com.omnimind.baselib.llm.SceneModelOverrideStore
import cn.com.omnimind.baselib.util.APPPackageUtil
import cn.com.omnimind.baselib.util.OmniLog
import cn.com.omnimind.baselib.util.exception.PermissionException
import cn.com.omnimind.bot.ui.scheduled.ScheduledTaskReminderLoader
import cn.com.omnimind.bot.util.AssistsUtil
import cn.com.omnimind.assists.controller.http.HttpController
import cn.com.omnimind.baselib.util.SchemeUtil
import cn.com.omnimind.bot.agent.AgentCallback
import cn.com.omnimind.bot.agent.AgentAlarmToolService
import cn.com.omnimind.bot.agent.AgentModelOverride
import cn.com.omnimind.bot.agent.AgentResult
import cn.com.omnimind.bot.agent.AgentRuntimeContextRepository
import cn.com.omnimind.bot.agent.AgentScheduleToolBridge
import cn.com.omnimind.bot.agent.AgentWorkspaceManager
import cn.com.omnimind.bot.agent.OmniAgentExecutor
import cn.com.omnimind.bot.agent.SkillIndexService
import cn.com.omnimind.bot.agent.ToolExecutionResult
import cn.com.omnimind.bot.mem0.Mem0ToolUtils
import cn.com.omnimind.bot.mcp.RemoteMcpConfigStore
import cn.com.omnimind.bot.util.TaskCompletionNavigator
import cn.com.omnimind.bot.workspace.WorkspaceStorageAccess
import cn.com.omnimind.uikit.UIKit
import cn.com.omnimind.uikit.loader.ScreenMaskLoader
import com.google.gson.Gson
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlin.collections.mapOf
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class AssistsCoreManager(private val context: Context) : OnMessagePushListener {
    private val TAG = "[AssistsCoreManager]"

    companion object {
        private const val SUMMARY_TASK_PREFIX_VLM = "vlm-summary-"
        private const val SUMMARY_TASK_PREFIX_TASK = "task-summary-"

        @Volatile
        private var mainEngineChannel: MethodChannel? = null

        fun bindMainEngineChannel(channel: MethodChannel) {
            mainEngineChannel = channel
        }

        private fun isSummaryTask(taskId: String): Boolean {
            return taskId.startsWith(SUMMARY_TASK_PREFIX_VLM) ||
                taskId.startsWith(SUMMARY_TASK_PREFIX_TASK)
        }
    }
    // 用于存储需要等待用户操作的回调结果
    private lateinit var channel: MethodChannel
    private var mainJob: CoroutineScope = CoroutineScope(Dispatchers.Main)
    private var workJob: CoroutineScope = CoroutineScope(Dispatchers.Default)
    private val activeAgentLock = Any()

    @Volatile
    private var activeAgentJob: Job? = null

    // 当前活跃的对话ID
    private var currentConversationId: Long? = null

    private fun registerActiveAgentJob(job: Job) {
        val previousJob = synchronized(activeAgentLock) {
            val previous = activeAgentJob
            activeAgentJob = job
            previous
        }
        previousJob?.cancel(CancellationException("Agent run replaced by a new request"))
    }

    private fun clearActiveAgentJob(job: Job) {
        synchronized(activeAgentLock) {
            if (activeAgentJob == job) {
                activeAgentJob = null
            }
        }
    }

    private fun cancelActiveAgentRun(reason: String) {
        val jobToCancel = synchronized(activeAgentLock) {
            val current = activeAgentJob
            activeAgentJob = null
            current
        }
        if (jobToCancel != null) {
            OmniLog.i(TAG, "Cancelling active agent run: $reason")
            jobToCancel.cancel(CancellationException(reason))
        }
    }

    private fun ModelProviderConfig.toMap(): Map<String, Any?> {
        return mapOf(
            "id" to id,
            "name" to name,
            "baseUrl" to baseUrl,
            "apiKey" to apiKey,
            "source" to source,
            "configured" to isConfigured()
        )
    }

    private fun ModelProviderProfile.toMap(): Map<String, Any?> {
        return mapOf(
            "id" to id,
            "name" to name,
            "baseUrl" to baseUrl,
            "apiKey" to apiKey,
            "configured" to isConfigured()
        )
    }

    private fun ProviderModelOption.toMap(): Map<String, Any?> {
        return mapOf(
            "id" to id,
            "displayName" to displayName,
            "ownedBy" to ownedBy
        )
    }

    private fun SceneCatalogItem.toMap(): Map<String, Any?> {
        return mapOf(
            "sceneId" to sceneId,
            "description" to description,
            "defaultModel" to defaultModel,
            "effectiveModel" to effectiveModel,
            "effectiveProviderProfileId" to effectiveProviderProfileId,
            "effectiveProviderProfileName" to effectiveProviderProfileName,
            "boundProviderProfileId" to boundProviderProfileId,
            "boundProviderProfileName" to boundProviderProfileName,
            "transport" to transport,
            "configSource" to configSource,
            "overrideApplied" to overrideApplied,
            "overrideModel" to overrideModel,
            "providerConfigured" to providerConfigured,
            "bindingExists" to bindingExists,
            "bindingProfileMissing" to bindingProfileMissing
        )
    }

    private fun SceneModelOverrideEntry.toMap(): Map<String, Any?> {
        return mapOf(
            "sceneId" to sceneId,
            "model" to model
        )
    }

    private fun SceneModelBindingEntry.toMap(): Map<String, Any?> {
        return mapOf(
            "sceneId" to sceneId,
            "providerProfileId" to providerProfileId,
            "modelId" to modelId
        )
    }

    fun setChannel(_channel: MethodChannel) {
        OmniLog.e(TAG, "setChannel")
        this.channel = _channel
    }

    private fun currentChannelOrNull(): MethodChannel? {
        return if (this::channel.isInitialized) channel else null
    }

    /**
     * 统一的 Flutter 事件派发：
     * 1) 始终在主线程调用；
     * 2) 当前通道失败时回退到主引擎通道；
     * 3) 避免事件派发异常导致进程崩溃。
     */
    private fun invokeFlutterEventSafely(method: String, arguments: Any? = null) {
        val current = currentChannelOrNull()
        val main = mainEngineChannel
        val channels = listOfNotNull(current, main).distinct()
        if (channels.isEmpty()) {
            OmniLog.w(TAG, "skip invoke $method: flutter channel unavailable")
            return
        }

        var lastError: Exception? = null
        for (target in channels) {
            try {
                target.invokeMethod(method, arguments)
                return
            } catch (e: Exception) {
                lastError = e
                OmniLog.e(TAG, "invoke $method failed on one channel: ${e.message}")
            }
        }
        OmniLog.e(TAG, "invoke $method failed on all channels: ${lastError?.message}")
    }

    suspend fun invokeFlutterMethodForAgent(method: String, arguments: Map<String, Any?>): Any? {
        val targetChannel = mainEngineChannel ?: if (this::channel.isInitialized) channel else null
        if (targetChannel == null) {
            throw IllegalStateException("Flutter channel unavailable for $method")
        }
        return suspendCancellableCoroutine { continuation ->
            mainJob.launch(Dispatchers.Main) {
                try {
                    targetChannel.invokeMethod(method, arguments, object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            if (!continuation.isCompleted) {
                                continuation.resume(result)
                            }
                        }

                        override fun error(
                            errorCode: String,
                            errorMessage: String?,
                            errorDetails: Any?
                        ) {
                            if (!continuation.isCompleted) {
                                continuation.resumeWithException(
                                    IllegalStateException(
                                        "$errorCode: ${errorMessage ?: "Flutter bridge error"}"
                                    )
                                )
                            }
                        }

                        override fun notImplemented() {
                            if (!continuation.isCompleted) {
                                continuation.resumeWithException(
                                    NotImplementedError("Flutter method not implemented: $method")
                                )
                            }
                        }
                    })
                } catch (e: Exception) {
                    if (!continuation.isCompleted) {
                        continuation.resumeWithException(e)
                    }
                }
            }
        }
    }

    private fun toStringAnyMap(value: Any?): Map<String, Any?> {
        return (value as? Map<*, *>)?.entries?.associate { (key, rawValue) ->
            key.toString() to normalizeChannelValue(rawValue)
        } ?: emptyMap()
    }

    private fun toListOfStringAnyMap(value: Any?): List<Map<String, Any?>> {
        return (value as? List<*>)?.map { toStringAnyMap(it) } ?: emptyList()
    }

    private fun normalizeChannelValue(value: Any?): Any? {
        return when (value) {
            is Map<*, *> -> toStringAnyMap(value)
            is List<*> -> value.map { normalizeChannelValue(it) }
            else -> value
        }
    }

    private data class AgentToolMeta(
        val toolType: String,
        val displayName: String,
        val serverName: String? = null
    )

    private fun resolveAgentToolMeta(toolName: String): AgentToolMeta {
        return when (toolName) {
            "context_apps_query" -> AgentToolMeta("builtin", "查询已安装应用")
            "context_time_now" -> AgentToolMeta("builtin", "查询当前时间")
            "vlm_task" -> AgentToolMeta("builtin", "视觉执行")
            "browser_use" -> AgentToolMeta("browser", "浏览器操作")
            "terminal_execute" -> AgentToolMeta("terminal", "终端执行")
            "terminal_session_start" -> AgentToolMeta("terminal", "启动终端会话")
            "terminal_session_exec" -> AgentToolMeta("terminal", "执行会话命令")
            "terminal_session_read" -> AgentToolMeta("terminal", "读取会话输出")
            "terminal_session_stop" -> AgentToolMeta("terminal", "结束终端会话")
            "file_read" -> AgentToolMeta("workspace", "读取文件")
            "file_write" -> AgentToolMeta("workspace", "写入文件")
            "file_edit" -> AgentToolMeta("workspace", "编辑文件")
            "file_list" -> AgentToolMeta("workspace", "列出文件")
            "file_search" -> AgentToolMeta("workspace", "搜索文件")
            "file_stat" -> AgentToolMeta("workspace", "查看文件信息")
            "file_move" -> AgentToolMeta("workspace", "移动文件")
            "schedule_task_create" -> AgentToolMeta("schedule", "创建定时任务")
            "schedule_task_list" -> AgentToolMeta("schedule", "查看定时任务")
            "schedule_task_update" -> AgentToolMeta("schedule", "修改定时任务")
            "schedule_task_delete" -> AgentToolMeta("schedule", "删除定时任务")
            "alarm_reminder_create" -> AgentToolMeta("alarm", "创建提醒闹钟")
            "alarm_reminder_list" -> AgentToolMeta("alarm", "查看提醒闹钟")
            "alarm_reminder_delete" -> AgentToolMeta("alarm", "删除提醒闹钟")
            "calendar_list" -> AgentToolMeta("calendar", "查看日历列表")
            "calendar_event_create" -> AgentToolMeta("calendar", "创建日程")
            "calendar_event_list" -> AgentToolMeta("calendar", "查询日程")
            "calendar_event_update" -> AgentToolMeta("calendar", "修改日程")
            "calendar_event_delete" -> AgentToolMeta("calendar", "删除日程")
            in Mem0ToolUtils.toolDisplayNames.keys -> AgentToolMeta(
                "mem0",
                Mem0ToolUtils.displayName(toolName)
            )
            else -> {
                val match = Regex("^mcp__(.+?)__(.+)$").find(toolName)
                if (match != null) {
                    val serverId = match.groupValues[1]
                    val rawToolName = match.groupValues[2]
                    val serverName = RemoteMcpConfigStore.getServer(serverId)?.name
                    AgentToolMeta("mcp", rawToolName, serverName)
                } else {
                    AgentToolMeta("builtin", toolName)
                }
            }
        }
    }

    private fun buildToolStartPayload(toolName: String, argsJson: String): Map<String, Any?> {
        val meta = resolveAgentToolMeta(toolName)
        return linkedMapOf<String, Any?>(
            "toolName" to toolName,
            "displayName" to meta.displayName,
            "toolType" to meta.toolType,
            "serverName" to meta.serverName,
            "args" to argsJson,
            "argsJson" to argsJson
        ).apply {
            extractToolTitleSummary(toolName, argsJson)?.let { summary ->
                put("summary", summary)
            }
        }
    }

    private fun extractToolTitleSummary(toolName: String, argsJson: String): String? {
        if (toolName != "browser_use" || argsJson.isBlank()) return null
        return runCatching {
            JSONObject(argsJson).optString("tool_title").trim()
        }.getOrNull()?.takeIf { it.isNotEmpty() }
    }

    private fun buildToolProgressPayload(
        toolName: String,
        progress: String,
        argsJson: String = "",
        extras: Map<String, Any?> = emptyMap()
    ): Map<String, Any?> {
        val meta = resolveAgentToolMeta(toolName)
        val payload = linkedMapOf<String, Any?>(
            "toolName" to toolName,
            "displayName" to meta.displayName,
            "toolType" to meta.toolType,
            "serverName" to meta.serverName,
            "progress" to progress,
            "args" to argsJson,
            "argsJson" to argsJson
        )
        payload.putAll(extras)
        return payload
    }

    private fun buildToolCompletePayload(
        toolName: String,
        result: ToolExecutionResult,
        argsJson: String = ""
    ): Map<String, Any?> {
        val meta = resolveAgentToolMeta(toolName)
        val summary: String
        val previewJson: String
        val rawResultJson: String
        val success: Boolean
        val status: String
        when (result) {
            is ToolExecutionResult.ChatMessage -> {
                summary = result.message
                previewJson = JSONObject(mapOf("message" to result.message)).toString()
                rawResultJson = previewJson
                success = true
                status = "success"
            }
            is ToolExecutionResult.Clarify -> {
                summary = result.question
                previewJson = JSONObject(
                    mapOf(
                        "question" to result.question,
                        "missingFields" to (result.missingFields ?: emptyList<String>())
                    )
                ).toString()
                rawResultJson = previewJson
                success = true
                status = "success"
            }
            is ToolExecutionResult.VlmTaskStarted -> {
                summary = "已启动视觉执行任务"
                previewJson = JSONObject(
                    mapOf("taskId" to result.taskId, "goal" to result.goal)
                ).toString()
                rawResultJson = previewJson
                success = true
                status = "success"
            }
            is ToolExecutionResult.PermissionRequired -> {
                summary = "缺少权限：${result.missing.joinToString("、")}"
                previewJson = JSONObject(mapOf("missing" to result.missing)).toString()
                rawResultJson = previewJson
                success = false
                status = "interrupted"
            }
            is ToolExecutionResult.ScheduleResult -> {
                summary = result.summaryText
                previewJson = result.previewJson
                rawResultJson = result.previewJson
                success = result.success
                status = if (result.success) "success" else "error"
            }
            is ToolExecutionResult.McpResult -> {
                summary = result.summaryText
                previewJson = result.previewJson
                rawResultJson = result.rawResultJson
                success = result.success
                status = if (result.success) "success" else "error"
            }
            is ToolExecutionResult.Mem0Result -> {
                summary = result.summaryText
                previewJson = result.previewJson
                rawResultJson = result.rawResultJson
                success = result.success
                status = if (result.success) "success" else "error"
            }
            is ToolExecutionResult.TerminalResult -> {
                summary = result.summaryText
                previewJson = result.previewJson
                rawResultJson = result.rawResultJson
                success = result.success
                status = if (result.success) "success" else "error"
            }
            is ToolExecutionResult.ContextResult -> {
                summary = result.summaryText
                previewJson = result.previewJson
                rawResultJson = result.rawResultJson
                success = result.success
                status = if (result.success) "success" else "error"
            }
            is ToolExecutionResult.Error -> {
                summary = result.message
                previewJson = JSONObject(
                    mapOf("toolName" to result.toolName, "message" to result.message)
                ).toString()
                rawResultJson = previewJson
                success = false
                status = "error"
            }
        }

        val payload = linkedMapOf<String, Any?>(
            "toolName" to toolName,
            "displayName" to meta.displayName,
            "toolType" to meta.toolType,
            "serverName" to meta.serverName,
            "status" to status,
            "summary" to summary,
            "args" to argsJson,
            "argsJson" to argsJson,
            "resultPreviewJson" to previewJson,
            "rawResultJson" to rawResultJson,
            "success" to success
        )
        if (result is ToolExecutionResult.TerminalResult) {
            payload["terminalOutput"] = result.terminalOutput
            payload["terminalSessionId"] = result.terminalSessionId
            payload["terminalStreamState"] = result.terminalStreamState
        }
        if (result.artifacts.isNotEmpty()) {
            payload["artifacts"] = result.artifacts.map { it.toPayload() }
        }
        result.workspaceId?.let { payload["workspaceId"] = it }
        if (result.actions.isNotEmpty()) {
            payload["actions"] = result.actions.map { it.toPayload() }
        }
        return payload
    }


    /**
     * 执行陪伴模式
     */
    fun createCompanionTask(
        call: MethodCall, result: MethodChannel.Result,
    ) {
        val listener = this;
        mainJob.launch {
            try {
                AssistsUtil.Core.createCompanionTask(
                    context, listener
                )
                withContext(Dispatchers.Main) {
                    result.success("SUCCESS")
                }
            } catch (e: PermissionException) {
                withContext(Dispatchers.Main) {
                    result.error("PERMISSION_ERROR", e.message, null);
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("DO_TASK_ERROR", e.message, null)
                }
            }
        }

    }

    /**
     * 取消陪伴模式
     */
    fun cancelTask(
        call: MethodCall, result: MethodChannel.Result,
    ) {
        mainJob.launch {
            try {
                AssistsUtil.Core.finishTask(context)
                withContext(Dispatchers.Main) {
                    result.success("SUCCESS")
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("CANCEL_TASK_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * 取消正在运行的任务，不影响陪伴模式
     */
    fun cancelRunningTask(
        call: MethodCall, result: MethodChannel.Result,
    ) {
        mainJob.launch {
            try {
                cancelActiveAgentRun("cancelRunningTask")
                AssistsUtil.Core.cancelRunningTask()
                withContext(Dispatchers.Main) {
                    result.success("SUCCESS")
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "cancelRunningTask error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("CANCEL_RUNNING_TASK_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * 提供用户输入给VLM任务（响应INFO动作）
     */
    fun provideUserInputToVLMTask(call: MethodCall, result: MethodChannel.Result) {
        try {
            val userInput = call.argument<String>("userInput")!!
            val success = AssistsUtil.Core.provideUserInputToVLMTask(userInput)
            mainJob.launch(Dispatchers.Main) {
                result.success(success)
            }
        } catch (e: Exception) {
            OmniLog.e(TAG, "提供用户输入失败: ${e.message}")
            mainJob.launch(Dispatchers.Main) {
                result.error("PROVIDE_USER_INPUT_ERROR", e.message, null)
            }
        }
    }

    /**
     * 通知VLM任务总结Sheet已准备就绪
     */
    fun notifySummarySheetReady(call: MethodCall, result: MethodChannel.Result) {
        try {
            val success = AssistsUtil.Core.notifySummarySheetReady()
            mainJob.launch(Dispatchers.Main) {
                if (success) {
                    result.success("SUCCESS")
                } else {
                    result.error("NO_RUNNING_VLM_TASK", "没有正在运行的VLM任务", null)
                }
            }
        } catch (e: Exception) {
            OmniLog.e(TAG, "通知总结Sheet准备就绪失败: ${e.message}")
            mainJob.launch(Dispatchers.Main) {
                result.error("NOTIFY_SUMMARY_SHEET_READY_ERROR", e.message, null)
            }
        }
    }

    /**
     * 取消聊天任务
     */
    fun cancelChatTask(
        call: MethodCall, result: MethodChannel.Result,
    ) {
        mainJob.launch {
            try {
                cancelActiveAgentRun("cancelChatTask")
                AssistsUtil.Core.cancelChatTask()
                withContext(Dispatchers.Main) {
                    result.success("SUCCESS")
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("CANCEL_MESSAGE_ERROR", e.message, null)
                }
            }
        }
    }

    fun isCompanionTaskRunning(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        mainJob.launch {
            try {
                var isRunning = AssistsUtil.Core.isCompanionTaskRunning()
                withContext(Dispatchers.Main) {
                    result.success(isRunning)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.success(false)
                }
            }
        }
    }

    /**
     * 取消陪伴任务的回到桌面操作
     */
    fun cancelCompanionGoHome(
        call: MethodCall, result: MethodChannel.Result,
    ) {
        mainJob.launch {
            try {
                AssistsUtil.Core.cancelCompanionGoHome()
                withContext(Dispatchers.Main) {
                    result.success("SUCCESS")
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("CANCEL_GO_HOME_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * Trigger the system Home action.
     */
    fun pressHome(
        call: MethodCall, result: MethodChannel.Result,
    ) {
        mainJob.launch {
            try {
                if (!AssistsCore.isAccessibilityServiceEnabled()) {
                    throw PermissionException("Accessibility service is not enabled")
                }
                AccessibilityController.initController()
                AccessibilityController.goHome()
                withContext(Dispatchers.Main) {
                    result.success("SUCCESS")
                }
            } catch (e: PermissionException) {
                withContext(Dispatchers.Main) {
                    result.error("PERMISSION_ERROR", e.message, null)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("PRESS_HOME_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * 创建聊天任务
     */
    fun createChatTask(
        call: MethodCall, result: MethodChannel.Result,
    ) {

        try {
            val taskID = call.argument<String>("taskID")!!
            val content = call.argument<List<Map<String, Any>>>("content")!!
            val provider = call.argument<String>("provider")
            val openClawConfigMap = call.argument<Map<String, Any>>("openClawConfig")
            val openClawConfig = openClawConfigMap?.let { map ->
                val baseUrl = map["baseUrl"] as? String ?: ""
                if (baseUrl.isBlank()) {
                    null
                } else {
                    cn.com.omnimind.assists.api.bean.TaskParams.OpenClawConfig(
                        baseUrl = baseUrl,
                        token = map["token"] as? String,
                        userId = map["userId"] as? String,
                        sessionKey = map["sessionKey"] as? String
                    )
                }
            }
            AssistsUtil.Core.createChatTask(
                taskID, content, this@AssistsCoreManager, provider, openClawConfig
            )
            mainJob.launch(Dispatchers.Main) {
                result.success("SUCCESS")
            }
        } catch (e: PermissionException) {
            mainJob.launch(Dispatchers.Main) {
                result.error("PERMISSION_ERROR", e.message, null);
            }
        } catch (e: Exception) {
            mainJob.launch(Dispatchers.Main) {
                result.error("DO_TASK_ERROR", e.message, null)
            }
        }

    }


    override suspend fun onChatMessage(taskID: String, content: String, type: String?) {
        withContext(Dispatchers.Main) {
            try {
                val isSummary = isSummaryTask(taskID)
                val mainChannel = mainEngineChannel

                if (isSummary && mainChannel != null && mainChannel != channel) {
                    mainChannel.invokeMethod(
                        "onChatMessage", mapOf(
                            "taskID" to taskID, "content" to content, "type" to type
                        )
                    )
                    // 如果当前不是主引擎通道，避免在半屏重复展示
                    return@withContext
                }

                channel.invokeMethod(
                    "onChatMessage", mapOf(
                        "taskID" to taskID, "content" to content, "type" to type
                    )
                )
            } catch (e: Exception) {
                OmniLog.e(TAG, "onChatMessage error: ${e.message}")
            }

        }
    }

    override suspend fun onChatMessageEnd(taskID: String) {
        withContext(Dispatchers.Main) {
            try {
                val isSummary = isSummaryTask(taskID)
                val mainChannel = mainEngineChannel

                if (isSummary && mainChannel != null && mainChannel != channel) {
                    mainChannel.invokeMethod(
                        "onChatMessageEnd", mapOf(
                            "taskID" to taskID
                        )
                    )
                    // 如果当前不是主引擎通道，避免在半屏重复展示
                    return@withContext
                }

                channel.invokeMethod(
                    "onChatMessageEnd", mapOf(
                        "taskID" to taskID
                    )
                )
            } catch (e: Exception) {
                OmniLog.e(TAG, "onChatMessageEnd error: ${e.message}")
            }

        }
    }


    override fun onTaskFinish() {
        mainJob.launch(Dispatchers.Main) {
            invokeFlutterEventSafely("onTaskFinish", HashMap<String, String>())
        }
    }

    override fun onVLMTaskFinish() {
        handleVlmTaskFinished("assists_core_listener")
    }

    private fun handleVlmTaskFinished(source: String, taskId: String? = null) {
        mainJob.launch(Dispatchers.Main) {
            OmniLog.d(TAG, "收到 VLM 任务完成回调: source=$source")
            navigateBackToChatIfNeeded()
            invokeFlutterEventSafely(
                "onVLMTaskFinish",
                taskId?.let { mapOf("taskId" to it) } ?: HashMap<String, String>()
            )
        }
    }

    override fun onVLMRequestUserInput(question: String) {
        mainJob.launch(Dispatchers.Main) {
            invokeFlutterEventSafely(
                "onVLMRequestUserInput", mapOf(
                    "question" to question
                )
            )
            OmniLog.d(TAG, "已通知Flutter层VLM请求用户输入：$question")
        }
    }

    fun createVLMOperationTask(
        call: MethodCall, result: MethodChannel.Result,
    ) {


        val taskId = call.argument<String>("taskId")?.trim().orEmpty()
        val needSummary = call.argument<Boolean>("needSummary") ?: false
        val skipGoHome = call.argument<Boolean>("skipGoHome") ?: false
        val vlmListener = if (taskId.isEmpty()) {
            this@AssistsCoreManager
        } else {
            object : OnMessagePushListener by this@AssistsCoreManager {
                override fun onVLMTaskFinish() {
                    handleVlmTaskFinished("create_vlm_operation_task", taskId)
                }

                override fun onVLMRequestUserInput(question: String) {
                    mainJob.launch(Dispatchers.Main) {
                        invokeFlutterEventSafely(
                            "onVLMRequestUserInput",
                            mapOf(
                                "question" to question,
                                "taskId" to taskId
                            )
                        )
                    }
                }
            }
        }
        mainJob.launch {
            try {
                AssistsUtil.Core.createVLMOperationTask(
                    context,
                    call.argument<String>("goal")!!,
                    call.argument<String>("model"),
                    call.argument<Int>("maxSteps"),
                    call.argument<String>("packageName"),
                    vlmListener,
                    needSummary,
                    skipGoHome
                )
                withContext(Dispatchers.Main) {
                    result.success("SUCCESS")
                }
            } catch (e: PermissionException) {
                withContext(Dispatchers.Main) {
                    result.error("PERMISSION_ERROR", e.message, null)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("DO_TASK_ERROR", e.message, null)
                }
            }
        }

    }

    /**
     * 获取已安装应用（包名与应用名）
     */
    fun getInstalledApplications(call: MethodCall, result: MethodChannel.Result) {
        workJob.launch {
            try {
                val pm = context.packageManager
                val applications = pm.getInstalledApplications(0)
                    .filter { pm.getLaunchIntentForPackage(it.packageName) != null }
                    .sortedBy { pm.getApplicationLabel(it).toString() }

                val list = applications.map { appInfo ->
                    mapOf(
                        "package_name" to appInfo.packageName,
                        "app_name" to pm.getApplicationLabel(appInfo).toString()
                    )
                }
                OmniLog.v(TAG, "getInstalledApplications size=${list.size}")

                withContext(Dispatchers.Main) {
                    result.success(list)
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "获取已安装应用失败: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("GET_INSTALLED_APPS_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * 获取已安装应用（包名与应用名，附带图标更新）
     */
    fun getInstalledApplicationsWithIconUpdate(call: MethodCall, result: MethodChannel.Result) {
        workJob.launch {
            try {
                val pm = context.packageManager
                val applications = pm.getInstalledApplications(0)
                    .filter { pm.getLaunchIntentForPackage(it.packageName) != null }
                    .sortedBy { pm.getApplicationLabel(it).toString() }

                val list = applications.map { appInfo ->
                    val packageName = appInfo.packageName
                    val appName = pm.getApplicationLabel(appInfo).toString()
                    var iconPath = ""
                    
                    // 查询数据库中是否已有该应用的图标
                    var appIcon = DatabaseHelper.getAppIconByPackageName(packageName)
                    
                    // 如果数据库中没有图标，则获取并保存
                    if (appIcon == null && appName.isNotEmpty()) {
                        val iconBase64 = APPPackageUtil.getAppIconBase64(context, packageName)
                        iconPath = APPPackageUtil.getAppIconFilePath(context, packageName)
                        
                        if (iconBase64.isNotEmpty()) {
                            DatabaseHelper.insertAppIcon(
                                appName = appName,
                                packageName = packageName,
                                iconBase64 = iconBase64,
                                iconPath = iconPath
                            )
                        }
                    }
                    
                    mapOf(
                        "package_name" to packageName,
                        "app_name" to appName,
                        "app_icon" to iconPath
                    )
                }
                OmniLog.v(TAG, "getInstalledApplications size=${list.size}")

                withContext(Dispatchers.Main) {
                    result.success(list)
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "获取已安装应用失败: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("GET_INSTALLED_APPS_ERROR", e.message, null)
                }
            }
        }
    }

    fun isPackageAuthorized(call: MethodCall, result: MethodChannel.Result) {
        val packageName = call.argument<String>("packageName") ?: ""
        mainJob.launch(Dispatchers.Main) {
            result.success(AssistsUtil.Core.isPackageAuthorized(packageName))
        }
    }

    fun scheduleVLMOperationTask(
        call: MethodCall, result: MethodChannel.Result,
    ) {

        try {
            val needSummary = call.argument<Boolean>("needSummary") ?: false
            mainJob.launch {
                AssistsUtil.Core.scheduleVLMOperationTask(
                    context,
                    call.argument<String>("goal")!!,
                    call.argument<String>("model"),
                    call.argument<Int>("maxSteps"),
                    call.argument<String>("packageName"),
                    call.argument<Int>("times")!!.toLong(),
                    call.argument<String>("title")!!,
                    call.argument<String>("subTitle"),
                    call.argument<String>("extraJson"),
                    this@AssistsCoreManager,
                    needSummary
                )
                withContext(Dispatchers.Main){
                    result.success("SUCCESS")
                }
            }


        } catch (e: PermissionException) {
            mainJob.launch(Dispatchers.Main) {
                result.error("PERMISSION_ERROR", e.message, null);
            }
        }

    }

    fun getScheduleInfo(
        call: MethodCall, result: MethodChannel.Result,
    ) {
        try {
            val status = AssistsUtil.Core.getScheduleStatus()
            val scheduleStatus = status.toString()
            val hasScheduleTask = status != null
            val canCreateScheduleTask =
                status == null || (status != ScheduledStates.SCHEDULED && status != ScheduledStates.RUNNING)
            val scheduleTaskParams = AssistsUtil.Core.getScheduleParams()
            val taskParamsJson = when (scheduleTaskParams?.taskParams) {
                is TaskParams.ScheduledVLMOperationTaskParams -> {
                    val params =
                        (scheduleTaskParams.taskParams as TaskParams.ScheduledVLMOperationTaskParams).toScheduledVLMOperationTaskParamsData()
                    Gson().toJson(params)
                }

                else -> {
                    ""
                }
            }
            val map = mapOf(
                "scheduleStatus" to scheduleStatus,
                "hasScheduleTask" to hasScheduleTask,
                "canCreateScheduleTask" to canCreateScheduleTask,
                "taskParamsJson" to taskParamsJson,
                "delayTimes" to scheduleTaskParams?.delayTimes,
                "startTimeStamp" to scheduleTaskParams?.startTimeStamp


            )
            mainJob.launch(Dispatchers.Main) {
                result.success(map)
            }
        } catch (e: Error) {
            mainJob.launch(Dispatchers.Main) {
                result.error("GET_SCHEDULEINFO_ERROR", e.message, null);
            }
        }
    }


    fun clearScheduleTask(call: MethodCall, result: MethodChannel.Result) {
        try {
            AssistsUtil.Core.clearScheduleTask()
            mainJob.launch(Dispatchers.Main) {
                result.success("SUCCESS")
            }
        } catch (e: Error) {
            mainJob.launch(Dispatchers.Main) {
                result.error("CLEAR_SCHEDULE_TASK_ERROR", e.message, null);
            }
        }
    }

    fun doScheduleNow(call: MethodCall, result: MethodChannel.Result) {
        try {
            AssistsUtil.Core.doScheduleNow()
            mainJob.launch(Dispatchers.Main) {
                result.success("SUCCESS")
            }
        } catch (e: Error) {
            mainJob.launch(Dispatchers.Main) {
                result.error("DO_SCHEDULE_NOW_ERROR", e.message, null);
            }
        }
    }

    fun cancelScheduleTask(call: MethodCall, result: MethodChannel.Result) {
        try {
            AssistsUtil.Core.cancelScheduleTask()
            mainJob.launch(Dispatchers.Main) {
                result.success("SUCCESS")
            }
        } catch (e: Error) {
            mainJob.launch(Dispatchers.Main) {
                result.error("CANCEL_SCHEDULE_TASK_ERROR", e.message, null);
            }
        }
    }

    /**
     * 查询统一 Agent 创建的 exact alarm 提醒列表
     */
    fun listAgentExactAlarms(call: MethodCall, result: MethodChannel.Result) {
        workJob.launch {
            try {
                val alarms = AgentAlarmToolService(context).listExactReminders()
                withContext(Dispatchers.Main) {
                    result.success(alarms)
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "listAgentExactAlarms error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("LIST_AGENT_EXACT_ALARMS_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * 删除统一 Agent 创建的 exact alarm 提醒
     */
    fun deleteAgentExactAlarm(call: MethodCall, result: MethodChannel.Result) {
        val alarmId = call.argument<String>("alarmId")?.trim().orEmpty()
        if (alarmId.isEmpty()) {
            result.error("INVALID_ARGUMENTS", "alarmId is empty", null)
            return
        }
        workJob.launch {
            try {
                val payload = AgentAlarmToolService(context).deleteExactReminder(alarmId)
                withContext(Dispatchers.Main) {
                    result.success(payload)
                }
            } catch (e: IllegalArgumentException) {
                OmniLog.e(TAG, "deleteAgentExactAlarm not found: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("AGENT_EXACT_ALARM_NOT_FOUND", e.message, null)
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "deleteAgentExactAlarm error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("DELETE_AGENT_EXACT_ALARM_ERROR", e.message, null)
                }
            }
        }
    }

    fun getAlarmSettings(call: MethodCall, result: MethodChannel.Result) {
        try {
            val payload = AgentAlarmToolService(context).getAlarmSettings()
            result.success(payload)
        } catch (e: Exception) {
            OmniLog.e(TAG, "getAlarmSettings error: ${e.message}")
            result.error("GET_ALARM_SETTINGS_ERROR", e.message, null)
        }
    }

    fun saveAlarmSettings(call: MethodCall, result: MethodChannel.Result) {
        try {
            val source = call.argument<String>("source")?.trim().orEmpty()
            if (source.isEmpty()) {
                result.error("INVALID_ARGUMENTS", "source is empty", null)
                return
            }
            val localPath = call.argument<String>("localPath")
            val remoteUrl = call.argument<String>("remoteUrl")
            val payload = AgentAlarmToolService(context).saveAlarmSettings(
                source = source,
                localPath = localPath,
                remoteUrl = remoteUrl
            )
            result.success(payload)
        } catch (e: IllegalArgumentException) {
            OmniLog.e(TAG, "saveAlarmSettings invalid: ${e.message}")
            result.error("INVALID_ARGUMENTS", e.message, null)
        } catch (e: Exception) {
            OmniLog.e(TAG, "saveAlarmSettings error: ${e.message}")
            result.error("SAVE_ALARM_SETTINGS_ERROR", e.message, null)
        }
    }

    /**
     * 显示定时任务执行前提醒（支持取消/立即执行）
     */
    fun showScheduledTaskReminder(call: MethodCall, result: MethodChannel.Result) {
        val taskId = call.argument<String>("taskId")?.trim().orEmpty()
        val taskName = call.argument<String>("taskName")?.trim().orEmpty()
        val countdownSeconds = call.argument<Int>("countdownSeconds") ?: 5

        if (taskId.isEmpty()) {
            result.error("INVALID_ARGUMENTS", "taskId is empty", null)
            return
        }
        if (taskName.isEmpty()) {
            result.error("INVALID_ARGUMENTS", "taskName is empty", null)
            return
        }

        mainJob.launch(Dispatchers.Main) {
            try {
                val success = ScheduledTaskReminderLoader.show(
                    taskId = taskId,
                    taskName = taskName,
                    countdownSeconds = countdownSeconds,
                    onCancel = { id ->
                        notifyScheduledTaskEvent("onScheduledTaskCancelled", id)
                    },
                    onExecuteNow = { id ->
                        notifyScheduledTaskEvent("onScheduledTaskExecuteNow", id)
                    }
                )
                if (success) {
                    result.success("SUCCESS")
                } else {
                    result.error("SERVICE_NOT_READY", "Accessibility service not ready", null)
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "showScheduledTaskReminder failed: ${e.message}")
                result.error("SHOW_SCHEDULED_TASK_REMINDER_ERROR", e.message, null)
            }
        }
    }

    /**
     * 隐藏定时任务提醒
     */
    fun hideScheduledTaskReminder(call: MethodCall, result: MethodChannel.Result) {
        mainJob.launch(Dispatchers.Main) {
            try {
                ScheduledTaskReminderLoader.hide()
                result.success("SUCCESS")
            } catch (e: Exception) {
                OmniLog.e(TAG, "hideScheduledTaskReminder failed: ${e.message}")
                result.error("HIDE_SCHEDULED_TASK_REMINDER_ERROR", e.message, null)
            }
        }
    }

    private fun notifyScheduledTaskEvent(method: String, taskId: String) {
        mainJob.launch(Dispatchers.Main) {
            val payload = mapOf("taskId" to taskId)
            try {
                channel.invokeMethod(method, payload)
            } catch (e: Exception) {
                OmniLog.e(TAG, "notifyScheduledTaskEvent via current channel failed: ${e.message}")
                try {
                    val mainChannel = mainEngineChannel
                    if (mainChannel != null && mainChannel != channel) {
                        mainChannel.invokeMethod(method, payload)
                    }
                } catch (fallbackError: Exception) {
                    OmniLog.e(TAG, "notifyScheduledTaskEvent fallback failed: ${fallbackError.message}")
                }
            }
        }
    }

    fun copyToClipboard(call: MethodCall, result: MethodChannel.Result) {
        try {
            val text = call.argument<String>("text") ?: ""
            val clipboard =
                context.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
            val clip = android.content.ClipData.newPlainText("label", text)
            clipboard.setPrimaryClip(clip)
            mainJob.launch(Dispatchers.Main) {
                result.success("SUCCESS")
            }
        } catch (e: Exception) {
            mainJob.launch(Dispatchers.Main) {
                result.error("COPY_TO_CLIPBOARD_ERROR", e.message, null)
            }
        }
    }

    fun getClipboardText(call: MethodCall, result: MethodChannel.Result) {
        try {
            val clipboard =
                context.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
            val clip = clipboard.primaryClip
            val text = if (clip != null && clip.itemCount > 0) {
                clip.getItemAt(0).coerceToText(context)?.toString() ?: ""
            } else {
                ""
            }
            mainJob.launch(Dispatchers.Main) {
                result.success(text)
            }
        } catch (e: Exception) {
            mainJob.launch(Dispatchers.Main) {
                result.error("GET_CLIPBOARD_ERROR", e.message, null)
            }
        }
    }

    fun startFirstUse(call: MethodCall, result: MethodChannel.Result) {
        val listener = this;
        val packageName = call.argument<String>("packageName")
        if (packageName.isNullOrEmpty()) {
            result.error("PARAMS_ERROR", "packageName不能为空", null)
            return
        }
        mainJob.launch {
            try {
                AssistsUtil.Core.startFirstUse(
                    context,
                    listener,
                    packageName
                )
                withContext(Dispatchers.Main) {
                    result.success("SUCCESS")
                }
            } catch (e: PermissionException) {
                withContext(Dispatchers.Main) {
                    result.error("PERMISSION_ERROR", e.message, null);
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("DO_TASK_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * 调用LLM chat接口（非流式）
     * 用于修复JSON格式等场景
     */
    fun postLLMChat(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text") ?: ""
        val model = call.argument<String>("model") ?: "scene.dispatch.model"

        workJob.launch {
            try {
                val response = HttpController.postLLMRequest(model, text)

                withContext(Dispatchers.Main) {
                    result.success(response.message)
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "postLLMChat error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("POST_LLM_CHAT_ERROR", e.message, null)
                }
            }
        }
    }

    fun getModelProviderConfig(call: MethodCall, result: MethodChannel.Result) {
        workJob.launch {
            try {
                val config = ModelProviderConfigStore.getConfig()
                withContext(Dispatchers.Main) {
                    result.success(config.toMap())
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "getModelProviderConfig error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("GET_MODEL_PROVIDER_CONFIG_ERROR", e.message, null)
                }
            }
        }
    }

    fun listModelProviderProfiles(call: MethodCall, result: MethodChannel.Result) {
        workJob.launch {
            try {
                val profiles = ModelProviderConfigStore.listProfiles()
                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "profiles" to profiles.map { it.toMap() },
                            "editingProfileId" to ModelProviderConfigStore.getEditingProfileId()
                        )
                    )
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "listModelProviderProfiles error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("LIST_MODEL_PROVIDER_PROFILES_ERROR", e.message, null)
                }
            }
        }
    }

    fun saveModelProviderProfile(call: MethodCall, result: MethodChannel.Result) {
        val profileId = call.argument<String>("id")?.trim()
        val name = call.argument<String>("name")?.trim().orEmpty()
        val baseUrl = call.argument<String>("baseUrl")?.trim().orEmpty()
        val apiKey = call.argument<String>("apiKey")?.trim().orEmpty()

        workJob.launch {
            try {
                val saved = ModelProviderConfigStore.saveProfile(
                    id = profileId,
                    name = name,
                    baseUrl = baseUrl,
                    apiKey = apiKey
                )
                withContext(Dispatchers.Main) {
                    result.success(saved.toMap())
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "saveModelProviderProfile error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("SAVE_MODEL_PROVIDER_PROFILE_ERROR", e.message, null)
                }
            }
        }
    }

    fun deleteModelProviderProfile(call: MethodCall, result: MethodChannel.Result) {
        val profileId = call.argument<String>("profileId")?.trim().orEmpty()

        workJob.launch {
            try {
                val profiles = ModelProviderConfigStore.deleteProfile(profileId)
                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "profiles" to profiles.map { it.toMap() },
                            "editingProfileId" to ModelProviderConfigStore.getEditingProfileId()
                        )
                    )
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "deleteModelProviderProfile error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("DELETE_MODEL_PROVIDER_PROFILE_ERROR", e.message, null)
                }
            }
        }
    }

    fun setEditingModelProviderProfile(call: MethodCall, result: MethodChannel.Result) {
        val profileId = call.argument<String>("profileId")?.trim().orEmpty()

        workJob.launch {
            try {
                val selected = ModelProviderConfigStore.setEditingProfile(profileId)
                withContext(Dispatchers.Main) {
                    result.success(selected.toMap())
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "setEditingModelProviderProfile error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("SET_EDITING_MODEL_PROVIDER_PROFILE_ERROR", e.message, null)
                }
            }
        }
    }

    fun saveModelProviderConfig(call: MethodCall, result: MethodChannel.Result) {
        val baseUrl = call.argument<String>("baseUrl")?.trim() ?: ""
        val apiKey = call.argument<String>("apiKey")?.trim() ?: ""

        workJob.launch {
            try {
                ModelProviderConfigStore.saveConfig(baseUrl, apiKey)
                val saved = ModelProviderConfigStore.getConfig()
                withContext(Dispatchers.Main) {
                    result.success(saved.toMap())
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "saveModelProviderConfig error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("SAVE_MODEL_PROVIDER_CONFIG_ERROR", e.message, null)
                }
            }
        }
    }

    fun clearModelProviderConfig(call: MethodCall, result: MethodChannel.Result) {
        workJob.launch {
            try {
                ModelProviderConfigStore.clearConfig()
                withContext(Dispatchers.Main) {
                    result.success(ModelProviderConfigStore.getConfig().toMap())
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "clearModelProviderConfig error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("CLEAR_MODEL_PROVIDER_CONFIG_ERROR", e.message, null)
                }
            }
        }
    }

    fun fetchProviderModels(call: MethodCall, result: MethodChannel.Result) {
        val baseUrlArg = call.argument<String>("apiBase")?.trim().orEmpty()
        val apiKeyArg = call.argument<String>("apiKey")?.trim().orEmpty()

        workJob.launch {
            try {
                val currentConfig = ModelProviderConfigStore.getConfig()
                val apiBase = if (baseUrlArg.isNotEmpty()) baseUrlArg else currentConfig.baseUrl
                val apiKey = if (baseUrlArg.isNotEmpty()) apiKeyArg else currentConfig.apiKey
                val models = HttpController.fetchProviderModels(apiBase, apiKey)
                withContext(Dispatchers.Main) {
                    result.success(models.map { it.toMap() })
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "fetchProviderModels error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("FETCH_PROVIDER_MODELS_ERROR", e.message, null)
                }
            }
        }
    }

    fun checkProviderModelAvailability(call: MethodCall, result: MethodChannel.Result) {
        val model = call.argument<String>("model")?.trim() ?: ""
        val baseUrlArg = call.argument<String>("apiBase")?.trim().orEmpty()
        val apiKeyArg = call.argument<String>("apiKey")?.trim().orEmpty()

        workJob.launch {
            try {
                val currentConfig = ModelProviderConfigStore.getConfig()
                val apiBase = if (baseUrlArg.isNotEmpty()) baseUrlArg else currentConfig.baseUrl
                val apiKey = if (baseUrlArg.isNotEmpty()) apiKeyArg else currentConfig.apiKey
                val checkResult = HttpController.checkProviderModelAvailability(
                    model = model,
                    apiBase = apiBase,
                    apiKey = apiKey
                )

                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "available" to checkResult.available,
                            "code" to checkResult.code,
                            "message" to checkResult.message
                        )
                    )
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "checkProviderModelAvailability error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "available" to false,
                            "code" to null,
                            "message" to (e.message ?: "检测失败")
                        )
                    )
                }
            }
        }
    }

    fun getSceneModelCatalog(call: MethodCall, result: MethodChannel.Result) {
        workJob.launch {
            try {
                val profilesById = ModelProviderConfigStore.listProfiles().associateBy { it.id }
                val bindings = SceneModelBindingStore.getBindingMap()
                val catalog = ModelSceneRegistry.listRuntimeProfiles()
                    .map { profile ->
                        val binding = bindings[profile.sceneId]
                        val boundProfile = binding?.providerProfileId?.let(profilesById::get)
                        val bindingApplied = binding != null && boundProfile?.isConfigured() == true
                        val bindingProfileMissing = binding != null && boundProfile == null
                        SceneCatalogItem(
                            sceneId = profile.sceneId,
                            description = profile.description,
                            defaultModel = profile.model,
                            effectiveModel = if (bindingApplied) binding.modelId else profile.model,
                            effectiveProviderProfileId = if (bindingApplied) boundProfile?.id else null,
                            effectiveProviderProfileName = if (bindingApplied) boundProfile?.name else null,
                            boundProviderProfileId = binding?.providerProfileId,
                            boundProviderProfileName = boundProfile?.name,
                            transport = if (bindingApplied) {
                                ModelSceneRegistry.SceneTransport.OPENAI_COMPATIBLE.wireValue
                            } else {
                                profile.transport.wireValue
                            },
                            configSource = profile.configSource.wireValue,
                            overrideApplied = bindingApplied,
                            overrideModel = binding?.modelId,
                            providerConfigured = boundProfile?.isConfigured() == true,
                            bindingExists = binding != null,
                            bindingProfileMissing = bindingProfileMissing
                        )
                    }
                withContext(Dispatchers.Main) {
                    result.success(catalog.map { it.toMap() })
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "getSceneModelCatalog error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("GET_SCENE_MODEL_CATALOG_ERROR", e.message, null)
                }
            }
        }
    }

    fun getSceneModelBindings(call: MethodCall, result: MethodChannel.Result) {
        workJob.launch {
            try {
                withContext(Dispatchers.Main) {
                    result.success(SceneModelBindingStore.getBindingEntries().map { it.toMap() })
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "getSceneModelBindings error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("GET_SCENE_MODEL_BINDINGS_ERROR", e.message, null)
                }
            }
        }
    }

    fun saveSceneModelBinding(call: MethodCall, result: MethodChannel.Result) {
        val sceneId = call.argument<String>("sceneId")?.trim().orEmpty()
        val providerProfileId = call.argument<String>("providerProfileId")?.trim().orEmpty()
        val modelId = call.argument<String>("modelId")?.trim().orEmpty()

        workJob.launch {
            try {
                SceneModelBindingStore.saveBinding(sceneId, providerProfileId, modelId)
                withContext(Dispatchers.Main) {
                    result.success(SceneModelBindingStore.getBindingEntries().map { it.toMap() })
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "saveSceneModelBinding error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("SAVE_SCENE_MODEL_BINDING_ERROR", e.message, null)
                }
            }
        }
    }

    fun clearSceneModelBinding(call: MethodCall, result: MethodChannel.Result) {
        val sceneId = call.argument<String>("sceneId")?.trim().orEmpty()

        workJob.launch {
            try {
                SceneModelBindingStore.clearBinding(sceneId)
                withContext(Dispatchers.Main) {
                    result.success(SceneModelBindingStore.getBindingEntries().map { it.toMap() })
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "clearSceneModelBinding error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("CLEAR_SCENE_MODEL_BINDING_ERROR", e.message, null)
                }
            }
        }
    }

    fun getSceneModelOverrides(call: MethodCall, result: MethodChannel.Result) {
        workJob.launch {
            try {
                withContext(Dispatchers.Main) {
                    result.success(SceneModelOverrideStore.getOverrideEntries().map { it.toMap() })
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "getSceneModelOverrides error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("GET_SCENE_MODEL_OVERRIDES_ERROR", e.message, null)
                }
            }
        }
    }

    fun saveSceneModelOverride(call: MethodCall, result: MethodChannel.Result) {
        val sceneId = call.argument<String>("sceneId")?.trim() ?: ""
        val model = call.argument<String>("model")?.trim() ?: ""

        workJob.launch {
            try {
                SceneModelOverrideStore.saveOverride(sceneId, model)
                withContext(Dispatchers.Main) {
                    result.success(SceneModelOverrideStore.getOverrideEntries().map { it.toMap() })
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "saveSceneModelOverride error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("SAVE_SCENE_MODEL_OVERRIDE_ERROR", e.message, null)
                }
            }
        }
    }

    fun clearSceneModelOverride(call: MethodCall, result: MethodChannel.Result) {
        val sceneId = call.argument<String>("sceneId")?.trim() ?: ""

        workJob.launch {
            try {
                SceneModelOverrideStore.clearOverride(sceneId)
                withContext(Dispatchers.Main) {
                    result.success(SceneModelOverrideStore.getOverrideEntries().map { it.toMap() })
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "clearSceneModelOverride error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("CLEAR_SCENE_MODEL_OVERRIDE_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * 检测自定义 VLM 模型可用性（OpenAI-compatible）
     */
    fun checkVlmModelAvailability(call: MethodCall, result: MethodChannel.Result) {
        checkProviderModelAvailability(call, result)
    }

    /**
     * 打开APP市场
     */
    fun openAPPMarket(call: MethodCall, result: MethodChannel.Result) {
        val packageName = call.argument<String>("packageName") ?: ""
        try {
            if (packageName.isNotEmpty()) {
                SchemeUtil.jumpToMarket(context, packageName)
                result.success("SUCCESS")
            } else {
                result.error("OPEN_APP_MARKET_ERROR", "packageName is empty", null)
            }

        } catch (e: Exception) {
            result.error("OPEN_APP_MARKET_ERROR", e.message, null)
        }
    }

    /**
     * 是否在桌面
     */
    fun isDesktop(call: MethodCall, result: MethodChannel.Result) {
        try {
            result.success(AssistsCore.isInDesktop())
        } catch (e: Exception) {
            result.error("IS_DESKTOP_ERROR", e.message, null)
        }
    }

    /**
     * 获取桌面包名
     */
    fun getDeskTopPackageName(call: MethodCall, result: MethodChannel.Result){
        try {
            result.success(Constant.LAUNCHER_PACKAGES.toList())
        } catch (e: Exception) {
            result.error("GET_DESK_TOP_PACKAGE_NAME_ERROR", e.message, null)
        }
    }

    /**
     * 获取当前应用包名
     * 用于从当前页面开始执行任务
     */
    fun getCurrentPackageName(call: MethodCall, result: MethodChannel.Result) {
        try {
            val packageName = AssistsCore.getCurrentPackageName()
            result.success(packageName)
        } catch (e: Exception) {
            result.error("GET_CURRENT_PACKAGE_NAME_ERROR", e.message, null)
        }
    }

    /**
     * 跳转到主引擎路由
     */
    fun navigateToMainEngineRoute(call: MethodCall, result: MethodChannel.Result) {
        val route = call.argument<String>("route") ?: ""
        if (route.isNotEmpty()) {
            try {
                TaskCompletionNavigator.navigateToMainRoute(context, route, needClear = false)
                mainJob.launch(Dispatchers.Main) {
                    result.success("SUCCESS")
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "navigateToMainEngineRoute failed: ${e.message}")
                mainJob.launch(Dispatchers.Main) {
                    result.error("NAVIGATE_ERROR", e.message, null)
                }
            }
        } else {
            result.error("NAVIGATE_ERROR", "Route is empty", null)
        }
    }

    /**
     * 创建 Agent 任务
     */
    fun createAgentTask(call: MethodCall, result: MethodChannel.Result) {
        val taskId = (call.argument<String>("taskId") ?: "").trim()
        val userMessage = (call.argument<String>("userMessage") ?: "").toString()
        val conversationHistory =
            call.argument<List<Map<String, Any?>>>("conversationHistory") ?: emptyList()
        val attachments = call.argument<List<Map<String, Any?>>>("attachments") ?: emptyList()
        val conversationId = call.argument<Number>("conversationId")?.toLong()
        val modelOverrideMap = call.argument<Map<String, Any?>>("modelOverride")
        val modelOverride = modelOverrideMap?.let { raw ->
            val providerProfileId = raw["providerProfileId"]?.toString()?.trim().orEmpty()
            val modelId = raw["modelId"]?.toString()?.trim().orEmpty()
            val providerProfile = ModelProviderConfigStore.getProfile(providerProfileId)
            if (
                providerProfileId.isEmpty() ||
                modelId.isEmpty() ||
                providerProfile == null ||
                !providerProfile.isConfigured()
            ) {
                null
            } else {
                AgentModelOverride(
                    providerProfileId = providerProfile.id,
                    providerProfileName = providerProfile.name,
                    modelId = modelId,
                    apiBase = providerProfile.baseUrl,
                    apiKey = providerProfile.apiKey
                )
            }
        }
        if (taskId.isBlank()) {
            result.error("INVALID_ARGUMENTS", "taskId is empty", null)
            return
        }
        val agentRunJob = SupervisorJob()
        val agentRunScope = CoroutineScope(agentRunJob + Dispatchers.Default)
        registerActiveAgentJob(agentRunJob)

        agentRunScope.launch {
            try {
                // 1. 获取当前包名
                val currentPackageName = AssistsCore.getCurrentPackageName()
                val runtimeContextRepository = AgentRuntimeContextRepository(context)

                val scheduleBridge = object : AgentScheduleToolBridge {
                    override suspend fun createTask(arguments: Map<String, Any?>): Map<String, Any?> {
                        return toStringAnyMap(
                            invokeFlutterMethodForAgent("agentScheduleCreate", arguments)
                        )
                    }

                    override suspend fun listTasks(): List<Map<String, Any?>> {
                        return toListOfStringAnyMap(
                            invokeFlutterMethodForAgent("agentScheduleList", emptyMap())
                        )
                    }

                    override suspend fun updateTask(arguments: Map<String, Any?>): Map<String, Any?> {
                        return toStringAnyMap(
                            invokeFlutterMethodForAgent("agentScheduleUpdate", arguments)
                        )
                    }

                    override suspend fun deleteTask(arguments: Map<String, Any?>): Map<String, Any?> {
                        return toStringAnyMap(
                            invokeFlutterMethodForAgent("agentScheduleDelete", arguments)
                        )
                    }
                }

                // 2. 初始化 Executor
                val executor = OmniAgentExecutor(context, agentRunScope, scheduleBridge)
                val activeToolArgs = mutableMapOf<String, String>()

                // 3. 创建回调
                val callback = object : AgentCallback {
                    override suspend fun onThinkingStart() {
                        sendEvent("onAgentThinkingStart", emptyMap())
                    }

                    override suspend fun onThinkingUpdate(thinking: String) {
                        sendEvent("onAgentThinkingUpdate", mapOf("thinking" to thinking))
                    }

                    override suspend fun onToolCallStart(
                        toolName: String,
                        arguments: JsonObject
                    ) {
                        val argsJson = arguments.toString()
                        activeToolArgs[toolName] = argsJson
                        sendEvent(
                            "onAgentToolCallStart",
                            buildToolStartPayload(toolName, argsJson)
                        )
                    }

                    override suspend fun onToolCallProgress(
                        toolName: String,
                        progress: String,
                        extras: Map<String, Any?>
                    ) {
                        sendEvent(
                            "onAgentToolCallProgress",
                            buildToolProgressPayload(
                                toolName,
                                progress,
                                activeToolArgs[toolName].orEmpty(),
                                extras
                            )
                        )
                    }

                    override suspend fun onToolCallComplete(
                        toolName: String,
                        result: ToolExecutionResult
                    ) {
                        val argsJson = activeToolArgs.remove(toolName).orEmpty()
                        sendEvent(
                            "onAgentToolCallComplete",
                            buildToolCompletePayload(toolName, result, argsJson)
                        )
                    }

                    override suspend fun onChatMessage(message: String) {
                        dispatchAgentChatMessage(message, isFinal = true)
                    }

                    override suspend fun onChatMessage(message: String, isFinal: Boolean) {
                        dispatchAgentChatMessage(message, isFinal)
                    }

                    override suspend fun onClarifyRequired(
                        question: String,
                        missingFields: List<String>?
                    ) {
                        sendEvent(
                            "onAgentClarifyRequired",
                            mapOf("question" to question, "missingFields" to missingFields)
                        )
                    }

                    override suspend fun onComplete(result: AgentResult) {
                        val isSuccess = result is AgentResult.Success
                        val outputKind = (result as? AgentResult.Success)?.outputKind ?: "none"
                        val hasUserVisibleOutput =
                            (result as? AgentResult.Success)?.hasUserVisibleOutput == true
                        sendEvent(
                            "onAgentComplete",
                            mapOf(
                                "success" to isSuccess,
                                "outputKind" to outputKind,
                                "hasUserVisibleOutput" to hasUserVisibleOutput
                            )
                        )
                    }

                    override suspend fun onError(error: String) {
                        sendEvent("onAgentError", mapOf("error" to error))
                    }

                    override suspend fun onPermissionRequired(missing: List<String>) {
                        sendEvent("onAgentPermissionRequired", mapOf("missing" to missing))
                    }

                    override suspend fun onVlmTaskFinished() {
                        handleVlmTaskFinished("unified_agent_listener", taskId = taskId)
                    }

                    private suspend fun dispatchAgentChatMessage(
                        message: String,
                        isFinal: Boolean
                    ) {
                        sendEvent(
                            "onAgentChatMessage",
                            mapOf(
                                "message" to message,
                                "isFinal" to isFinal
                            )
                        )
                    }

                    private suspend fun sendEvent(method: String, args: Map<String, Any?>) {
                        withContext(Dispatchers.Main) {
                            try {
                                channel.invokeMethod(method, mapOf("taskId" to taskId) + args)
                            } catch (e: Exception) {
                                OmniLog.e(TAG, "Failed to send agent event: $method, ${e.message}")
                            }
                        }
                    }
                }

                // 4. 执行任务
                executor.processUserMessage(
                    userMessage,
                    conversationHistory,
                    runtimeContextRepository,
                    currentPackageName,
                    attachments,
                    conversationId,
                    modelOverride,
                    callback
                )

                withContext(Dispatchers.Main) {
                    result.success("SUCCESS")
                }
            } catch (e: CancellationException) {
                OmniLog.i(TAG, "createAgentTask cancelled: ${e.message}")
                withContext(NonCancellable + Dispatchers.Main) {
                    result.success("SUCCESS")
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "createAgentTask error: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("CREATE_AGENT_TASK_ERROR", e.message, null)
                }
            } finally {
                clearActiveAgentJob(agentRunJob)
            }
        }
    }

    fun agentSkillList(call: MethodCall, result: MethodChannel.Result) {
        mainJob.launch {
            try {
                if (!WorkspaceStorageAccess.isGranted(context)) {
                    withContext(Dispatchers.Main) {
                        result.error(
                            "WORKSPACE_STORAGE_PERMISSION_REQUIRED",
                            WorkspaceStorageAccess.REQUIRED_PERMISSION_NAME,
                            null
                        )
                    }
                    return@launch
                }
                val workspaceManager = AgentWorkspaceManager(context)
                val skillIndexService = SkillIndexService(context, workspaceManager)
                val payload = skillIndexService.listInstalledSkills().map { entry ->
                    mapOf(
                        "id" to entry.id,
                        "name" to entry.name,
                        "description" to entry.description,
                        "compatibility" to entry.compatibility,
                        "metadata" to entry.metadata,
                        "rootPath" to entry.rootPath,
                        "hasScripts" to entry.hasScripts,
                        "hasReferences" to entry.hasReferences,
                        "hasAssets" to entry.hasAssets,
                        "hasEvals" to entry.hasEvals
                    )
                }
                withContext(Dispatchers.Main) {
                    result.success(payload)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    val isWorkspacePermissionError =
                        WorkspaceStorageAccess.looksLikePermissionError(e)
                    result.error(
                        if (isWorkspacePermissionError) {
                            "WORKSPACE_STORAGE_PERMISSION_REQUIRED"
                        } else {
                            "AGENT_SKILL_LIST_ERROR"
                        },
                        if (isWorkspacePermissionError) {
                            WorkspaceStorageAccess.REQUIRED_PERMISSION_NAME
                        } else {
                            e.message
                        },
                        null
                    )
                }
            }
        }
    }

    fun agentSkillInstall(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")?.trim().orEmpty()
        if (sourcePath.isBlank()) {
            result.error("INVALID_ARGS", "sourcePath is required", null)
            return
        }
        mainJob.launch {
            try {
                if (!WorkspaceStorageAccess.isGranted(context)) {
                    withContext(Dispatchers.Main) {
                        result.error(
                            "WORKSPACE_STORAGE_PERMISSION_REQUIRED",
                            WorkspaceStorageAccess.REQUIRED_PERMISSION_NAME,
                            null
                        )
                    }
                    return@launch
                }
                val workspaceManager = AgentWorkspaceManager(context)
                val skillIndexService = SkillIndexService(context, workspaceManager)
                val entry = skillIndexService.installSkillFromDirectory(sourcePath)
                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "id" to entry.id,
                            "name" to entry.name,
                            "description" to entry.description,
                            "compatibility" to entry.compatibility,
                            "metadata" to entry.metadata,
                            "rootPath" to entry.rootPath,
                            "hasScripts" to entry.hasScripts,
                            "hasReferences" to entry.hasReferences,
                            "hasAssets" to entry.hasAssets,
                            "hasEvals" to entry.hasEvals
                        )
                    )
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    val isWorkspacePermissionError =
                        WorkspaceStorageAccess.looksLikePermissionError(e)
                    result.error(
                        if (isWorkspacePermissionError) {
                            "WORKSPACE_STORAGE_PERMISSION_REQUIRED"
                        } else {
                            "AGENT_SKILL_INSTALL_ERROR"
                        },
                        if (isWorkspacePermissionError) {
                            WorkspaceStorageAccess.REQUIRED_PERMISSION_NAME
                        } else {
                            e.message
                        },
                        null
                    )
                }
            }
        }
    }

    /**
     * 获取所有对话列表
     */
    fun getConversations(call: MethodCall, result: MethodChannel.Result) {
        OmniLog.d(TAG, "[getConversations] 开始获取对话列表...")
        workJob.launch {
            try {
                val conversations = DatabaseHelper.getAllConversations()
                OmniLog.d(TAG, "[getConversations] 从数据库获取到 ${conversations.size} 条对话记录")
                val jsonList = conversations.map { conv ->
                    mapOf(
                        "id" to conv.id,
                        "title" to conv.title,
                        "summary" to conv.summary,
                        "status" to conv.status,
                        "lastMessage" to conv.lastMessage,
                        "messageCount" to conv.messageCount,
                        "createdAt" to conv.createdAt,
                        "updatedAt" to conv.updatedAt
                    )
                }
                withContext(Dispatchers.Main) {
                    OmniLog.d(TAG, "[getConversations] 返回 Flutter: $jsonList")
                    result.success(jsonList)
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "[getConversations] 获取对话列表失败: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("GET_CONVERSATIONS_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * 分页获取对话列表
     */
    fun getConversationsByPage(call: MethodCall, result: MethodChannel.Result) {
        val offset = call.argument<Int>("offset") ?: 0
        val limit = call.argument<Int>("limit") ?: 20

        workJob.launch {
            try {
                val conversations = DatabaseHelper.getConversationsByPage(offset, limit)
                val jsonList = conversations.map { conv ->
                    mapOf(
                        "id" to conv.id,
                        "title" to conv.title,
                        "summary" to conv.summary,
                        "status" to conv.status,
                        "lastMessage" to conv.lastMessage,
                        "messageCount" to conv.messageCount,
                        "createdAt" to conv.createdAt,
                        "updatedAt" to conv.updatedAt
                    )
                }
                withContext(Dispatchers.Main) {
                    result.success(jsonList)
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "分页获取对话列表失败: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("GET_CONVERSATIONS_BY_PAGE_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * 创建新对话
     */
    fun createConversation(call: MethodCall, result: MethodChannel.Result) {
        val title = call.argument<String>("title") ?: "新对话"
        val summary = call.argument<String>("summary")

        workJob.launch {
            try {
                val conversation = Conversation(
                    id = 0,
                    title = title,
                    summary = summary,
                    status = 0, // 进行中
                    lastMessage = null,
                    messageCount = 0,
                    createdAt = System.currentTimeMillis(),
                    updatedAt = System.currentTimeMillis()
                )
                val conversationId = DatabaseHelper.insertConversation(conversation)
                withContext(Dispatchers.Main) {
                    result.success(conversationId)
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "创建对话失败: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("CREATE_CONVERSATION_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * 更新对话
     */
    fun updateConversation(call: MethodCall, result: MethodChannel.Result) {
        val conversationMap = call.argument<Map<String, Any>>("conversation")

        workJob.launch {
            try {
                if (conversationMap != null) {
                    val conversation = Conversation(
                        id = (conversationMap["id"] as Number).toLong(),
                        title = conversationMap["title"] as String,
                        summary = conversationMap["summary"] as String?,
                        status = (conversationMap["status"] as Number).toInt(),
                        lastMessage = conversationMap["lastMessage"] as String?,
                        messageCount = (conversationMap["messageCount"] as Number).toInt(),
                        createdAt = (conversationMap["createdAt"] as Number).toLong(),
                        updatedAt = (conversationMap["updatedAt"] as Number).toLong()
                    )
                    DatabaseHelper.updateConversation(conversation)
                    withContext(Dispatchers.Main) {
                        result.success("SUCCESS")
                    }
                } else {
                    withContext(Dispatchers.Main) {
                        result.error("INVALID_ARGUMENTS", "conversation is null", null)
                    }
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "更新对话失败: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("UPDATE_CONVERSATION_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * 删除对话
     */
    fun deleteConversation(call: MethodCall, result: MethodChannel.Result) {
        val conversationId = (call.argument<Int>("conversationId") ?: 0).toLong()

        workJob.launch {
            try {
                DatabaseHelper.deleteConversationById(conversationId)
                withContext(Dispatchers.Main) {
                    result.success("SUCCESS")
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "删除对话失败: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("DELETE_CONVERSATION_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * 更新对话标题
     */
    fun updateConversationTitle(call: MethodCall, result: MethodChannel.Result) {
        val conversationId = (call.argument<Int>("conversationId") ?: 0).toLong()
        val newTitle = call.argument<String>("newTitle") ?: ""

        workJob.launch {
            try {
                val conversation = DatabaseHelper.getConversationById(conversationId)
                if (conversation != null) {
                    val updatedConversation = conversation.copy(
                        title = newTitle,
                        updatedAt = System.currentTimeMillis()
                    )
                    DatabaseHelper.updateConversation(updatedConversation)
                    withContext(Dispatchers.Main) {
                        result.success("SUCCESS")
                    }
                } else {
                    withContext(Dispatchers.Main) {
                        result.error("CONVERSATION_NOT_FOUND", "Conversation not found", null)
                    }
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "更新对话标题失败: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("UPDATE_CONVERSATION_TITLE_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * 生成对话摘要
     * 使用云端 qwen-flash 模型生成 10 字左右的摘要
     */
    fun generateConversationSummary(call: MethodCall, result: MethodChannel.Result) {
        val conversationHistory = call.argument<String>("conversationHistory") ?: ""

        workJob.launch {
            try {
                // 构建提示词，要求生成10字左右的摘要
                val prompt = """
                    你是一个聊天总结助手，请根据以下用户发送的对话内容，生成一个简洁的摘要标题，要求：
                    1. 摘要标题长度控制在10个字左右
                    2. 摘要标题应该体现对话的主要内容
                    3. 不要包含特殊字符和表情符号
                    4. 不要包含任何的人称用词

                    对话内容：
                    $conversationHistory

                    请直接返回摘要标题，不要包含其他内容。
                """.trimIndent()

                // 调用 LLM 生成摘要
                val llmResult = HttpController.postLLMRequest("scene.compactor.context", prompt)
                val summary = llmResult.message
                    .trim()
                    .take(10)
                    .takeIf { it.isNotBlank() }
                    ?: throw IllegalStateException("Conversation summary is empty")

                withContext(Dispatchers.Main) {
                    result.success(summary)
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "生成对话摘要失败: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("GENERATE_SUMMARY_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * 跳转回聊天页面
     */
    private fun navigateBackToChatIfNeeded() {
        if (TaskCompletionNavigator.isAutoBackToChatAfterTaskEnabled(context)) {
            TaskCompletionNavigator.navigateBackToChat(context, currentConversationId)
        } else {
            OmniLog.d(TAG, "任务完成后停留当前页面（已关闭自动返回聊天）")
        }
    }

    fun setAutoBackToChatAfterTaskEnabled(
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        val enabled = call.argument<Boolean>("enabled") ?: true
        try {
            val success = TaskCompletionNavigator.setAutoBackToChatAfterTaskEnabled(
                context,
                enabled
            )

            if (success) {
                OmniLog.d(TAG, "自动返回聊天设置已同步到原生: $enabled")
                result.success("SUCCESS")
            } else {
                result.error("SAVE_AUTO_BACK_SETTING_FAILED", "保存自动返回聊天设置失败", null)
            }
        } catch (e: Exception) {
            OmniLog.e(TAG, "保存自动返回聊天设置失败: ${e.message}")
            result.error("SAVE_AUTO_BACK_SETTING_FAILED", e.message, null)
        }
    }

    /**
     * 完成对话
     */
    fun completeConversation(call: MethodCall, result: MethodChannel.Result) {
        val conversationId = (call.argument<Int>("conversationId") ?: 0).toLong()

        workJob.launch {
            try {
                val conversation = DatabaseHelper.getConversationById(conversationId)
                if (conversation != null) {
                    val updatedConversation = conversation.copy(
                        status = 1, // 已完成
                        updatedAt = System.currentTimeMillis()
                    )
                    DatabaseHelper.updateConversation(updatedConversation)
                    withContext(Dispatchers.Main) {
                        result.success("SUCCESS")
                    }
                } else {
                    withContext(Dispatchers.Main) {
                        result.error("CONVERSATION_NOT_FOUND", "Conversation not found", null)
                    }
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "完成对话失败: ${e.message}")
                withContext(Dispatchers.Main) {
                    result.error("COMPLETE_CONVERSATION_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * 设置当前活跃的对话ID
     */
    fun setCurrentConversationId(call: MethodCall, result: MethodChannel.Result) {
        val conversationId = (call.argument<Int>("conversationId") ?: 0).toLong()
        currentConversationId = if (conversationId > 0) conversationId else null
        mainJob.launch(Dispatchers.Main) {
            result.success("SUCCESS")
        }
    }

    /**
     * 授权完成后重新打开ChatBot半屏
     */
    fun reopenChatBotAfterAuth(result: MethodChannel.Result) {
        mainJob.launch(Dispatchers.Main) {
            try {
                withContext(Dispatchers.Main) {
                    ScreenMaskLoader.loadLockScreenMask()
                }
                // delay(500)
                UIKit.uiChatEvent?.showChatBotHalfScreen("resume_after_auth")
                result.success("SUCCESS")
            } catch (e: Exception) {
                OmniLog.e(TAG, "reopenChatBotAfterAuth failed: ${e.message}")
                result.error("REOPEN_ERROR", e.message, null)
            }
        }
    }
}
