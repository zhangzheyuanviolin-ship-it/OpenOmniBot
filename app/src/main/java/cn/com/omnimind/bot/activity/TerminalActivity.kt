package cn.com.omnimind.bot.activity

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.lifecycle.lifecycleScope
import cn.com.omnimind.bot.terminal.EmbeddedTerminalRuntime
import com.ai.assistance.operit.terminal.TerminalManager
import com.ai.assistance.operit.terminal.main.TerminalScreen
import com.ai.assistance.operit.terminal.provider.type.TerminalType
import com.ai.assistance.operit.terminal.rememberTerminalEnv
import kotlinx.coroutines.launch

class TerminalActivity : ComponentActivity() {
    companion object {
        const val EXTRA_OPEN_SETUP = "open_setup"
    }

    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        getSharedPreferences("terminal_prefs", MODE_PRIVATE)
            .edit()
            .putBoolean("is_first_launch", false)
            .apply()

        lifecycleScope.launch {
            prepareLocalSession()
        }

        setContent {
            val terminalManager = remember { TerminalManager.getInstance(this) }
            val requestedOpenSetup = intent?.getBooleanExtra(EXTRA_OPEN_SETUP, false) == true
            val forceShowSetup by produceState(initialValue = false) {
                value =
                    if (requestedOpenSetup) {
                        true
                    } else {
                        runCatching {
                            val readiness =
                                EmbeddedTerminalRuntime.inspectRuntimeReadiness(this@TerminalActivity)
                            !(readiness.supported && readiness.runtimeReady)
                        }.getOrDefault(false)
                    }
            }
            val env = rememberTerminalEnv(terminalManager, forceShowSetup = forceShowSetup)

            MaterialTheme {
                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { Text("终端") },
                            navigationIcon = {
                                IconButton(onClick = ::finish) {
                                    androidx.compose.material3.Icon(
                                        imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                                        contentDescription = "返回"
                                    )
                                }
                            }
                        )
                    }
                ) { paddingValues ->
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(paddingValues)
                    ) {
                        TerminalScreen(env)
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        TerminalManager.getInstance(this).setPreferredTerminalType(null)
        super.onDestroy()
    }

    private suspend fun prepareLocalSession() {
        runCatching {
            val terminalManager = TerminalManager.getInstance(this)
            terminalManager.prepareForMaintenance()
            terminalManager.setPreferredTerminalType(TerminalType.LOCAL)
            val localSession = terminalManager.createNewSession("OpenClaw", TerminalType.LOCAL)
            terminalManager.switchToSession(localSession.id)
        }
    }
}
