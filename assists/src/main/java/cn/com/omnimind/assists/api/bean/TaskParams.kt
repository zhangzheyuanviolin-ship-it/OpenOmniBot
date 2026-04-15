package cn.com.omnimind.assists.api.bean

import cn.com.omnimind.assists.api.interfaces.OnMessagePushListener
import cn.com.omnimind.assists.task.vlmserver.OperationResult
import cn.com.omnimind.assists.task.vlmserver.TaskExecutionReport
import java.util.concurrent.TimeUnit

data class VLMTaskPreHookResult(
    val kind: String,
    val summary: String = "",
    val pathId: String? = null,
    val plannerGuidance: String = "",
    val executionRoute: String = ""
)

data class VLMTaskRunLogPayload(
    val goal: String,
    val compileGateResult: VLMTaskPreHookResult? = null,
    val taskReport: TaskExecutionReport,
    val startedAtMs: Long,
    val finishedAtMs: Long,
    val finalXml: String? = null,
    val finalPackageName: String? = null,
    val rawEvents: List<Map<String, Any?>> = emptyList(),
    val traceSessionMeta: Map<String, Any?> = emptyMap(),
)

sealed class TaskParams {
    data class OpenClawConfig(
        val baseUrl: String,
        val token: String? = null,
        val userId: String? = null,
        val sessionKey: String? = null
    )
    data class ChatModelOverride(
        val providerProfileId: String,
        val modelId: String,
        val apiBase: String,
        val apiKey: String,
        val protocolType: String = "openai_compatible"
    )
    //陪伴任务参数
    data class CompanionTaskParams(
        val companionFinishListener:()->Unit
    ) : TaskParams();
    //聊天任务参数
    data class ChatTaskParams(
        val taskId: String,
        val content: List<Map<String, Any>>,
        val onMessagePush: OnMessagePushListener,
        val provider: String? = null,
        val openClawConfig: OpenClawConfig? = null,
        val modelOverride: ChatModelOverride? = null,
        val reasoningEffort: String? = null
    ) : TaskParams();
    //VLM任务参数
    data class VLMOperationTaskParams(
        val goal: String,
        val model: String?,
        val maxSteps: Int?,
        val packageName: String?,
        val onTaskFinishListener: () -> Unit,
        val needSummary: Boolean = false,
        val onMessagePushListener: OnMessagePushListener? = null,
        val skipGoHome: Boolean = false,  // 是否跳过回到主页，从当前页面开始执行
        val stepSkillGuidance: String = "",
        val onRunCompiledPath: (suspend (String) -> OperationResult)? = null,
        val onPrepareExecution: (suspend () -> VLMTaskPreHookResult)? = null,
        val onCompileGateResolved: (suspend (VLMTaskPreHookResult) -> Unit)? = null,
        val onTaskRunLogReady: (suspend (VLMTaskRunLogPayload) -> Unit)? = null
    ): TaskParams();

    data class ScheduledTaskParams(
        val taskParams: TaskParams,
        val delay: Long,
        val timeUnit: TimeUnit=TimeUnit.SECONDS,
        val onTaskFinishListener: () -> Unit
    ): TaskParams();
    data class ScheduledVLMOperationTaskParams(
        val name: String,
        val subTitle: String?,
        val extraJson: String?,
        val goal: String,
        val model: String?,
        val maxSteps: Int?,
        val packageName: String?,
        val scheduledTaskID:String,
        val needSummary: Boolean = false,
        val onMessagePushListener: OnMessagePushListener? = null
    ): TaskParams();
}
