package cn.com.omnimind.bot.agent

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

class AgentLlmStreamAccumulatorTest {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
        explicitNulls = false
    }

    @Test
    fun `treats leading text before closing think tag as reasoning for local models`() {
        val accumulator = AgentLlmStreamAccumulator(
            json = json,
            preferInlineThinkTags = true
        )

        accumulator.consume("""{"choices":[{"delta":{"content":"先思考第一步"}}]}""")
        accumulator.consume("""{"choices":[{"delta":{"content":"再思考第二步</think>最后回答"}}]}""")

        val turn = accumulator.buildTurn()

        assertEquals("先思考第一步再思考第二步", turn.reasoning)
        assertEquals("最后回答", turn.message.contentText())
    }

    @Test
    fun `flushes pending text as normal content when no think tag appears`() {
        val accumulator = AgentLlmStreamAccumulator(
            json = json,
            preferInlineThinkTags = true
        )

        accumulator.consume("""{"choices":[{"delta":{"content":"普通回答"}}]}""")

        val turn = accumulator.buildTurn()

        assertEquals("", turn.reasoning)
        assertEquals("普通回答", turn.message.contentText())
    }
}
