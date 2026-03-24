package cn.com.omnimind.bot.agent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentOrchestratorTest {
    @Test
    fun extractRecoverableToolFailureReturnsSummaryForFailedTerminalResult() {
        val failure = AgentOrchestrator.extractRecoverableToolFailure(
            toolName = "terminal_execute",
            result = ToolExecutionResult.TerminalResult(
                toolName = "terminal_execute",
                summaryText = "uv: command not found",
                previewJson = "{}",
                rawResultJson = "{}",
                success = false
            )
        )

        assertNotNull(failure)
        assertEquals("terminal_execute", failure?.toolName)
        assertEquals("uv: command not found", failure?.summary)
    }

    @Test
    fun extractRecoverableToolFailureIgnoresSuccessfulResults() {
        val failure = AgentOrchestrator.extractRecoverableToolFailure(
            toolName = "terminal_execute",
            result = ToolExecutionResult.TerminalResult(
                toolName = "terminal_execute",
                summaryText = "执行完成",
                previewJson = "{}",
                rawResultJson = "{}",
                success = true
            )
        )

        assertNull(failure)
    }

    @Test
    fun buildToolFailureRetryPromptMentionsToolAndUserRequest() {
        val prompt = AgentOrchestrator.buildToolFailureRetryPrompt(
            userMessage = "帮我继续跑 bilibili 分析脚本",
            failure = AgentOrchestrator.RecoverableToolFailure(
                toolName = "terminal_execute",
                summary = "uv: command not found"
            )
        )

        assertTrue(prompt.contains("terminal_execute"))
        assertTrue(prompt.contains("uv: command not found"))
        assertTrue(prompt.contains("帮我继续跑 bilibili 分析脚本"))
    }
}
