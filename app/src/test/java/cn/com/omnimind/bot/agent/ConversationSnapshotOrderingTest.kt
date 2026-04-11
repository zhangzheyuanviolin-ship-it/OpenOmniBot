package cn.com.omnimind.bot.agent

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

class ConversationSnapshotOrderingTest {

    @Test
    fun `prepareForStorage sorts flutter local iso timestamps from oldest to newest`() {
        val messages = listOf(
            assistantMessage(
                id = "assistant",
                createAt = "2026-03-31T18:00:03.300",
                text = "assistant"
            ),
            deepThinkingMessage(
                id = "thinking",
                createAt = "2026-03-31T18:00:02.200",
                taskId = "task-1",
                startTime = localMillis("2026-03-31T18:00:02.200"),
                thinking = "thinking"
            ),
            userMessage(
                id = "user",
                createAt = "2026-03-31T18:00:01.100",
                text = "user"
            )
        )

        val orderedIds = ConversationSnapshotOrdering.prepareForStorage(messages)
            .map { it.payload["id"] }

        assertEquals(listOf("user", "thinking", "assistant"), orderedIds)
    }

    @Test
    fun `prepareForStorage keeps newest-first snapshot tie order reversible when timestamps match`() {
        val messages = listOf(
            assistantMessage(
                id = "1711872000300-text",
                createAt = "invalid",
                text = "assistant"
            ),
            deepThinkingMessage(
                id = "1711872000300-thinking",
                createAt = "invalid",
                taskId = "1711872000300-ai",
                startTime = 1711872000300L,
                thinking = "thinking"
            ),
            userMessage(
                id = "1711872000300-user",
                createAt = "invalid",
                text = "user"
            )
        )

        val orderedIds = ConversationSnapshotOrdering.prepareForStorage(messages)
            .map { it.payload["id"] }

        assertEquals(
            listOf(
                "1711872000300-user",
                "1711872000300-thinking",
                "1711872000300-text"
            ),
            orderedIds
        )
    }

    @Test
    fun `sortForDisplay keeps deep thinking between user and assistant after retry restore`() {
        val messages = listOf(
            userMessage(
                id = "1711872001200-user",
                createAt = "2026-03-31T18:00:01.200",
                text = "第二轮用户"
            ),
            assistantMessage(
                id = "1711872001200-text",
                createAt = "2026-03-31T18:00:01.202",
                text = "第二轮助手"
            ),
            deepThinkingMessage(
                id = "1711872001200-thinking",
                createAt = "2026-03-31T18:00:01.201",
                taskId = "1711872001200-ai",
                startTime = localMillis("2026-03-31T18:00:01.201"),
                thinking = "第二轮思考"
            ),
            userMessage(
                id = "1711872000100-user",
                createAt = "2026-03-31T18:00:00.100",
                text = "第一轮用户"
            ),
            assistantMessage(
                id = "1711872000100-text",
                createAt = "2026-03-31T18:00:00.102",
                text = "第一轮助手"
            ),
            deepThinkingMessage(
                id = "1711872000100-thinking",
                createAt = "2026-03-31T18:00:00.101",
                taskId = "1711872000100-ai",
                startTime = localMillis("2026-03-31T18:00:00.101"),
                thinking = "第一轮思考"
            )
        )

        val orderedIds = ConversationSnapshotOrdering.sortForDisplay(messages)
            .map { it["id"] }

        assertEquals(
            listOf(
                "1711872001200-text",
                "1711872001200-thinking",
                "1711872001200-user",
                "1711872000100-text",
                "1711872000100-thinking",
                "1711872000100-user"
            ),
            orderedIds
        )
    }

    @Test
    fun `prepareForStorage keeps logical phase order when persisted timestamps drift inside one task`() {
        val messages = listOf(
            assistantMessage(
                id = "1711872000100-ai-assistant",
                createAt = "2026-03-31T18:00:00.300",
                text = "助手回答"
            ),
            userMessage(
                id = "1711872000100-ai-user",
                createAt = "2026-03-31T18:00:00.200",
                text = "用户提问"
            ),
            deepThinkingMessage(
                id = "1711872000100-ai-thinking",
                createAt = "2026-03-31T18:00:00.100",
                taskId = "1711872000100-ai",
                startTime = localMillis("2026-03-31T18:00:00.100"),
                thinking = "思考过程"
            )
        )

        val orderedIds = ConversationSnapshotOrdering.prepareForStorage(messages)
            .map { it.payload["id"] }

        assertEquals(
            listOf(
                "1711872000100-ai-user",
                "1711872000100-ai-thinking",
                "1711872000100-ai-assistant"
            ),
            orderedIds
        )
    }

    private fun userMessage(
        id: String,
        createAt: String,
        text: String
    ): Map<String, Any?> {
        return linkedMapOf(
            "id" to id,
            "type" to 1,
            "user" to 1,
            "content" to linkedMapOf(
                "id" to id,
                "text" to text
            ),
            "createAt" to createAt
        )
    }

    private fun assistantMessage(
        id: String,
        createAt: String,
        text: String
    ): Map<String, Any?> {
        return linkedMapOf(
            "id" to id,
            "type" to 1,
            "user" to 2,
            "content" to linkedMapOf(
                "id" to id,
                "text" to text
            ),
            "createAt" to createAt
        )
    }

    private fun deepThinkingMessage(
        id: String,
        createAt: String,
        taskId: String,
        startTime: Long,
        thinking: String
    ): Map<String, Any?> {
        return linkedMapOf(
            "id" to id,
            "type" to 2,
            "user" to 3,
            "content" to linkedMapOf(
                "id" to id,
                "cardData" to linkedMapOf(
                    "type" to "deep_thinking",
                    "taskID" to taskId,
                    "thinkingContent" to thinking,
                    "startTime" to startTime,
                    "endTime" to (startTime + 1),
                    "stage" to 4,
                    "isLoading" to false
                )
            ),
            "createAt" to createAt
        )
    }

    private fun localMillis(value: String): Long {
        return LocalDateTime.parse(value)
            .atZone(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli()
    }
}
