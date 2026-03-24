package cn.com.omnimind.bot.terminal

import cn.com.omnimind.bot.agent.AgentWorkspaceManager
import org.junit.Assert.assertTrue
import org.junit.Test

class EmbeddedTerminalRuntimeTest {
    @Test
    fun buildPythonEnvironmentPreludeIncludesWorkspaceVenvBootstrap() {
        val prelude = EmbeddedTerminalRuntime.buildPythonEnvironmentPrelude()

        assertTrue(prelude.contains(AgentWorkspaceManager.SHELL_ROOT_PATH))
        assertTrue(prelude.contains("HOME/.local/bin"))
        assertTrue(prelude.contains("UV_LINK_MODE=copy"))
        assertTrue(prelude.contains("UV_PROJECT_ENVIRONMENT"))
        assertTrue(prelude.contains("uv() {"))
        assertTrue(prelude.contains("command uv venv --link-mode copy"))
        assertTrue(prelude.contains("__omni_uv_resolve_target_path"))
        assertTrue(prelude.contains("__omni_cleanup_invalid_virtualenv"))
        assertTrue(prelude.contains("Removing invalid virtual environment"))
        assertTrue(prelude.contains("__omni_prepare_python_env"))
        assertTrue(prelude.contains("command python3 -m venv --copies"))
        assertTrue(prelude.contains("command python -m pip"))
        assertTrue(prelude.contains("command python -m pytest"))
        assertTrue(prelude.contains(".venv/bin/activate"))
    }
}
