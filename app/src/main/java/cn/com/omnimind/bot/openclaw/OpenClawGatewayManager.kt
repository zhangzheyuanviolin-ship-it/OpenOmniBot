package cn.com.omnimind.bot.openclaw

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import kotlinx.coroutines.delay

object OpenClawGatewayManager {
    data class GatewayStatus(
        val installed: Boolean,
        val configured: Boolean,
        val autoStartEnabled: Boolean,
        val running: Boolean,
        val healthy: Boolean,
        val restarting: Boolean,
        val dashboardUrl: String?,
        val lastError: String?,
        val legacyConfigNeedsRedeploy: Boolean,
        val uptimeSeconds: Long?
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "installed" to installed,
            "configured" to configured,
            "autoStartEnabled" to autoStartEnabled,
            "running" to running,
            "healthy" to healthy,
            "restarting" to restarting,
            "dashboardUrl" to dashboardUrl,
            "lastError" to lastError,
            "legacyConfigNeedsRedeploy" to legacyConfigNeedsRedeploy,
            "uptimeSeconds" to uptimeSeconds
        )
    }

    private data class LiveState(
        val running: Boolean = false,
        val healthy: Boolean = false,
        val restarting: Boolean = false,
        val startedAt: Long? = null,
        val adoptedExistingInstance: Boolean = false,
        val lastError: String? = null,
        val recentLogs: List<String> = emptyList()
    )

    private const val MAX_RECENT_LOGS = 240
    private val lock = Any()
    private var liveState = LiveState()

    fun appendLogLine(context: Context, line: String) {
        val normalized = line.trimEnd()
        if (normalized.isBlank()) {
            return
        }
        synchronized(lock) {
            val nextLogs = (liveState.recentLogs + normalized).takeLast(MAX_RECENT_LOGS)
            liveState = liveState.copy(recentLogs = nextLogs)
        }
        OpenClawRuntimeSupport.appendGatewayLogLine(context, normalized)
    }

    fun markStarting(context: Context, restarting: Boolean = false) {
        synchronized(lock) {
            liveState = liveState.copy(
                running = true,
                healthy = false,
                restarting = restarting,
                lastError = null,
                startedAt = liveState.startedAt ?: System.currentTimeMillis(),
                adoptedExistingInstance = false
            )
        }
        if (!restarting) {
            OpenClawRuntimeSupport.clearLastGatewayError(context)
        }
    }

    fun markRunning(
        context: Context,
        healthy: Boolean,
        restarting: Boolean = false,
        adoptedExistingInstance: Boolean = false,
        startedAt: Long = System.currentTimeMillis()
    ) {
        synchronized(lock) {
            liveState = liveState.copy(
                running = true,
                healthy = healthy,
                restarting = restarting,
                startedAt = startedAt,
                adoptedExistingInstance = adoptedExistingInstance,
                lastError = null
            )
        }
        OpenClawRuntimeSupport.clearLastGatewayError(context)
    }

    fun updateHealth(context: Context, healthy: Boolean) {
        synchronized(lock) {
            liveState = liveState.copy(
                running = liveState.running || healthy,
                healthy = healthy
            )
        }
        if (healthy) {
            OpenClawRuntimeSupport.clearLastGatewayError(context)
        }
    }

    fun markStopped(context: Context, lastError: String? = null) {
        synchronized(lock) {
            liveState = liveState.copy(
                running = false,
                healthy = false,
                restarting = false,
                startedAt = null,
                adoptedExistingInstance = false,
                lastError = lastError?.trim()?.takeIf { it.isNotEmpty() }
            )
        }
        if (lastError.isNullOrBlank()) {
            OpenClawRuntimeSupport.clearLastGatewayError(context)
        } else {
            OpenClawRuntimeSupport.setLastGatewayError(context, lastError)
        }
    }

    fun markRestarting(context: Context, reason: String?) {
        synchronized(lock) {
            liveState = liveState.copy(
                running = true,
                healthy = false,
                restarting = true,
                lastError = reason?.trim()?.takeIf { it.isNotEmpty() }
            )
        }
        if (!reason.isNullOrBlank()) {
            OpenClawRuntimeSupport.setLastGatewayError(context, reason)
        }
    }

    fun getRecentLogs(): List<String> {
        return synchronized(lock) { liveState.recentLogs }
    }

    fun setAutoStartEnabled(context: Context, enabled: Boolean) {
        OpenClawRuntimeSupport.setGatewayAutoStartEnabled(context, enabled)
    }

    fun startGateway(context: Context, forceRestart: Boolean = false) {
        markStarting(context, restarting = forceRestart)
        val intent = Intent(context, OpenClawGatewayService::class.java).apply {
            action = if (forceRestart) {
                OpenClawGatewayService.ACTION_RESTART
            } else {
                OpenClawGatewayService.ACTION_START
            }
        }
        ContextCompat.startForegroundService(context, intent)
    }

    fun stopGateway(context: Context) {
        val intent = Intent(context, OpenClawGatewayService::class.java).apply {
            action = OpenClawGatewayService.ACTION_STOP
        }
        context.startService(intent)
    }

    suspend fun awaitHealthy(context: Context, timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (getGatewayStatus(context).healthy) {
                return true
            }
            delay(1200L)
        }
        return getGatewayStatus(context).healthy
    }

    fun restoreIfNeeded(context: Context) {
        if (!OpenClawRuntimeSupport.isGatewayAutoStartEnabled(context)) {
            return
        }
        if (!OpenClawRuntimeSupport.isOpenClawInstalled(context)) {
            return
        }
        if (!OpenClawRuntimeSupport.isGatewayConfigured(context)) {
            return
        }
        if (OpenClawRuntimeSupport.legacyConfigNeedsRedeploy(context)) {
            return
        }
        startGateway(context, forceRestart = false)
    }

    fun getGatewayStatus(context: Context): GatewayStatus {
        val config = OpenClawRuntimeSupport.inspectGatewayConfig(context)
        val installed = OpenClawRuntimeSupport.isOpenClawInstalled(context)
        val configured = config.exists && config.authMode == "token"
        val autoStartEnabled = OpenClawRuntimeSupport.isGatewayAutoStartEnabled(context)
        val legacyConfigNeedsRedeploy = OpenClawRuntimeSupport.legacyConfigNeedsRedeploy(context)
        val dashboardUrl = OpenClawRuntimeSupport.dashboardUrlForToken(config.token)
            ?: OpenClawRuntimeSupport.dashboardUrlForToken(OpenClawRuntimeSupport.readPersistedGatewayToken(context))

        val state = synchronized(lock) { liveState }
        val portHealthy = if (state.running || configured || installed) {
            runCatching { OpenClawRuntimeSupport.isGatewayHealthy() }.getOrDefault(false)
        } else {
            false
        }
        val effectiveRunning = state.running || portHealthy
        val effectiveHealthy = state.healthy || portHealthy

        val lastError = state.lastError
            ?: OpenClawRuntimeSupport.legacyRedeployMessage(context)
            ?: OpenClawRuntimeSupport.readLastGatewayError(context)

        val uptimeSeconds = state.startedAt?.let {
            ((System.currentTimeMillis() - it).coerceAtLeast(0L) / 1000L)
        }

        return GatewayStatus(
            installed = installed,
            configured = configured,
            autoStartEnabled = autoStartEnabled,
            running = effectiveRunning,
            healthy = effectiveHealthy,
            restarting = state.restarting,
            dashboardUrl = dashboardUrl,
            lastError = lastError,
            legacyConfigNeedsRedeploy = legacyConfigNeedsRedeploy,
            uptimeSeconds = uptimeSeconds
        )
    }
}
