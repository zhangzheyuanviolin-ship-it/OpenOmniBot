package cn.com.omnimind.bot.agent

import java.io.File
import kotlin.io.path.createTempDirectory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentWorkspaceManagerChatDocTest {

    @Test
    fun `ensureDefaultWorkspaceDocs creates CHAT md alongside other defaults`() {
        val tempRoot = createTempDirectory("workspace-docs-").toFile()
        try {
            val soulFile = File(tempRoot, ".omnibot/agent/SOUL.md")
            val chatFile = File(tempRoot, ".omnibot/agent/CHAT.md")
            val memoryFile = File(tempRoot, ".omnibot/memory/MEMORY.md")

            ensureDefaultWorkspaceDocs(
                soulFile = soulFile,
                chatFile = chatFile,
                longMemoryFile = memoryFile
            )

            assertTrue(soulFile.exists())
            assertTrue(chatFile.exists())
            assertTrue(memoryFile.exists())
            assertEquals(defaultChatTemplateText(), chatFile.readText())
        } finally {
            tempRoot.deleteRecursively()
        }
    }

    @Test
    fun `ensureDefaultWorkspaceDocs keeps existing CHAT md content`() {
        val tempRoot = createTempDirectory("workspace-docs-").toFile()
        try {
            val soulFile = File(tempRoot, ".omnibot/agent/SOUL.md")
            val chatFile = File(tempRoot, ".omnibot/agent/CHAT.md")
            val memoryFile = File(tempRoot, ".omnibot/memory/MEMORY.md")
            chatFile.parentFile?.mkdirs()
            chatFile.writeText("# CHAT\ncustom prompt\n")

            ensureDefaultWorkspaceDocs(
                soulFile = soulFile,
                chatFile = chatFile,
                longMemoryFile = memoryFile
            )

            assertEquals("# CHAT\ncustom prompt\n", chatFile.readText())
        } finally {
            tempRoot.deleteRecursively()
        }
    }
}
