package cn.com.omnimind.bot.openclaw

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import cn.com.omnimind.bot.R
import cn.com.omnimind.bot.activity.MainActivity
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.BufferedReader
import java.io.InputStreamReader

class OpenClawGatewayService : Service() {
    companion object {
        const val ACTION_START = "cn.com.omnimind.bot.openclaw.action.START"
        const val ACTION_RESTART = "cn.com.omnimind.bot.openclaw.action.RESTART"
        const val ACTION_STOP = "cn.com.omnimind.bot.openclaw.action.STOP"

        private const val CHANNEL_ID = "openclaw_gateway"
        private const val NOTIFICATION_ID = 118789
        private const val WAKE_LOCK_TAG = "omnibot:openclaw_gateway"
        private val RESTART_BACKOFF_MS = longArrayOf(2_000L, 4_000L, 8_000L, 16_000L, 16_000L)
        private const val STABLE_UPTIME_RESET_MS = 60_000L
        private const val HEALTH_CHECK_INTERVAL_MS = 5_000L
    }

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val startMutex = Mutex()
    private var gatewayProcess: Process? = null
    private var stdoutJob: Job? = null
    private var stderrJob: Job? = null
    private var processWatchJob: Job? = null
    private var healthJob: Job? = null
    private var notificationJob: Job? = null
    private var restartJob: Job? = null
    private var wakeLock: PowerManager.WakeLock? = null
    @Volatile private var stopping = false
    private var startedAt: Long = 0L
    private var restartAttempt = 0
    private var adoptedExistingInstance = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        startForeground(NOTIFICATION_ID, buildNotification("准备启动 OpenClaw Gateway"))
        when (action) {
            ACTION_STOP -> {
                serviceScope.launch {
                    stopGateway(userInitiated = true)
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }

            ACTION_RESTART -> {
                serviceScope.launch {
                    launchGateway(forceRestart = true)
                }
            }

            else -> {
                serviceScope.launch {
                    launchGateway(forceRestart = false)
                }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        runBlocking {
            stopGateway(userInitiated = false)
        }
        serviceScope.cancel()
        super.onDestroy()
    }

    private suspend fun launchGateway(forceRestart: Boolean) {
        startMutex.withLock {
            stopping = false
            acquireWakeLock()
            cancelRestartJob()
            if (forceRestart) {
                performHardStop()
            }

            OpenClawRuntimeSupport.ensureRuntimeFiles(this)
            if (!OpenClawRuntimeSupport.isOpenClawInstalled(this)) {
                failAndStop("OpenClaw 尚未安装完成，请先执行部署。")
                return
            }
            if (!OpenClawRuntimeSupport.isGatewayConfigured(this)) {
                failAndStop("OpenClaw 配置缺失，请先完成部署。")
                return
            }
            if (OpenClawRuntimeSupport.legacyConfigNeedsRedeploy(this)) {
                failAndStop("检测到旧版 OpenClaw 配置，请重新保存或重新部署一次。")
                return
            }

            val providerApiKey = OpenClawRuntimeSupport.readProviderApiKey(this)
            if (providerApiKey.isNullOrBlank()) {
                failAndStop("缺少 Provider API key，请重新保存配置或重新部署。")
                return
            }

            if (!OpenClawRuntimeSupport.ensureOpenClawWrapper(this)) {
                failAndStop("OpenClaw CLI 安装不完整，请重新部署以修复可执行入口。")
                return
            }

            if (!forceRestart && OpenClawRuntimeSupport.isGatewayHealthy()) {
                startedAt = System.currentTimeMillis()
                adoptedExistingInstance = true
                OpenClawGatewayManager.appendLogLine(this, "[INFO] 发现已在运行的本机 Gateway，已接管状态追踪。")
                OpenClawGatewayManager.markRunning(
                    context = this,
                    healthy = true,
                    restarting = false,
                    adoptedExistingInstance = true,
                    startedAt = startedAt
                )
                updateNotification("Gateway 已连接，正在持续守护")
                startHealthMonitor()
                startNotificationTicker()
                return
            }

            performHardStop()

            OpenClawGatewayManager.markStarting(this, restarting = forceRestart)
            updateNotification(if (forceRestart) "Gateway 重启中" else "Gateway 启动中")
            OpenClawGatewayManager.appendLogLine(this, "[INFO] 正在启动 OpenClaw Gateway...")

            val builder = OpenClawRuntimeSupport.buildGatewayProcessBuilder(this, providerApiKey)
            val process = builder.start()
            gatewayProcess = process
            adoptedExistingInstance = false
            startedAt = System.currentTimeMillis()
            OpenClawGatewayManager.markRunning(
                context = this,
                healthy = false,
                restarting = false,
                adoptedExistingInstance = false,
                startedAt = startedAt
            )
            startReaderJobs(process)
            startProcessWatcher(process)
            startHealthMonitor()
            startNotificationTicker()
        }
    }

    private fun startReaderJobs(process: Process) {
        stdoutJob?.cancel()
        stderrJob?.cancel()
        stdoutJob = serviceScope.launch {
            readProcessStream(process.inputStream, prefix = "[OUT]")
        }
        stderrJob = serviceScope.launch {
            readProcessStream(process.errorStream, prefix = "[ERR]")
        }
    }

    private suspend fun readProcessStream(inputStream: java.io.InputStream, prefix: String) {
        try {
            BufferedReader(InputStreamReader(inputStream)).use { reader ->
                while (true) {
                    val line = reader.readLine() ?: break
                    OpenClawGatewayManager.appendLogLine(this, "$prefix $line")
                }
            }
        } catch (_: CancellationException) {
        } catch (error: Exception) {
            OpenClawGatewayManager.appendLogLine(this, "[WARN] 日志读取失败: ${error.message}")
        }
    }

    private fun startProcessWatcher(process: Process) {
        processWatchJob?.cancel()
        processWatchJob = serviceScope.launch {
            val exitCode = runCatching { process.waitFor() }.getOrDefault(-1)
            val uptimeMs = System.currentTimeMillis() - startedAt
            OpenClawGatewayManager.appendLogLine(
                this@OpenClawGatewayService,
                "[INFO] Gateway 进程退出，exit=$exitCode，uptime=${uptimeMs / 1000}s"
            )
            gatewayProcess = null
            if (stopping) {
                OpenClawGatewayManager.markStopped(this@OpenClawGatewayService, null)
                return@launch
            }
            if (uptimeMs >= STABLE_UPTIME_RESET_MS) {
                restartAttempt = 0
            }
            scheduleRestart("Gateway 进程已退出（exit=$exitCode）")
        }
    }

    private fun startHealthMonitor() {
        healthJob?.cancel()
        healthJob = serviceScope.launch {
            while (isActive && !stopping) {
                val healthy = runCatching { OpenClawRuntimeSupport.isGatewayHealthy() }.getOrDefault(false)
                OpenClawGatewayManager.updateHealth(this@OpenClawGatewayService, healthy)
                if (healthy) {
                    updateNotification("Gateway 运行正常")
                } else if (adoptedExistingInstance) {
                    OpenClawGatewayManager.appendLogLine(
                        this@OpenClawGatewayService,
                        "[WARN] 已接管的 Gateway 失去健康状态，准备拉起新的实例。"
                    )
                    scheduleRestart("已接管的 Gateway 失去健康状态")
                    return@launch
                }
                delay(HEALTH_CHECK_INTERVAL_MS)
            }
        }
    }

    private fun startNotificationTicker() {
        notificationJob?.cancel()
        notificationJob = serviceScope.launch(Dispatchers.Default) {
            while (isActive && !stopping) {
                val uptimeText = if (startedAt > 0L) {
                    val uptimeSeconds = ((System.currentTimeMillis() - startedAt).coerceAtLeast(0L) / 1000L)
                    "Gateway 已运行 ${formatDuration(uptimeSeconds)}"
                } else {
                    "Gateway 状态同步中"
                }
                updateNotification(uptimeText)
                delay(1_000L)
            }
        }
    }

    private fun scheduleRestart(reason: String) {
        if (stopping) {
            return
        }
        if (restartAttempt >= RESTART_BACKOFF_MS.size) {
            failAndStop("$reason，自动重启次数已达上限。")
            return
        }
        val delayMs = RESTART_BACKOFF_MS[restartAttempt]
        restartAttempt += 1
        OpenClawGatewayManager.markRestarting(this, "$reason，${delayMs / 1000}s 后重试。")
        updateNotification("Gateway 重启中，${delayMs / 1000}s 后重试")
        cancelRestartJob()
        restartJob = serviceScope.launch {
            delay(delayMs)
            if (!stopping) {
                launchGateway(forceRestart = true)
            }
        }
    }

    private suspend fun stopGateway(userInitiated: Boolean) {
        stopping = true
        cancelRestartJob()
        stdoutJob?.cancel()
        stderrJob?.cancel()
        processWatchJob?.cancel()
        healthJob?.cancel()
        notificationJob?.cancel()
        stdoutJob = null
        stderrJob = null
        processWatchJob = null
        healthJob = null
        notificationJob = null
        performHardStop()
        releaseWakeLock()
        if (userInitiated) {
            OpenClawGatewayManager.markStopped(this, null)
        }
    }

    private suspend fun performHardStop() {
        runCatching { gatewayProcess?.destroy() }
        gatewayProcess = null
        runCatching { OpenClawRuntimeSupport.executeGatewayCleanup(this) }
        adoptedExistingInstance = false
    }

    private fun failAndStop(message: String) {
        OpenClawGatewayManager.appendLogLine(this, "[ERROR] $message")
        OpenClawGatewayManager.markStopped(this, message)
        updateNotification(message)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun cancelRestartJob() {
        restartJob?.cancel()
        restartJob = null
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) {
            return
        }
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseWakeLock() {
        runCatching {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        }
        wakeLock = null
    }

    private fun buildNotification(contentText: String): android.app.Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("OpenClaw Gateway")
            .setContentText(contentText)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun updateNotification(contentText: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(contentText))
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val channel = NotificationChannel(
            CHANNEL_ID,
            "OpenClaw Gateway",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "展示 OpenClaw Gateway 的守护状态"
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun formatDuration(totalSeconds: Long): String {
        val hours = totalSeconds / 3600
        val minutes = (totalSeconds % 3600) / 60
        val seconds = totalSeconds % 60
        return if (hours > 0) {
            String.format("%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format("%02d:%02d", minutes, seconds)
        }
    }
}
