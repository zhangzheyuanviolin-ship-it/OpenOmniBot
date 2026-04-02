package cn.com.omnimind.bot.mcp

import android.content.Context
import android.os.Handler
import android.os.Looper
import cn.com.omnimind.accessibility.util.ScreenStateUtil
import cn.com.omnimind.assists.api.interfaces.OnMessagePushListener
import cn.com.omnimind.baselib.util.OmniLog
import cn.com.omnimind.bot.utg.UtgBridge
import cn.com.omnimind.bot.util.AssistsUtil
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.util.UUID

/**
 * MCP 工具执行器
 */
object McpToolExecutors {
    private const val TAG = "[McpToolExecutors]"
    private const val SUMMARY_WAIT_GRACE_MS = 20_000L
    
    private val mainHandler = Handler(Looper.getMainLooper())
    
    /**
     * 执行 VLM 任务（阻塞等待完成）
     */
    suspend fun executeVlmTask(
        context: Context,
        args: Map<String, Any?>?,
        scope: CoroutineScope
    ): Map<String, Any?> = withContext(Dispatchers.IO) {
        val goal = args?.get("goal") as? String
        if (goal.isNullOrBlank()) {
            return@withContext McpResponseBuilder.buildErrorText("Missing goal")
        }

        val needSummaryArg = args?.get("needSummary") as? Boolean
        val shouldSummary = shouldEnableSummary(goal, needSummaryArg)

        // 检查屏幕状态，如果屏幕锁定则创建任务并返回提示
        if (!ScreenStateUtil.isOperable()) {
            val taskId = UUID.randomUUID().toString()
            val taskState = McpTaskManager.createTask(
                taskId = taskId,
                goal = goal,
                status = TaskStatus.SCREEN_LOCKED,
                needSummary = shouldSummary
            )
            taskState.message = "屏幕锁定，等待解锁"
            OmniLog.d(TAG, "Screen locked, created pending task: $taskId")
            // 返回提示，让 LLM 告知用户解锁并调用 task_wait_unlock
            return@withContext McpResponseBuilder.buildScreenLockedResponse(taskState, isInitial = true)
        }

        val request = VlmTaskRequest(
            goal = goal,
            model = args["model"] as? String,
            packageName = args["packageName"] as? String,
            needSummary = shouldSummary
        )
        val taskId = UUID.randomUUID().toString()
        
        // 创建任务状态
        val taskState = McpTaskManager.createTask(
            taskId = taskId,
            goal = request.goal,
            status = TaskStatus.RUNNING,
            needSummary = shouldSummary
        )
        
        OmniLog.d(TAG, "Starting VLM task: $taskId, goal: ${request.goal}")
        
        try {
            // 启动 VLM 任务
            val result = startVlmTaskInternal(context, request, taskId, taskState, scope)
            if (result.isFailure) {
                val err = result.exceptionOrNull()?.message ?: "Unknown error"
                return@withContext McpResponseBuilder.buildErrorText("Error: $err")
            }

            if (shouldSummary) {
                val notified = notifySummarySheetReadyWithRetry()
                OmniLog.d(TAG, "Summary sheet ready notify (needSummary=$shouldSummary) => $notified")
            }
            
            // 阻塞等待任务完成或状态变化
            return@withContext waitForTaskStateChange(taskId, goal)
            
        } catch (e: Exception) {
            OmniLog.e(TAG, "Error executing VLM task: ${e.message}")
            McpTaskManager.markTaskError(taskId, e.message ?: "Unknown error")
            return@withContext McpResponseBuilder.buildErrorText("VLM task failed: ${e.message}")
        }
    }
    
    /**
     * 执行任务回复
     */
    suspend fun executeTaskReply(
        args: Map<String, Any?>?
    ): Map<String, Any?> = withContext(Dispatchers.IO) {
        val taskId = args?.get("taskId") as? String
        val reply = args?.get("reply") as? String
        
        if (taskId.isNullOrBlank() || reply.isNullOrBlank()) {
            return@withContext McpResponseBuilder.buildErrorText("Missing taskId or reply")
        }
        
        val taskState = McpTaskManager.getTask(taskId)
            ?: return@withContext McpResponseBuilder.buildErrorText("Task not found: $taskId")
        
        if (taskState.status != TaskStatus.WAITING_INPUT) {
            return@withContext McpResponseBuilder.buildErrorText(
                "Task is not waiting for input. Current status: ${taskState.status}"
            )
        }
        
        OmniLog.d(TAG, "Sending reply to task $taskId: $reply")
        
        val success = AssistsUtil.Core.provideUserInputToVLMTask(reply)
        if (!success) {
            return@withContext McpResponseBuilder.buildErrorText("Failed to send reply to task")
        }
        
        // 更新状态并等待下一个状态变更
        taskState.status = TaskStatus.RUNNING
        taskState.waitingQuestion = null
        taskState.addChatMessage("User replied: $reply")
        
        // 阻塞等待任务完成或再次需要输入
        return@withContext waitForTaskStateChange(taskId, taskState.goal)
    }
    
    /**
     * 执行任务状态查询
     */
    fun executeTaskStatus(args: Map<String, Any?>?): Map<String, Any?> {
        val taskId = args?.get("taskId") as? String
        
        if (taskId.isNullOrBlank()) {
            return McpResponseBuilder.buildErrorText("Missing taskId")
        }
        
        val state = McpTaskManager.getTask(taskId)
            ?: return McpResponseBuilder.buildErrorText("Task not found: $taskId")
        
        return McpResponseBuilder.buildTaskStatusResponse(state)
    }
    
    /**
     * 执行等待屏幕解锁
     */
    suspend fun executeTaskWaitUnlock(
        context: Context,
        args: Map<String, Any?>?,
        scope: CoroutineScope
    ): Map<String, Any?> = withContext(Dispatchers.IO) {
        val taskId = args?.get("taskId") as? String
        
        if (taskId.isNullOrBlank()) {
            return@withContext McpResponseBuilder.buildErrorText("Missing taskId")
        }
        
        val taskState = McpTaskManager.getTask(taskId)
            ?: return@withContext McpResponseBuilder.buildErrorText("Task not found: $taskId")
        
        if (taskState.status != TaskStatus.SCREEN_LOCKED) {
            // 如果已经不是锁屏状态，直接返回当前状态
            return@withContext when (taskState.status) {
                TaskStatus.FINISHED -> McpResponseBuilder.buildFinishedResponse(taskState)
                TaskStatus.ERROR -> McpResponseBuilder.buildErrorResponse(taskState)
                TaskStatus.WAITING_INPUT -> McpResponseBuilder.buildWaitingInputResponse(taskState)
                TaskStatus.RUNNING -> waitForTaskStateChange(taskId, taskState.goal)
                else -> McpResponseBuilder.buildTextResponse("Task status: ${taskState.status}")
            }
        }
        
        OmniLog.d(TAG, "Waiting for screen unlock for task $taskId")
        
        // 等待屏幕解锁
        val startTime = System.currentTimeMillis()
        while (System.currentTimeMillis() - startTime < McpTaskManager.MAX_WAIT_TIME_MS) {
            if (ScreenStateUtil.isOperable()) {
                // 屏幕已解锁
                taskState.addChatMessage("[SYSTEM] Screen unlocked, starting task...")

                // 启动实际的VLM任务
                val req = VlmTaskRequest(goal = taskState.goal, needSummary = taskState.needSummary)
                taskState.status = TaskStatus.RUNNING
                taskState.message = "屏幕已解锁，任务启动中"

                val result = startVlmTaskInternal(context, req, taskId, taskState, scope)
                if (result.isFailure) {
                    val err = result.exceptionOrNull()?.message ?: "Unknown error"
                    taskState.status = TaskStatus.ERROR
                    taskState.message = err
                    return@withContext McpResponseBuilder.buildErrorResponse(taskState)
                }

                if (taskState.needSummary) {
                    val notified = notifySummarySheetReadyWithRetry()
                    OmniLog.d(TAG, "Summary sheet ready notify after unlock => $notified")
                }
                
                // 等待任务完成或需要输入
                return@withContext waitForTaskStateChange(taskId, taskState.goal)
            }
            kotlinx.coroutines.delay(McpTaskManager.POLL_INTERVAL_MS)
        }
        
        // 超时仍未解锁
        return@withContext McpResponseBuilder.buildUnlockTimeoutResponse(taskId, taskState.goal)
    }

    /**
     * 执行文件传输工具
     */
    suspend fun executeFileTransfer(
        args: Map<String, Any?>?
    ): Map<String, Any?> = withContext(Dispatchers.IO) {
        val action = (args?.get("action") as? String)?.trim()?.lowercase() ?: "latest"
        val fileId = args?.get("fileId") as? String
        val afterFileId = args?.get("afterFileId") as? String
        val limit = (args?.get("limit") as? Number)?.toInt()
        val timeoutMs = (args?.get("timeoutMs") as? Number)?.toLong()
            ?.coerceIn(1_000L, McpTaskManager.MAX_WAIT_TIME_MS)
            ?: McpTaskManager.MAX_WAIT_TIME_MS

        when (action) {
            "latest" -> {
                val record = McpFileInbox.latest()
                    ?: return@withContext McpResponseBuilder.buildTextResponse(
                        "No files in inbox. Ask the user to share/open the file with 小万, then call file_transfer again."
                    )
                return@withContext buildFileTransferResponse(record)
            }
            "get" -> {
                if (fileId.isNullOrBlank()) {
                    return@withContext McpResponseBuilder.buildErrorText("Missing fileId")
                }
                val record = McpFileInbox.getFile(fileId)
                    ?: return@withContext McpResponseBuilder.buildErrorText("File not found: $fileId")
                return@withContext buildFileTransferResponse(record)
            }
            "list" -> {
                val records = McpFileInbox.list(limit)
                if (records.isEmpty()) {
                    return@withContext McpResponseBuilder.buildTextResponse(
                        "No files in inbox. Ask the user to share/open the file with 小万, then call file_transfer again."
                    )
                }
                val itemsText = records.joinToString("\n") { record ->
                    "- id=${record.id}, name=${record.fileName}, size=${record.sizeBytes}, receivedAt=${record.createdAt}"
                }
                return@withContext mapOf(
                    "content" to listOf(
                        mapOf(
                            "type" to "text",
                            "text" to "Received files:\n$itemsText"
                        )
                    ),
                    "files" to records.map { record ->
                        mapOf(
                            "id" to record.id,
                            "name" to record.fileName,
                            "mimeType" to record.mimeType,
                            "sizeBytes" to record.sizeBytes,
                            "receivedAt" to record.createdAt,
                        )
                    }
                )
            }
            "clear" -> {
                val cleared = if (!fileId.isNullOrBlank()) {
                    if (McpFileInbox.removeFile(fileId)) 1 else 0
                } else {
                    McpFileInbox.clearAll()
                }
                return@withContext McpResponseBuilder.buildTextResponse("Cleared $cleared file(s) from inbox.")
            }
            "wait" -> {
                val startTime = System.currentTimeMillis()
                while (System.currentTimeMillis() - startTime < timeoutMs) {
                    val record = McpFileInbox.latest()
                    if (record != null && (afterFileId == null || record.id != afterFileId)) {
                        return@withContext buildFileTransferResponse(record)
                    }
                    kotlinx.coroutines.delay(McpTaskManager.POLL_INTERVAL_MS)
                }
                return@withContext McpResponseBuilder.buildTextResponse(
                    "No file received within timeout. Ask the user to share/open the file with 小万, then call file_transfer again."
                )
            }
            else -> {
                return@withContext McpResponseBuilder.buildErrorText("Unknown action: $action")
            }
        }
    }
    
    /**
     * 阻塞等待任务状态变更（完成/需要输入/超时）
     * 在息屏时会等待解锁后继续轮询
     */
    private suspend fun waitForTaskStateChange(taskId: String, goal: String): Map<String, Any?> {
        val startWaitTime = System.currentTimeMillis()
        var lastScreenState = ScreenStateUtil.isOperable()
        var summaryWaitStart: Long? = null
        
        while (System.currentTimeMillis() - startWaitTime < McpTaskManager.MAX_WAIT_TIME_MS) {
            val state = McpTaskManager.getTask(taskId)
            if (state == null) {
                return McpResponseBuilder.buildErrorText("Task not found: $taskId")
            }
            
            // 检测屏幕状态变化
            val currentScreenState = ScreenStateUtil.isOperable()
            if (!currentScreenState && lastScreenState) {
                // 屏幕刚刚锁定
                state.status = TaskStatus.SCREEN_LOCKED
                state.message = "屏幕锁定，等待解锁"
                state.addChatMessage("[SYSTEM] Screen locked, waiting for unlock...")
                OmniLog.d(TAG, "Screen locked during task, waiting for unlock...")
            } else if (currentScreenState && !lastScreenState && state.status == TaskStatus.SCREEN_LOCKED) {
                // 屏幕刚刚解锁，恢复运行状态
                state.status = TaskStatus.RUNNING
                state.message = "屏幕解锁，任务继续"
                state.addChatMessage("[SYSTEM] Screen unlocked, task resuming")
                OmniLog.d(TAG, "Screen unlocked, task resuming")
            }
            lastScreenState = currentScreenState
            
            when (state.status) {
                TaskStatus.FINISHED -> {
                    if (state.needSummary && state.summaryText.isNullOrBlank()) {
                        if (summaryWaitStart == null) {
                            summaryWaitStart = System.currentTimeMillis()
                            OmniLog.d(TAG, "Summary pending for task $taskId, waiting briefly...")
                        }
                        if (System.currentTimeMillis() - summaryWaitStart < SUMMARY_WAIT_GRACE_MS) {
                            kotlinx.coroutines.delay(McpTaskManager.POLL_INTERVAL_MS)
                            continue
                        }
                    }
                    return McpResponseBuilder.buildFinishedResponse(state)
                }
                TaskStatus.ERROR -> return McpResponseBuilder.buildErrorResponse(state)
                TaskStatus.CANCELLED -> return McpResponseBuilder.buildErrorText("Task was cancelled.")
                TaskStatus.WAITING_INPUT -> return McpResponseBuilder.buildWaitingInputResponse(state)
                TaskStatus.USER_PAUSED -> return McpResponseBuilder.buildUserPausedResponse(state)
                TaskStatus.SCREEN_LOCKED -> {
                    // 息屏时返回提示，让 LLM 告知用户解锁并调用 task_wait_unlock
                    return McpResponseBuilder.buildScreenLockedResponse(state, isInitial = false)
                }
                TaskStatus.RUNNING -> kotlinx.coroutines.delay(McpTaskManager.POLL_INTERVAL_MS)
            }
        }
        
        // 超时但任务仍在运行
        val state = McpTaskManager.getTask(taskId)
        if (state?.status == TaskStatus.FINISHED) {
            return McpResponseBuilder.buildFinishedResponse(state)
        }
        return McpResponseBuilder.buildTimeoutResponse(taskId, goal, state)
    }

    private fun buildFileTransferResponse(record: McpFileRecord): Map<String, Any?> {
        val issued = McpFileInbox.issueDownloadToken(record)
        val state = McpServerManager.currentState()
        val host = state.host ?: McpNetworkUtils.currentLanIp()
        if (host.isNullOrBlank()) {
            return McpResponseBuilder.buildErrorText("LAN IP not available. Please ensure the device is on a LAN-accessible network.")
        }
        val url = "http://$host:${state.port}/mcp/file/${issued.id}?token=${issued.downloadToken}"
        val text = buildString {
            appendLine("File ready for download.")
            appendLine("")
            appendLine("File ID: ${issued.id}")
            appendLine("Name: ${issued.fileName}")
            appendLine("Size: ${issued.sizeBytes} bytes")
            appendLine("MIME: ${issued.mimeType ?: "unknown"}")
            appendLine("ReceivedAt: ${issued.createdAt}")
            appendLine("")
            appendLine("Download URL (valid ~15 minutes):")
            appendLine(url)
        }
        return mapOf(
            "content" to listOf(mapOf("type" to "text", "text" to text)),
            "file" to mapOf(
                "id" to issued.id,
                "name" to issued.fileName,
                "mimeType" to issued.mimeType,
                "sizeBytes" to issued.sizeBytes,
                "receivedAt" to issued.createdAt,
                "downloadUrl" to url,
                "tokenExpiresAt" to issued.tokenExpiresAt,
            )
        )
    }

    /**
     * 内部方法：启动VLM任务
     */
    private suspend fun startVlmTaskInternal(
        context: Context,
        payload: VlmTaskRequest,
        taskId: String,
        taskState: TaskState,
        scope: CoroutineScope
    ): Result<Unit> {
        val deferred = CompletableDeferred<Result<Unit>>()
        mainHandler.post {
            scope.launch(Dispatchers.Main) {
                try {
                    AssistsUtil.Core.createVLMOperationTask(
                        context = context,
                        goal = payload.goal,
                        model = payload.model,
                        maxSteps = payload.maxSteps,
                        packageName = payload.packageName,
                        onMessagePushListener = buildListener(taskId, taskState, scope),
                        needSummary = payload.needSummary ?: false,
                        onCompileGateResolved = { gateResult ->
                            if (gateResult.summary.isNotBlank()) {
                                taskState.addChatMessage(gateResult.summary)
                            }
                        },
                    )
                    deferred.complete(Result.success(Unit))
                } catch (e: Exception) {
                    taskState.status = TaskStatus.ERROR
                    taskState.message = e.message ?: "Unknown error"
                    deferred.complete(Result.failure(e))
                }
            }
        }
        return deferred.await()
    }

    /**
     * 构建 VLM 任务消息监听器
     */
    private fun buildListener(taskId: String, taskState: TaskState, scope: CoroutineScope): OnMessagePushListener {
        return object : OnMessagePushListener {
            override suspend fun onChatMessage(taskID: String, content: String, type: String?) {
                OmniLog.v(TAG, "MCP[$taskId] chat: $content type: $type")
                if (content.isNotBlank()) {
                    if (isSummaryMessage(taskID)) {
                        val summary = extractSummaryText(content) ?: content
                        if (summary.isNotBlank()) {
                            taskState.updateSummary(summary)
                        }
                    } else {
                        taskState.addChatMessage(content)
                    }
                }
            }

            override suspend fun onChatMessageEnd(taskID: String) {
                OmniLog.v(TAG, "MCP[$taskId] chat end")
            }

            override fun onTaskFinish() {
                OmniLog.d(TAG, "MCP[$taskId] task finished")
                taskState.status = TaskStatus.FINISHED
                taskState.message = "任务完成"
                McpTaskManager.scheduleTaskCleanup(taskId, scope)
            }

            override fun onVLMTaskFinish() {
                OmniLog.d(TAG, "MCP[$taskId] vlm finished")
                if (taskState.status == TaskStatus.RUNNING) {
                    taskState.status = TaskStatus.FINISHED
                    taskState.message = "VLM任务执行完成"
                }
                McpTaskManager.scheduleTaskCleanup(taskId, scope)
            }

            override fun onVLMRequestUserInput(question: String) {
                OmniLog.d(TAG, "MCP[$taskId] request input: $question")
                taskState.status = TaskStatus.WAITING_INPUT
                taskState.waitingQuestion = question
                taskState.message = "等待用户输入"
                taskState.addChatMessage("[AGENT QUESTION] $question")
            }
        }
    }

    private fun isSummaryMessage(taskId: String): Boolean {
        val normalized = taskId.lowercase()
        return normalized.startsWith("vlm-summary-")
    }

    private fun extractSummaryText(content: String): String? {
        val trimmed = content.trim()
        if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) {
            return null
        }
        return try {
            val json = JSONObject(trimmed)
            json.optString("text", "").takeIf { it.isNotBlank() }
        } catch (_: Exception) {
            null
        }
    }

    private fun shouldEnableSummary(goal: String, needSummaryArg: Boolean?): Boolean {
        return (needSummaryArg == true) || hasSummaryIntent(goal)
    }

    private fun hasSummaryIntent(goal: String): Boolean {
        if (goal.isBlank()) return false
        val keywords = listOf(
            "总结", "汇总", "整理", "要点", "概括", "归纳", "提炼", "总结一下",
            "summary", "summarize", "recap", "tl;dr", "tl;dr."
        )
        return keywords.any { goal.contains(it, ignoreCase = true) }
    }

    private suspend fun notifySummarySheetReadyWithRetry(): Boolean {
        var notified = AssistsUtil.Core.notifySummarySheetReady()
        if (notified) return true
        repeat(3) {
            kotlinx.coroutines.delay(300L)
            notified = AssistsUtil.Core.notifySummarySheetReady()
            if (notified) return true
        }
        return false
    }
}
