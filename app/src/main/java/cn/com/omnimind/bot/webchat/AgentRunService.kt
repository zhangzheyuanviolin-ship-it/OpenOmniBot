package cn.com.omnimind.bot.webchat

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import cn.com.omnimind.bot.manager.AssistsCoreManager
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class AgentRunService(
    private val context: Context
) {
    suspend fun startConversationRun(
        conversationId: Long,
        request: Map<String, Any?>
    ): Map<String, Any?> {
        val manager = AssistsCoreManager.sharedInstanceOrCreate(context)
        if (manager.hasActiveAgentRuns()) {
            throw IllegalStateException("设备当前已有运行中的 Agent 任务，请稍后重试")
        }
        val taskId = request["taskId"]?.toString()?.trim()?.ifEmpty { null }
            ?: UUID.randomUUID().toString()
        val arguments = linkedMapOf<String, Any?>(
            "taskId" to taskId,
            "conversationId" to conversationId,
            "conversationMode" to normalizeConversationMode(
                request["conversationMode"]?.toString()
            ),
            "userMessage" to (request["userMessage"]?.toString() ?: ""),
            "attachments" to normalizeListOfMaps(request["attachments"]),
            "terminalEnvironment" to normalizeMap(request["terminalEnvironment"]),
            "modelOverride" to normalizeMap(request["modelOverride"])
        )
        invokeManagerNonBlocking("createAgentTask", arguments) {
            manager.createAgentTask(it, this)
        }
        return mapOf(
            "taskId" to taskId,
            "status" to "accepted"
        )
    }

    suspend fun cancelTask(taskId: String?): Map<String, Any?> {
        val manager = AssistsCoreManager.sharedInstanceOrCreate(context)
        invokeManager(
            method = "cancelRunningTask",
            arguments = taskId?.let { mapOf("taskId" to it) }
        ) {
            manager.cancelRunningTask(it, this)
        }
        return mapOf(
            "taskId" to taskId,
            "status" to "cancelled"
        )
    }

    suspend fun clarifyTask(taskId: String?, reply: String): Map<String, Any?> {
        val manager = AssistsCoreManager.sharedInstanceOrCreate(context)
        invokeManager(
            method = "provideUserInputToVLMTask",
            arguments = mapOf("taskId" to taskId, "userInput" to reply)
        ) {
            manager.provideUserInputToVLMTask(it, this)
        }
        return mapOf(
            "taskId" to taskId,
            "status" to "submitted"
        )
    }

    private suspend fun invokeManager(
        method: String,
        arguments: Map<String, Any?>?,
        block: MethodChannel.Result.(MethodCall) -> Unit
    ): Any? {
        return suspendCancellableCoroutine { continuation ->
            val call = MethodCall(method, arguments)
            val result = object : MethodChannel.Result {
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
                                "$errorCode: ${errorMessage ?: "native bridge error"}"
                            )
                        )
                    }
                }

                override fun notImplemented() {
                    if (!continuation.isCompleted) {
                        continuation.resumeWithException(
                            NotImplementedError("Method not implemented: $method")
                        )
                    }
                }
            }
            result.block(call)
        }
    }

    private fun invokeManagerNonBlocking(
        method: String,
        arguments: Map<String, Any?>?,
        block: MethodChannel.Result.(MethodCall) -> Unit
    ) {
        val returned = AtomicBoolean(false)
        val syncFailure = AtomicReference<Throwable?>(null)
        val call = MethodCall(method, arguments)
        val result = object : MethodChannel.Result {
            override fun success(result: Any?) {
                // Non-blocking invocation only cares about synchronous validation failures.
            }

            override fun error(
                errorCode: String,
                errorMessage: String?,
                errorDetails: Any?
            ) {
                if (!returned.get()) {
                    syncFailure.set(
                        IllegalStateException(
                            "$errorCode: ${errorMessage ?: "native bridge error"}"
                        )
                    )
                }
            }

            override fun notImplemented() {
                if (!returned.get()) {
                    syncFailure.set(
                        NotImplementedError("Method not implemented: $method")
                    )
                }
            }
        }
        result.block(call)
        returned.set(true)
        syncFailure.get()?.let { throw it }
    }

    private fun normalizeConversationMode(rawMode: String?): String {
        val normalized = rawMode?.trim()?.lowercase().orEmpty()
        return if (normalized.isEmpty()) "normal" else normalized
    }

    private fun normalizeMap(value: Any?): Map<String, Any?>? {
        return (value as? Map<*, *>)?.entries?.associate { entry ->
            entry.key.toString() to normalizeValue(entry.value)
        }
    }

    private fun normalizeListOfMaps(value: Any?): List<Map<String, Any?>> {
        return (value as? List<*>)?.mapNotNull { entry ->
            normalizeMap(entry)
        } ?: emptyList()
    }

    private fun normalizeValue(value: Any?): Any? {
        return when (value) {
            is Map<*, *> -> normalizeMap(value)
            is List<*> -> value.map { normalizeValue(it) }
            else -> value
        }
    }
}
