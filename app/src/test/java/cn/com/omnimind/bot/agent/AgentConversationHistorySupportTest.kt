package cn.com.omnimind.bot.agent

import cn.com.omnimind.baselib.database.AgentConversationEntry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlinx.serialization.json.jsonPrimitive

class AgentConversationHistorySupportTest {
    @Test
    fun `mergeToolPayload keeps args and final status across tool lifecycle`() {
        val startPayload = mapOf(
            "toolName" to "browser_use",
            "displayName" to "浏览器自动化",
            "toolType" to "builtin",
            "argsJson" to """{"url":"https://example.com","steps":2}""",
            "summary" to "打开页面"
        )
        val progressPayload = mapOf(
            "progress" to "正在分析页面",
            "summary" to "正在分析页面"
        )
        val completePayload = mapOf(
            "status" to AgentConversationHistoryRepository.STATUS_SUCCESS,
            "summary" to "已完成页面分析",
            "resultPreviewJson" to """{"message":"done"}""",
            "rawResultJson" to """{"message":"done","details":"very long raw"}""",
            "success" to true
        )

        val mergedProgress = AgentConversationHistorySupport.mergeToolPayload(
            existing = startPayload,
            incoming = progressPayload,
            fallbackStatus = AgentConversationHistoryRepository.STATUS_RUNNING,
            fallbackSummary = "正在调用工具"
        )
        val mergedComplete = AgentConversationHistorySupport.mergeToolPayload(
            existing = mergedProgress,
            incoming = completePayload,
            fallbackStatus = AgentConversationHistoryRepository.STATUS_SUCCESS,
            fallbackSummary = "已完成页面分析"
        )

        assertEquals(
            """{"url":"https://example.com","steps":2}""",
            mergedComplete["argsJson"]
        )
        assertEquals(
            AgentConversationHistoryRepository.STATUS_SUCCESS,
            mergedComplete["status"]
        )
        assertEquals("已完成页面分析", mergedComplete["summary"])
        assertEquals("""{"message":"done"}""", mergedComplete["resultPreviewJson"])
    }

    @Test
    fun `buildPromptSeedFromEntries replays per-tool summaries in chronological order`() {
        val userEntry = AgentConversationEntry(
            id = 1,
            conversationId = 7,
            conversationMode = "normal",
            entryId = "u1",
            entryType = AgentConversationHistoryRepository.ENTRY_TYPE_USER_MESSAGE,
            status = AgentConversationHistoryRepository.STATUS_SUCCESS,
            summary = "查看 example",
            payloadJson = """
                {"id":"u1","type":1,"user":1,"content":{"text":"查看 example","id":"u1"},"createAt":"2026-03-27T00:00:00Z"}
            """.trimIndent(),
            createdAt = 1,
            updatedAt = 1
        )
        val assistantEntry = AgentConversationEntry(
            id = 2,
            conversationId = 7,
            conversationMode = "normal",
            entryId = "a1",
            entryType = AgentConversationHistoryRepository.ENTRY_TYPE_ASSISTANT_MESSAGE,
            status = AgentConversationHistoryRepository.STATUS_SUCCESS,
            summary = "assistant should start being replayed",
            payloadJson = """
                {"id":"a1","type":1,"user":2,"content":{"text":"assistant should start being replayed","id":"a1"},"createAt":"2026-03-27T00:00:01Z"}
            """.trimIndent(),
            createdAt = 2,
            updatedAt = 2
        )
        val toolEntry = AgentConversationEntry(
            id = 3,
            conversationId = 7,
            conversationMode = "normal",
            entryId = "t1",
            entryType = AgentConversationHistoryRepository.ENTRY_TYPE_TOOL_EVENT,
            status = AgentConversationHistoryRepository.STATUS_SUCCESS,
            summary = "抓取成功",
            payloadJson = """
                {
                  "toolName":"browser_use",
                  "displayName":"浏览器自动化",
                  "toolType":"builtin",
                  "argsJson":"{\"url\":\"https://example.com\",\"query\":\"latest\"}",
                  "summary":"抓取成功",
                  "resultPreviewJson":"{\"title\":\"Example\"}",
                  "rawResultJson":"{\"title\":\"Example\",\"html\":\"<html>super long raw payload</html>\"}",
                  "success":true
                }
            """.trimIndent(),
            createdAt = 3,
            updatedAt = 3
        )

        val secondToolEntry = AgentConversationEntry(
            id = 4,
            conversationId = 7,
            conversationMode = "normal",
            entryId = "t2",
            entryType = AgentConversationHistoryRepository.ENTRY_TYPE_TOOL_EVENT,
            status = AgentConversationHistoryRepository.STATUS_ERROR,
            summary = "执行命令失败",
            payloadJson = """
                {
                  "toolName":"terminal_execute",
                  "displayName":"执行命令",
                  "toolType":"terminal",
                  "argsJson":"{\"command\":\"pwd\"}",
                  "summary":"执行命令失败",
                  "resultPreviewJson":"{\"message\":\"permission denied\"}",
                  "rawResultJson":"{\"message\":\"permission denied\",\"trace\":\"super long raw payload terminal\"}",
                  "terminalOutput":"permission denied",
                  "success":false
                }
            """.trimIndent(),
            createdAt = 4,
            updatedAt = 4
        )

        val seed = AgentConversationHistorySupport.buildPromptSeedFromEntries(
            listOf(userEntry, assistantEntry, toolEntry, secondToolEntry)
        )

        assertEquals(6, seed.historyMessages.size)
        assertEquals(
            listOf("user", "assistant", "assistant", "tool", "assistant", "tool"),
            seed.historyMessages.map { it.role }
        )
        assertTrue(seed.historyMessages[0].content.toString().contains("查看 example"))
        assertEquals(1, seed.historyMessages[2].toolCalls?.size)
        assertEquals("browser_use", seed.historyMessages[2].toolCalls?.single()?.function?.name)
        assertTrue(
            seed.historyMessages[2].toolCalls
                ?.single()
                ?.function
                ?.arguments
                .orEmpty()
                .contains("\"url\":\"https://example.com\"")
        )
        assertEquals("terminal_execute", seed.historyMessages[4].toolCalls?.single()?.function?.name)

        val firstToolSummary = seed.historyMessages[3].content!!.jsonPrimitive.content
        assertTrue(firstToolSummary.contains("浏览器自动化"))
        assertTrue(firstToolSummary.contains("抓取成功"))
        assertTrue(firstToolSummary.contains("previewJson"))

        val secondToolSummary = seed.historyMessages[5].content!!.jsonPrimitive.content
        assertTrue(secondToolSummary.contains("执行命令"))
        assertTrue(secondToolSummary.contains("执行命令失败"))
        assertTrue(secondToolSummary.contains("terminalOutput"))

        val allReplayText = seed.historyMessages.joinToString("\n") {
            it.content?.toString().orEmpty()
        }
        assertTrue(allReplayText.contains("assistant should start being replayed"))
        assertFalse(allReplayText.contains("super long raw payload"))
    }

    @Test
    fun `normalizeInterruptedEntries converts running tools to interrupted`() {
        val runningEntry = AgentConversationEntry(
            id = 1,
            conversationId = 9,
            conversationMode = "subagent",
            entryId = "tool-running",
            entryType = AgentConversationHistoryRepository.ENTRY_TYPE_TOOL_EVENT,
            status = AgentConversationHistoryRepository.STATUS_RUNNING,
            summary = "",
            payloadJson = """
                {"toolName":"terminal_run","displayName":"执行命令","toolType":"terminal","status":"running","summary":"","terminalOutput":"hello"}
            """.trimIndent(),
            createdAt = 1,
            updatedAt = 1
        )

        val normalized = AgentConversationHistorySupport.normalizeInterruptedEntries(
            listOf(runningEntry)
        )

        assertEquals(1, normalized.size)
        assertEquals(
            AgentConversationHistoryRepository.STATUS_INTERRUPTED,
            normalized.single().status
        )
        assertTrue(normalized.single().summary.isNotBlank())
        assertTrue(normalized.single().payloadJson.contains("\"status\":\"interrupted\""))
    }
}
