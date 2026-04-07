package cn.com.omnimind.bot.agent

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentToolDefinitionsMusicTest {

    @Test
    fun `music playback tool is exposed in static tools`() {
        val toolNames = AgentToolDefinitions.staticTools()
            .mapNotNull { definition ->
                ((definition["function"] as? JsonObject)
                    ?.get("name")
                    ?.jsonPrimitive
                    ?.contentOrNull)
            }

        assertTrue(toolNames.contains("music_playback_control"))
    }

    @Test
    fun `artifact ref treats pdf and html as inline renderable resources`() {
        val pdf = ArtifactRef(
            id = "pdf",
            uri = "omnibot://workspace/docs/spec.pdf",
            title = "spec.pdf",
            mimeType = "application/pdf",
            size = 128,
            sourceTool = "test",
            workspacePath = "/workspace/docs/spec.pdf",
            androidPath = "/tmp/spec.pdf",
            previewKind = "pdf"
        )
        val html = pdf.copy(
            id = "html",
            uri = "omnibot://workspace/docs/index.html",
            title = "index.html",
            mimeType = "text/html",
            androidPath = "/tmp/index.html",
            previewKind = "html"
        )

        assertEquals("pdf", pdf.embedKind)
        assertTrue(pdf.inlineRenderable)
        assertEquals("[spec.pdf](omnibot://workspace/docs/spec.pdf)", pdf.renderMarkdown)

        assertEquals("html", html.embedKind)
        assertTrue(html.inlineRenderable)
        assertEquals("[index.html](omnibot://workspace/docs/index.html)", html.renderMarkdown)
    }
}
