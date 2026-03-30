package com.rk.terminal.service

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.annotation.RequiresApi
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.core.app.NotificationCompat
import com.rk.resources.drawables
import com.rk.resources.strings
import com.rk.terminal.ui.activities.terminal.MainActivity
import com.rk.terminal.ui.screens.settings.Settings
import com.rk.terminal.ui.screens.terminal.HeadlessTerminalSessionClient
import com.rk.terminal.ui.screens.terminal.MkSession
import com.termux.terminal.TerminalSession

class SessionService : Service() {
    companion object {
        private const val DEFAULT_COLUMNS = 120
        private const val DEFAULT_ROWS = 40
        private const val DEFAULT_CELL_WIDTH = 10
        private const val DEFAULT_CELL_HEIGHT = 20
        private const val AGENT_SESSION_ID_PREFIX = "session_"
    }

    data class HeadlessSessionAccess(
        val sessionId: String,
        val session: TerminalSession,
        val created: Boolean
    )

    private val sessions = hashMapOf<String, TerminalSession>()
    val sessionList = mutableStateMapOf<String,Int>()
    var currentSession = mutableStateOf(Pair("main",com.rk.settings.Settings.working_Mode))

    inner class SessionBinder : Binder() {
        fun getService():SessionService{
            return this@SessionService
        }
        fun terminateAllSessions(){
            sessions.values.forEach{
                it.finishIfRunning()
            }
            sessions.clear()
            sessionList.clear()
            currentSession.value = Pair("main", com.rk.settings.Settings.working_Mode)
            updateNotification()
        }

        fun createSession(id: String, context: android.content.Context, workingMode:Int): TerminalSession {
            val existing = sessions[id]
            if (existing != null) {
                sessionList[id] = workingMode
                currentSession.value = Pair(id, workingMode)
                updateNotification()
                return existing
            }
            return MkSession.createSession(
                context,
                HeadlessTerminalSessionClient,
                id,
                workingMode = workingMode
            ).also {
                sessions[id] = it
                sessionList[id] = workingMode
                currentSession.value = Pair(id, workingMode)
                updateNotification()
            }
        }

        fun createHeadlessSession(
            requestedId: String?,
            context: android.content.Context,
            workingMode: Int,
            sessionTitle: String? = null,
            extraEnv: Map<String, String> = emptyMap()
        ): HeadlessSessionAccess {
            val sessionId = resolveSessionId(requestedId)
            val existing = sessions[sessionId]
            if (existing != null) {
                existing.mSessionName = sessionTitle?.trim().takeUnless { it.isNullOrEmpty() }
                    ?: existing.mSessionName
                sessionList[sessionId] = workingMode
                currentSession.value = Pair(sessionId, workingMode)
                updateNotification()
                return HeadlessSessionAccess(
                    sessionId = sessionId,
                    session = existing,
                    created = false
                )
            }

            val mergedEnv = linkedMapOf(
                "OMNIBOT_HEADLESS" to "1",
                "HOME" to "/root",
                "PAGER" to "cat",
                "GIT_PAGER" to "cat"
            ).apply {
                putAll(extraEnv)
            }

            val session = MkSession.createSession(
                context = context,
                sessionClient = HeadlessTerminalSessionClient,
                session_id = sessionId,
                workingMode = workingMode,
                extraEnv = mergedEnv
            ).also { created ->
                created.mSessionName = sessionTitle?.trim().takeUnless { it.isNullOrEmpty() }
                    ?: "Agent Session"
                created.updateTerminalSessionClient(HeadlessTerminalSessionClient)
                if (created.emulator == null) {
                    created.updateSize(
                        DEFAULT_COLUMNS,
                        DEFAULT_ROWS,
                        DEFAULT_CELL_WIDTH,
                        DEFAULT_CELL_HEIGHT
                    )
                }
                sessions[sessionId] = created
                sessionList[sessionId] = workingMode
                currentSession.value = Pair(sessionId, workingMode)
                updateNotification()
            }

            return HeadlessSessionAccess(
                sessionId = sessionId,
                session = session,
                created = true
            )
        }

        fun getSession(id: String): TerminalSession? {
            return sessions[id]
        }
        fun terminateSession(id: String) {
            runCatching {
                //crash is here
                sessions[id]?.apply {
                    if (emulator != null){
                        sessions[id]?.finishIfRunning()
                    }
                }

                sessions.remove(id)
                sessionList.remove(id)
                if (sessions.isEmpty()) {
                    currentSession.value = Pair("main", com.rk.settings.Settings.working_Mode)
                    stopSelf()
                } else {
                    if (currentSession.value.first == id) {
                        sessionList.entries.firstOrNull()?.let { next ->
                            currentSession.value = Pair(next.key, next.value)
                        }
                    }
                    updateNotification()
                }
            }.onFailure { it.printStackTrace() }

        }
    }

    private val binder = SessionBinder()
    private val notificationManager by lazy {
        getSystemService(NotificationManager::class.java)
    }

    override fun onBind(intent: Intent?): IBinder {
        return binder
    }

    override fun onDestroy() {
        sessions.forEach { s -> s.value.finishIfRunning() }
        super.onDestroy()
    }

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            createNotificationChannel()
        }
        val notification = createNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(1, notification)
        }
    }


    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "ACTION_EXIT" -> {
                sessions.forEach { s -> s.value.finishIfRunning() }
                stopSelf()
                return START_NOT_STICKY
            }
        }
        return START_STICKY
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val exitIntent = Intent(this, SessionService::class.java).apply {
            action = "ACTION_EXIT"
        }
        val exitPendingIntent = PendingIntent.getService(
            this, 1, exitIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("ReTerminal")
            .setContentText(getNotificationContentText())
            .setSmallIcon(drawables.terminal)
            .setContentIntent(pendingIntent)
            .addAction(
                NotificationCompat.Action.Builder(
                    null,
                    "EXIT",
                    exitPendingIntent
                ).build()
            )
            .setOngoing(true)
            .build()
    }

    private val CHANNEL_ID = "session_service_channel"

    @RequiresApi(Build.VERSION_CODES.O)
    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Session Service",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Notification for Terminal Service"
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun updateNotification() {
        val notification = createNotification()
        notificationManager.notify(1, notification)
    }

    private fun getNotificationContentText(): String {
        val count = sessions.size
        if (count == 1){
            return "1 session running"
        }
        return "$count sessions running"
    }

    private fun resolveSessionId(requestedId: String?): String {
        val sanitizedRequestedId = sanitizeSessionId(requestedId)
        if (!sanitizedRequestedId.isNullOrEmpty()) {
            return sanitizedRequestedId
        }
        var candidate: String
        do {
            candidate = AGENT_SESSION_ID_PREFIX + java.util.UUID.randomUUID().toString().take(8)
        } while (sessions.containsKey(candidate))
        return candidate
    }

    private fun sanitizeSessionId(raw: String?): String? {
        val normalized = raw?.trim().orEmpty()
        if (normalized.isEmpty()) {
            return null
        }
        return normalized
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .trim('_')
            .take(48)
            .takeIf { it.isNotEmpty() }
    }
}
