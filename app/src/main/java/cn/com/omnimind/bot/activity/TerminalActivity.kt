package cn.com.omnimind.bot.activity

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AssistChip
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
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import cn.com.omnimind.bot.openclaw.OpenClawGatewayManager
import cn.com.omnimind.bot.terminal.EmbeddedTerminalRuntime
import com.ai.assistance.operit.terminal.TerminalManager
import com.ai.assistance.operit.terminal.main.TerminalScreen
import com.ai.assistance.operit.terminal.provider.type.TerminalType
import com.ai.assistance.operit.terminal.rememberTerminalEnv
import kotlinx.coroutines.launch

class TerminalActivity : ComponentActivity() {
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
            val forceShowSetup by produceState(initialValue = false) {
                value = runCatching {
                    val readiness = EmbeddedTerminalRuntime.inspectRuntimeReadiness(this@TerminalActivity)
                    !(readiness.supported && readiness.runtimeReady && readiness.basePackagesReady)
                }.getOrDefault(false)
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
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(paddingValues)
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 12.dp, vertical = 8.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            AssistChip(
                                onClick = {
                                    lifecycleScope.launch {
                                        terminalManager.sendCommand("cd /root/.openclaw/workspace")
                                    }
                                },
                                label = { Text("Workspace") }
                            )
                            AssistChip(
                                onClick = {
                                    lifecycleScope.launch {
                                        terminalManager.sendCommand("tail -n 120 /root/openclaw.log")
                                    }
                                },
                                label = { Text("Gateway 日志") }
                            )
                            AssistChip(
                                onClick = {
                                    OpenClawGatewayManager.startGateway(this@TerminalActivity, forceRestart = true)
                                },
                                label = { Text("重启 Gateway") },
                                leadingIcon = {
                                    androidx.compose.material3.Icon(
                                        Icons.Default.Refresh,
                                        contentDescription = null
                                    )
                                }
                            )
                        }
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .weight(1f)
                        ) {
                            TerminalScreen(env)
                        }
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
