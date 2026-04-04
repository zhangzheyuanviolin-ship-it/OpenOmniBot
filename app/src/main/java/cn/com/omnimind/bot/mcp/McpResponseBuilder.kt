package cn.com.omnimind.bot.mcp

/**
 * MCP 响应构建器
 */
object McpResponseBuilder {
    
    fun buildFinishedResponse(state: TaskState): Map<String, Any?> {
        val recentActivity = state.chatMessages.takeLast(5).joinToString("\n") { "- $it" }
        val recentActivityList = state.chatMessages.takeLast(5)
        val summary = state.summaryText?.takeIf { it.isNotBlank() }
        val finishedContent = state.finishedContent?.takeIf { it.isNotBlank() }
        val summaryBlock = when {
            summary != null -> "\n\nSummary:\n$summary"
            state.needSummary && state.summaryUnavailable -> "\n\nSummary:\n(unavailable)"
            state.needSummary -> "\n\nSummary:\n(pending)"
            else -> ""
        }
        return mapOf(
            "content" to listOf(mapOf(
                "type" to "text",
                "text" to """✅ Task completed successfully!

Task ID: ${state.taskId}
Goal: ${state.goal}
Status: FINISHED
${if (state.message.isNotBlank()) "Message: ${state.message}" else ""}
${if (!finishedContent.isNullOrBlank()) "Finished Content: $finishedContent" else ""}
$summaryBlock

Recent activity:
$recentActivity""".trimIndent()
            )),
            "status" to "FINISHED",
            "finishedContent" to finishedContent,
            "summary" to summary,
            "summaryUnavailable" to state.summaryUnavailable,
            "feedback" to state.feedback,
            "recentActivity" to recentActivityList
        )
    }
    
    fun buildErrorResponse(state: TaskState): Map<String, Any?> {
        return mapOf(
            "content" to listOf(mapOf(
                "type" to "text",
                "text" to """❌ Task failed with error.

Task ID: ${state.taskId}
Goal: ${state.goal}
Error: ${state.message}""".trimIndent()
            )),
            "status" to "ERROR",
            "finishedContent" to state.finishedContent,
            "summary" to state.summaryText,
            "summaryUnavailable" to state.summaryUnavailable,
            "feedback" to state.feedback,
            "recentActivity" to state.chatMessages.takeLast(5),
            "isError" to true
        )
    }
    
    fun buildWaitingInputResponse(state: TaskState): Map<String, Any?> {
        return mapOf(
            "content" to listOf(mapOf(
                "type" to "text",
                "text" to """⏸️ Task paused - Agent needs your input!

Task ID: ${state.taskId}
Goal: ${state.goal}

🤖 Agent is asking:
"${state.waitingQuestion ?: "Please provide input to continue"}"

👉 ACTION REQUIRED:
Use the 'task_reply' tool to respond:
- taskId: "${state.taskId}"
- reply: <your answer to the agent's question>

Example scenarios:
- If asked for a verification code, reply with the code
- If asked which song to play, reply with the song name
- If asked to confirm an action, reply "确认" or provide specific instructions""".trimIndent()
            )),
            "status" to "WAITING_INPUT",
            "waitingQuestion" to state.waitingQuestion,
            "finishedContent" to state.finishedContent,
            "summary" to state.summaryText,
            "summaryUnavailable" to state.summaryUnavailable,
            "feedback" to state.feedback,
            "recentActivity" to state.chatMessages.takeLast(5)
        )
    }
    
    fun buildUserPausedResponse(state: TaskState): Map<String, Any?> {
        return mapOf(
            "content" to listOf(mapOf(
                "type" to "text",
                "text" to """⏸️ Task paused by user.

Task ID: ${state.taskId}
Goal: ${state.goal}

The user has manually paused this task on the device.
The task will resume when the user continues it from the device UI.""".trimIndent()
            )),
            "status" to "USER_PAUSED",
            "recentActivity" to state.chatMessages.takeLast(5)
        )
    }

    fun buildScreenLockedResponse(state: TaskState, isInitial: Boolean): Map<String, Any?> {
        val actionText = if (isInitial) {
            """The device screen is currently locked/off. The VLM task cannot start until the screen is unlocked.

👉 ACTION REQUIRED:
Please ask the user to unlock their phone, then use 'task_wait_unlock' tool to wait for the screen to be unlocked and start the task:
- taskId: "${state.taskId}"
- goal: "${state.goal}" """
        } else {
            """The device screen was locked during task execution. The task is paused.

👉 ACTION REQUIRED:
Please ask the user to unlock their phone, then use 'task_wait_unlock' tool to resume:
- taskId: "${state.taskId}" """
        }
        
        return mapOf(
            "content" to listOf(mapOf(
                "type" to "text",
                "text" to """🔒 Screen Locked - Task Paused

Task ID: ${state.taskId}
Goal: ${state.goal}
Status: SCREEN_LOCKED

$actionText""".trimIndent()
            )),
            "status" to "SCREEN_LOCKED",
            "recentActivity" to state.chatMessages.takeLast(5)
        )
    }
    
    fun buildTimeoutResponse(taskId: String, goal: String, state: TaskState?): Map<String, Any?> {
        return mapOf(
            "content" to listOf(mapOf(
                "type" to "text",
                "text" to """Task is still running after timeout.

Task ID: $taskId
Goal: $goal
Current Status: ${state?.status?.name ?: "UNKNOWN"}

The task continues running on the device. You can:
1. Use 'task_status' with taskId="$taskId" to check current progress
2. Wait for the task to complete on the device

Recent activity:
${state?.chatMessages?.takeLast(5)?.joinToString("\n") { "- $it" } ?: "No activity yet"}""".trimIndent()
            )),
            "status" to "TIMEOUT",
            "finishedContent" to state?.finishedContent,
            "summary" to state?.summaryText,
            "summaryUnavailable" to (state?.summaryUnavailable ?: false),
            "feedback" to state?.feedback,
            "recentActivity" to (state?.chatMessages?.takeLast(5) ?: emptyList<String>())
        )
    }
    
    fun buildUnlockTimeoutResponse(taskId: String, goal: String): Map<String, Any?> {
        return mapOf(
            "content" to listOf(mapOf(
                "type" to "text",
                "text" to """⏱️ Timeout waiting for screen unlock.

Task ID: $taskId
Goal: $goal

The screen was not unlocked within the timeout period.
Please ask the user to unlock the phone and try again with 'task_wait_unlock'.""".trimIndent()
            )),
            "status" to "TIMEOUT"
        )
    }
    
    fun buildTaskStatusResponse(state: TaskState): Map<String, Any?> {
        val statusText = buildString {
            appendLine("Task ID: ${state.taskId}")
            appendLine("Goal: ${state.goal}")
            appendLine("Status: ${state.status}")
            if (state.message.isNotBlank()) {
                appendLine("Message: ${state.message}")
            }
            val finishedContent = state.finishedContent?.takeIf { it.isNotBlank() }
            if (finishedContent != null) {
                appendLine("Finished Content: $finishedContent")
            }
            val summaryValue = state.summaryText?.takeIf { it.isNotBlank() }
            if (state.needSummary || summaryValue != null) {
                appendLine(
                    "Summary: ${summaryValue ?: if (state.summaryUnavailable) "unavailable" else "pending"}"
                )
            }
            state.feedback?.takeIf { it.isNotBlank() }?.let { feedback ->
                appendLine("Feedback: $feedback")
            }
            if (state.status == TaskStatus.WAITING_INPUT && state.waitingQuestion != null) {
                appendLine("")
                appendLine("⚠️ WAITING FOR INPUT")
                appendLine("Question: ${state.waitingQuestion}")
                appendLine("")
                appendLine("Use 'task_reply' to provide the requested information.")
            }
            if (state.chatMessages.isNotEmpty()) {
                appendLine("")
                appendLine("Recent activity:")
                state.chatMessages.takeLast(5).forEach { appendLine("- $it") }
            }
        }
        return mapOf(
            "content" to listOf(mapOf("type" to "text", "text" to statusText)),
            "status" to state.status.name,
            "waitingQuestion" to state.waitingQuestion,
            "finishedContent" to state.finishedContent,
            "summary" to state.summaryText,
            "summaryUnavailable" to state.summaryUnavailable,
            "feedback" to state.feedback,
            "recentActivity" to state.chatMessages.takeLast(5)
        )
    }
    
    fun buildErrorText(message: String): Map<String, Any?> {
        return mapOf("content" to listOf(mapOf("type" to "text", "text" to message)), "isError" to true)
    }
    
    fun buildTextResponse(message: String): Map<String, Any?> {
        return mapOf("content" to listOf(mapOf("type" to "text", "text" to message)))
    }
}
