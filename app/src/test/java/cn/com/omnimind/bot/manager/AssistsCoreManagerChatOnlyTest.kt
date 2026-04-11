package cn.com.omnimind.bot.manager

import cn.com.omnimind.baselib.llm.ModelProviderProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class AssistsCoreManagerChatOnlyTest {

    @Test
    fun `prepareChatTaskContent prepends CHAT prompt only for chat_only mode`() {
        val content = listOf(
            linkedMapOf<String, Any>(
                "role" to "user",
                "content" to "hello"
            )
        )

        val chatOnlyResult = prepareChatTaskContent(
            content = content,
            conversationMode = CHAT_ONLY_MODE,
            chatPromptContent = "# CHAT\nbe helpful\n"
        )
        val normalResult = prepareChatTaskContent(
            content = content,
            conversationMode = "normal",
            chatPromptContent = "# CHAT\nbe helpful\n"
        )

        assertEquals(2, chatOnlyResult.size)
        assertEquals("system", chatOnlyResult.first()["role"])
        assertEquals("# CHAT\nbe helpful\n", chatOnlyResult.first()["content"])
        assertEquals(content.first(), chatOnlyResult[1])
        assertEquals(content, normalResult)
    }

    @Test
    fun `resolveChatTaskModelOverride uses configured provider profile`() {
        val result = resolveChatTaskModelOverride(
            raw = mapOf(
                "providerProfileId" to "provider-1",
                "modelId" to "gpt-5.4-mini"
            )
        ) { id ->
            if (id != "provider-1") {
                return@resolveChatTaskModelOverride null
            }
            ModelProviderProfile(
                id = "provider-1",
                name = "Provider One",
                baseUrl = "https://example.com/v1",
                apiKey = "secret",
                protocolType = "openai_compatible"
            )
        }

        assertNotNull(result)
        assertEquals("provider-1", result?.providerProfileId)
        assertEquals("gpt-5.4-mini", result?.modelId)
        assertEquals("https://example.com/v1", result?.apiBase)
        assertEquals("secret", result?.apiKey)
        assertEquals("openai_compatible", result?.protocolType)
    }

    @Test
    fun `resolveChatTaskModelOverride falls back when provider profile is missing or invalid`() {
        val missingProfileResult = resolveChatTaskModelOverride(
            raw = mapOf(
                "providerProfileId" to "missing-provider",
                "modelId" to "gpt-5.4-mini"
            )
        ) { _ -> null }

        val invalidProfileResult = resolveChatTaskModelOverride(
            raw = mapOf(
                "providerProfileId" to "provider-2",
                "modelId" to "gpt-5.4-mini"
            )
        ) { id ->
            ModelProviderProfile(
                id = id,
                name = "Provider Two",
                baseUrl = "",
                apiKey = "secret"
            )
        }

        assertNull(missingProfileResult)
        assertNull(invalidProfileResult)
    }

    @Test
    fun `extractChatTaskTextPayload parses OpenAI stream chunks`() {
        val chunk = """
            {"choices":[{"delta":{"content":"hello from pure chat"}}]}
        """.trimIndent()

        val result = extractChatTaskTextPayload(chunk)

        assertEquals("hello from pure chat", result)
    }

    @Test
    fun `extractChatTaskTextPayload ignores reasoning-only json chunks`() {
        val chunk = """
            {"choices":[{"delta":{"reasoning_content":"先分析一下问题。"}}]}
        """.trimIndent()

        val result = extractChatTaskTextPayload(chunk)

        assertEquals("", result)
    }
}
