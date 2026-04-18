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
import cn.com.omnimind.bot.R
import cn.com.omnimind.bot.activity.MainActivity

object DataSyncNotifications {
    private const val CHANNEL_ID = "data_sync_status"
    private const val CHANNEL_NAME = "Data Sync"
    private const val CHANNEL_DESCRIPTION = "Omnibot data synchronization status"
    private const val FOREGROUND_ID = 7010
    private const val RESULT_ID = 7011
    private const val DATA_SYNC_ROUTE = "/home/data_sync_setting"

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
        val notification = baseBuilder(context)
            .setContentTitle(progressTitle(progress))
            .setContentText(progressSummary(progress))
            .setStyle(NotificationCompat.BigTextStyle().bigText(progressBody(progress)))
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setSubText("${progress.percent.coerceIn(0, 100)}%")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setProgress(100, progress.percent.coerceIn(0, 100), false)
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
        val notification = baseBuilder(context)
            .setSmallIcon(if (error) android.R.drawable.stat_sys_warning else notificationIcon(context))
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        NotificationManagerCompat.from(context).notify(RESULT_ID, notification)
    }

    private fun baseBuilder(context: Context): NotificationCompat.Builder {
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(notificationIcon(context))
            .setContentIntent(contentIntent(context))
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setShowWhen(false)
    }

    private fun notificationIcon(context: Context): Int {
        return context.applicationInfo.icon.takeIf { it != 0 } ?: R.mipmap.ic_launcher
    }

    private fun contentIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            )
            putExtra("route", DATA_SYNC_ROUTE)
            putExtra("needClear", false)
        }
        return PendingIntent.getActivity(
            context,
            FOREGROUND_ID,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun progressTitle(progress: DataSyncProgress): String {
        return when (progress.stage) {
            "handshake" -> "正在建立安全同步连接"
            "snapshot" -> "正在整理本地同步差异"
            "push" -> "正在上传本地数据"
            "pull" -> "正在接收远端数据"
            "done" -> "数据同步已完成"
            "error" -> "数据同步失败"
            else -> "Omnibot 数据同步中"
        }
    }

    private fun progressSummary(progress: DataSyncProgress): String {
        val detail = progress.detail.ifBlank { progress.stage.ifBlank { "准备同步…" } }
        return when {
            progress.total > 0 -> "$detail · ${progress.completed.coerceAtMost(progress.total)}/${progress.total}"
            else -> detail
        }
    }

    private fun progressBody(progress: DataSyncProgress): String {
        val detail = progress.detail.ifBlank { progress.stage.ifBlank { "准备同步…" } }
        return buildString {
            append(detail)
            append('\n')
            append("总体进度 ${progress.percent.coerceIn(0, 100)}%")
            if (progress.total > 0) {
                append(" · ${progress.completed.coerceAtMost(progress.total)}/${progress.total}")
            }
        }
    }
}
