package cn.com.omnimind.baselib.shizuku

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.RemoteException
import cn.com.omnimind.baselib.util.OmniLog
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import rikka.shizuku.Shizuku
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class ShizukuCapabilityManager private constructor(
    context: Context
) {

    private val appContext = context.applicationContext
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }
    private val bindMutex = Mutex()
    private val permissionMutex = Mutex()
    private val pendingResults = ConcurrentHashMap<String, CompletableDeferred<PrivilegedResult>>()
    private val replyMessenger = Messenger(
        Handler(Looper.getMainLooper()) { message ->
            if (message.what != PrivilegedServiceProtocol.MSG_RESULT) {
                return@Handler false
            }
            val resultJson = message.data?.getString(PrivilegedServiceProtocol.KEY_RESULT_JSON)
            val result = runCatching {
                json.decodeFromString(PrivilegedResult.serializer(), resultJson.orEmpty())
            }.getOrNull() ?: return@Handler true
            pendingResults.remove(result.requestId)?.complete(result)
            true
        }
    )

    @Volatile
    private var remoteMessenger: Messenger? = null

    @Volatile
    private var lastBinderDead = false

    @Volatile
    private var listenersRegistered = false

    private val userServiceArgs = Shizuku.UserServiceArgs(
        ComponentName(appContext, OmnibotPrivilegedUserService::class.java)
    )
        .daemon(false)
        .processNameSuffix("omnibot_privileged")
        .tag(USER_SERVICE_TAG)
        .version(USER_SERVICE_VERSION)

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            remoteMessenger = if (service != null) Messenger(service) else null
            OmniLog.i(TAG, "Shizuku user service connected")
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            remoteMessenger = null
            OmniLog.w(TAG, "Shizuku user service disconnected")
        }

        override fun onBindingDied(name: ComponentName?) {
            remoteMessenger = null
            OmniLog.w(TAG, "Shizuku user service binding died")
        }

        override fun onNullBinding(name: ComponentName?) {
            remoteMessenger = null
            OmniLog.w(TAG, "Shizuku user service null binding")
        }
    }

    init {
        registerListenersIfNeeded()
    }

    fun getStatus(): ShizukuStatus {
        registerListenersIfNeeded()
        val installed = isShizukuInstalled() || runCatching { Shizuku.pingBinder() }.getOrDefault(false)
        val binderReady = runCatching { Shizuku.pingBinder() }.getOrDefault(false)
        val running = binderReady
        val permissionGranted = if (binderReady) {
            runCatching { Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED }
                .getOrDefault(false)
        } else {
            false
        }
        val uid = if (binderReady) runCatching { Shizuku.getUid() }.getOrNull() else null
        val version = if (binderReady) runCatching { Shizuku.getVersion() }.getOrNull() else null
        val backend = when {
            !permissionGranted -> ShizukuBackend.NONE
            uid == 0 -> ShizukuBackend.ROOT
            uid == 2000 -> ShizukuBackend.ADB
            else -> ShizukuBackend.ADB
        }
        val code = when {
            !installed -> ShizukuStatusCode.NOT_INSTALLED
            !binderReady && lastBinderDead -> ShizukuStatusCode.BINDER_DEAD
            !binderReady -> ShizukuStatusCode.NOT_RUNNING
            !permissionGranted -> ShizukuStatusCode.PERMISSION_DENIED
            backend == ShizukuBackend.ROOT -> ShizukuStatusCode.GRANTED_ROOT
            else -> ShizukuStatusCode.GRANTED_ADB
        }
        return ShizukuStatus(
            code = code,
            backend = backend,
            installed = installed,
            running = running,
            permissionGranted = permissionGranted,
            binderReady = binderReady,
            serviceBound = remoteMessenger != null,
            uid = uid,
            version = version,
            availableActions = suggestedAgentActions(backend),
            message = statusMessage(code)
        )
    }

    fun suggestedAgentActions(backend: ShizukuBackend = getStatus().backend): List<String> {
        return PrivilegedActionPolicy.visibleAgentActions(
            if (backend == ShizukuBackend.ROOT) ShizukuBackend.ROOT else ShizukuBackend.ADB
        )
    }

    fun isGranted(): Boolean = getStatus().isGranted()

    fun isShizukuInstalled(): Boolean {
        return runCatching {
            appContext.packageManager.getPackageInfo(SHIZUKU_PACKAGE_NAME, 0)
            true
        }.getOrDefault(false)
    }

    fun openShizukuDownloadOrApp(): Boolean {
        return runCatching {
            val launchIntent = appContext.packageManager.getLaunchIntentForPackage(SHIZUKU_PACKAGE_NAME)
            val intent = launchIntent ?: Intent(
                Intent.ACTION_VIEW,
                android.net.Uri.parse("https://shizuku.rikka.app/download/")
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            appContext.startActivity(intent)
            true
        }.getOrElse {
            OmniLog.e(TAG, "Failed to open Shizuku app or website", it)
            false
        }
    }

    suspend fun requestPermission(): ShizukuStatus {
        registerListenersIfNeeded()
        return permissionMutex.withLock {
            val current = getStatus()
            if (!current.installed || !current.running) {
                return@withLock current
            }
            if (current.permissionGranted) {
                return@withLock current
            }
            val deferred = CompletableDeferred<Int>()
            val requestCode = (System.currentTimeMillis() % 100000).toInt()
            val listener = Shizuku.OnRequestPermissionResultListener { callbackCode, grantResult ->
                if (callbackCode == requestCode && !deferred.isCompleted) {
                    deferred.complete(grantResult)
                }
            }
            withContext(Dispatchers.Main) {
                Shizuku.addRequestPermissionResultListener(listener)
                Shizuku.requestPermission(requestCode)
            }
            withTimeoutOrNull(10_000) {
                deferred.await()
            }
            withContext(Dispatchers.Main) {
                Shizuku.removeRequestPermissionResultListener(listener)
            }
            getStatus()
        }
    }

    suspend fun runHealthCheck(): Map<String, Any?> {
        val status = getStatus()
        val payload = linkedMapOf<String, Any?>()
        payload.putAll(status.toMap())
        if (!status.isGranted()) {
            payload["probe"] = null
            return payload
        }
        val probe = execute(
            PrivilegedRequest(
                requestId = UUID.randomUUID().toString(),
                action = PrivilegedActionPolicy.ACTION_DIAGNOSTICS_GETPROP,
                arguments = mapOf("name" to "ro.build.version.release")
            )
        )
        payload["probe"] = probe.toMap()
        return payload
    }

    suspend fun executeAgentAction(
        action: String,
        arguments: Map<String, String>,
        requiresConfirmation: Boolean = false,
    ): PrivilegedResult {
        val request = PrivilegedRequest(
            requestId = UUID.randomUUID().toString(),
            action = PrivilegedActionPolicy.normalizeAction(action),
            arguments = arguments,
            requiresConfirmation = requiresConfirmation
        )
        return execute(request)
    }

    suspend fun pressKeyEvent(key: String): PrivilegedResult {
        return executeAgentAction(
            action = PrivilegedActionPolicy.ACTION_DEVICE_KEYEVENT,
            arguments = mapOf("key" to key)
        )
    }

    suspend fun inputText(text: String): PrivilegedResult {
        return executeAgentAction(
            action = PrivilegedActionPolicy.ACTION_DEVICE_INPUT_TEXT,
            arguments = mapOf("text" to text)
        )
    }

    suspend fun launchApp(packageName: String): PrivilegedResult {
        return executeAgentAction(
            action = PrivilegedActionPolicy.ACTION_PACKAGE_LAUNCH,
            arguments = mapOf("packageName" to packageName)
        )
    }

    private suspend fun execute(request: PrivilegedRequest): PrivilegedResult {
        val status = getStatus()
        if (!status.isGranted()) {
            return PrivilegedResult(
                requestId = request.requestId,
                action = request.action,
                success = false,
                code = status.code.name.lowercase(),
                message = status.message,
                backend = status.backend,
                availableActions = suggestedAgentActions(status.backend)
            )
        }
        val messenger = ensureUserServiceBound() ?: return PrivilegedResult(
            requestId = request.requestId,
            action = request.action,
            success = false,
            code = "service_bind_failed",
            message = "Failed to bind Shizuku user service.",
            backend = status.backend,
            availableActions = suggestedAgentActions(status.backend)
        )
        val deferred = CompletableDeferred<PrivilegedResult>()
        pendingResults[request.requestId] = deferred
        val sent = runCatching {
            val message = Message.obtain(null, PrivilegedServiceProtocol.MSG_EXECUTE)
            message.replyTo = replyMessenger
            message.data = Bundle().apply {
                putString(
                    PrivilegedServiceProtocol.KEY_REQUEST_JSON,
                    json.encodeToString(PrivilegedRequest.serializer(), request)
                )
            }
            messenger.send(message)
        }.isSuccess
        if (!sent) {
            pendingResults.remove(request.requestId)
            remoteMessenger = null
            return PrivilegedResult(
                requestId = request.requestId,
                action = request.action,
                success = false,
                code = "service_send_failed",
                message = "Failed to send privileged request.",
                backend = status.backend,
                availableActions = suggestedAgentActions(status.backend)
            )
        }
        return withTimeoutOrNull(12_000) {
            deferred.await()
        } ?: run {
            pendingResults.remove(request.requestId)
            PrivilegedResult(
                requestId = request.requestId,
                action = request.action,
                success = false,
                code = "service_timeout",
                message = "Timed out waiting for privileged service result.",
                backend = status.backend,
                availableActions = suggestedAgentActions(status.backend)
            )
        }
    }

    private suspend fun ensureUserServiceBound(): Messenger? {
        remoteMessenger?.let { return it }
        return bindMutex.withLock {
            remoteMessenger?.let { return@withLock it }
            if (!getStatus().isGranted()) {
                return@withLock null
            }
            val connected = CompletableDeferred<Messenger?>()
            withContext(Dispatchers.Main) {
                try {
                    Shizuku.bindUserService(userServiceArgs, serviceConnection)
                } catch (error: Throwable) {
                    connected.complete(null)
                    return@withContext
                }
                if (remoteMessenger != null && !connected.isCompleted) {
                    connected.complete(remoteMessenger)
                } else {
                    Handler(Looper.getMainLooper()).postDelayed({
                        if (!connected.isCompleted) {
                            connected.complete(remoteMessenger)
                        }
                    }, 800)
                }
            }
            withTimeoutOrNull(2_000) {
                connected.await()
            }
        }
    }

    private fun registerListenersIfNeeded() {
        if (listenersRegistered) {
            return
        }
        synchronized(this) {
            if (listenersRegistered) {
                return
            }
            runCatching {
                Shizuku.addBinderReceivedListenerSticky {
                    lastBinderDead = false
                }
                Shizuku.addBinderDeadListener {
                    lastBinderDead = true
                    remoteMessenger = null
                }
            }
            listenersRegistered = true
        }
    }

    private fun statusMessage(code: ShizukuStatusCode): String {
        return when (code) {
            ShizukuStatusCode.NOT_INSTALLED -> "Shizuku is not installed."
            ShizukuStatusCode.NOT_RUNNING -> "Shizuku is installed but not running."
            ShizukuStatusCode.PERMISSION_DENIED -> "Shizuku permission is not granted."
            ShizukuStatusCode.GRANTED_ADB -> "Shizuku is granted through adb."
            ShizukuStatusCode.GRANTED_ROOT -> "Shizuku is granted through root/Sui."
            ShizukuStatusCode.BINDER_DEAD -> "Shizuku binder died. Please restart Shizuku."
        }
    }

    companion object {
        private const val TAG = "ShizukuCapabilityMgr"
        private const val SHIZUKU_PACKAGE_NAME = "moe.shizuku.privileged.api"
        private const val USER_SERVICE_TAG = "omnibot-privileged-agent"
        private const val USER_SERVICE_VERSION = 1

        @Volatile
        private var instance: ShizukuCapabilityManager? = null

        fun get(context: Context): ShizukuCapabilityManager {
            return instance ?: synchronized(this) {
                instance ?: ShizukuCapabilityManager(context).also {
                    instance = it
                }
            }
        }
    }
}
