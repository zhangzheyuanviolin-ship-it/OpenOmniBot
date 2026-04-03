package com.alibaba.mnnllm.api.openai.network.utils

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class ThinkingContentStreamParserTest {

    @Test
    fun closeTagWithoutOpenTag_routesPrefixToReasoning() {
        val parser = ThinkingContentStreamParser()

        assertTrue(parser.append("先思考").isEmpty())

        val deltas = parser.append("</think>最后回答")

        assertEquals(
            listOf(
                ThinkingContentStreamParser.DeltaPayload(reasoningContent = "先思考"),
                ThinkingContentStreamParser.DeltaPayload(content = "最后回答")
            ),
            deltas
        )
        assertTrue(parser.finish().isEmpty())
        assertEquals("先思考", parser.result().reasoningContent)
        assertEquals("最后回答", parser.result().content)
    }

    @Test
    fun splitCloseTagAcrossChunks_keepsReasoningAndAnswerSeparated() {
        val parser = ThinkingContentStreamParser()

        assertTrue(parser.append("分步推理</th").isEmpty())

        val deltas = parser.append("ink>输出结果")

        assertEquals(
            listOf(
                ThinkingContentStreamParser.DeltaPayload(reasoningContent = "分步推理"),
                ThinkingContentStreamParser.DeltaPayload(content = "输出结果")
            ),
            deltas
        )
        assertEquals("分步推理", parser.result().reasoningContent)
        assertEquals("输出结果", parser.result().content)
    }

    @Test
    fun openTagSplitAcrossChunks_emitsReasoningBeforeContent() {
        val parser = ThinkingContentStreamParser()

        assertTrue(parser.append("<th").isEmpty())
        assertEquals(
            listOf(ThinkingContentStreamParser.DeltaPayload(reasoningContent = "深度思考")),
            parser.append("ink>深度思考</th")
        )
        assertEquals(
            listOf(ThinkingContentStreamParser.DeltaPayload(content = "标准回答")),
            parser.append("ink>标准回答")
        )
        assertEquals("深度思考", parser.result().reasoningContent)
        assertEquals("标准回答", parser.result().content)
    }

    @Test
    fun plainContentFlushesOnFinishWithoutThinkTags() {
        val parser = ThinkingContentStreamParser()

        assertTrue(parser.append("直接回答").isEmpty())

        val deltas = parser.finish()

        assertEquals(
            listOf(ThinkingContentStreamParser.DeltaPayload(content = "直接回答")),
            deltas
        )
        assertEquals("", parser.result().reasoningContent)
        assertEquals("直接回答", parser.result().content)
    }

    @Test
    fun formatterWritesReasoningContentWithoutNullContent() {
        val formatter = ChatResponseFormatter()

        val json = formatter.createDeltaResponse(
            responseId = "chatcmpl-1",
            created = 1L,
            reasoningContent = "思考中"
        )

        assertTrue(json.contains("\"reasoning_content\":\"思考中\""))
        assertFalse(json.contains("\"content\":null"))
    }

    @Test
    fun thinkingModelMode_streamsReasoningImmediatelyBeforeCloseTag() {
        val parser = ThinkingContentStreamParser(streamLeadingReasoning = true)

        val deltas = parser.append("先想第一步")

        assertEquals(
            listOf(ThinkingContentStreamParser.DeltaPayload(reasoningContent = "先想第一步")),
            deltas
        )
        assertEquals("先想第一步", parser.result().reasoningContent)
        assertEquals("", parser.result().content)
    }

    @Test
    fun thinkingModelMode_switchesToContentAfterCloseTag() {
        val parser = ThinkingContentStreamParser(streamLeadingReasoning = true)

        assertEquals(
            listOf(ThinkingContentStreamParser.DeltaPayload(reasoningContent = "先想第一步")),
            parser.append("先想第一步")
        )
        val deltas = parser.append("</think>再给答案")

        assertEquals(
            listOf(ThinkingContentStreamParser.DeltaPayload(content = "再给答案")),
            deltas
        )
        assertEquals("先想第一步", parser.result().reasoningContent)
        assertEquals("再给答案", parser.result().content)
    }
}
