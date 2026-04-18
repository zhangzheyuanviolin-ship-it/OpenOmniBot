package cn.com.omnimind.bot.sync

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ListenableWorker
import androidx.work.WorkerParameters
import cn.com.omnimind.baselib.util.OmniLog

class DataSyncWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {
    companion object {
        const val KEY_REASON = "reason"
        const val KEY_FOREGROUND = "foreground"
    }

    override suspend fun doWork(): ListenableWorker.Result {
        val reason = inputData.getString(KEY_REASON).orEmpty().ifBlank { "background" }
        val foreground = inputData.getBoolean(KEY_FOREGROUND, false)
        return runCatching {
            val manager = DataSyncManager.get(applicationContext)
            manager.runSync(
                reason = reason,
                foreground = foreground
            ) { progress ->
                if (foreground) {
                    setForeground(DataSyncNotifications.foregroundInfo(applicationContext, progress))
                }
            }
            ListenableWorker.Result.success()
        }.getOrElse { error ->
            OmniLog.e("DataSyncWorker", "Sync failed: ${error.message}", error)
            ListenableWorker.Result.retry()
        }
    }
}
