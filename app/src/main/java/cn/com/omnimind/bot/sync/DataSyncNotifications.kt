package cn.com.omnimind.bot.sync

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.ForegroundInfo
import cn.com.omnimind.bot.activity.MainActivity

object DataSyncNotifications {
    private const val CHANNEL_ID = "data_sync_status"
    private const val CHANNEL_NAME = "Data Sync"
    private const val CHANNEL_DESCRIPTION = "Omnibot data synchronization status"
    private const val FOREGROUND_ID = 7010
    private const val RESULT_ID = 7011

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = CHANNEL_DESCRIPTION
        }
        manager.createNotificationChannel(channel)
    }

    fun foregroundInfo(context: Context, progress: DataSyncProgress): ForegroundInfo {
        ensureChannel(context)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle("数据同步进行中")
            .setContentText(progress.detail.ifBlank { progress.stage.ifBlank { "准备同步…" } })
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setProgress(100, progress.percent.coerceIn(0, 100), progress.total <= 0)
            .build()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                FOREGROUND_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            ForegroundInfo(FOREGROUND_ID, notification)
        }
    }

    fun notifyResult(context: Context, title: String, message: String, error: Boolean = false) {
        ensureChannel(context)
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val contentIntent = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(
                if (error) android.R.drawable.stat_sys_warning
                else android.R.drawable.stat_sys_upload_done
            )
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .build()
        NotificationManagerCompat.from(context).notify(RESULT_ID, notification)
    }
}
