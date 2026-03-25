package cn.com.omnimind.bot.agent

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import cn.com.omnimind.baselib.util.OmniLog

class WorkspaceMemoryRollupReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action.orEmpty()
        if (action != WorkspaceMemoryRollupScheduler.ACTION_MEMORY_ROLLUP) {
            return
        }
        runCatching {
            WorkspaceMemoryRollupScheduler(context).onAlarmTriggered()
        }.onFailure {
            OmniLog.e(
                "WorkspaceMemoryRollupReceiver",
                "nightly rollup failed: ${it.message}"
            )
        }
    }
}
