package cn.com.omnimind.bot.sync

import android.content.Context
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

object DataSyncScheduler {
    private const val PERIODIC_WORK_NAME = "data_sync_periodic_pull"
    private const val IMMEDIATE_WORK_NAME = "data_sync_immediate"
    private const val PREFS_NAME = "data_sync_runtime"
    private const val KEY_LAST_FOREGROUND_TRIGGER_AT = "last_foreground_trigger_at"
    private const val FOREGROUND_DEBOUNCE_MS = 2 * 60 * 1000L

    fun ensureScheduledIfEnabled(context: Context, config: DataSyncConfig) {
        val workManager = WorkManager.getInstance(context.applicationContext)
        if (!config.enabled || !config.isConfigured()) {
            workManager.cancelUniqueWork(PERIODIC_WORK_NAME)
            return
        }
        val request = PeriodicWorkRequestBuilder<DataSyncWorker>(15, TimeUnit.MINUTES)
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .setInputData(
                Data.Builder()
                    .putString(DataSyncWorker.KEY_REASON, "periodic_pull")
                    .putBoolean(DataSyncWorker.KEY_FOREGROUND, false)
                    .build()
            )
            .build()
        workManager.enqueueUniquePeriodicWork(
            PERIODIC_WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            request
        )
    }

    fun requestSyncNow(context: Context, reason: String, foreground: Boolean) {
        val request = OneTimeWorkRequestBuilder<DataSyncWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .setInputData(
                Data.Builder()
                    .putString(DataSyncWorker.KEY_REASON, reason)
                    .putBoolean(DataSyncWorker.KEY_FOREGROUND, foreground)
                    .build()
            )
            .build()
        WorkManager.getInstance(context.applicationContext)
            .enqueueUniqueWork(
                IMMEDIATE_WORK_NAME,
                ExistingWorkPolicy.REPLACE,
                request
            )
    }

    fun requestForegroundSyncIfDue(context: Context, config: DataSyncConfig) {
        if (!config.enabled || !config.isConfigured()) return
        val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        if (now - prefs.getLong(KEY_LAST_FOREGROUND_TRIGGER_AT, 0L) < FOREGROUND_DEBOUNCE_MS) {
            return
        }
        prefs.edit().putLong(KEY_LAST_FOREGROUND_TRIGGER_AT, now).apply()
        requestSyncNow(context, reason = "app_foreground", foreground = false)
    }
}
