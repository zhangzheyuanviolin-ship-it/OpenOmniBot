package cn.com.omnimind.baselib.shizuku

import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json

class OmnibotPrivilegedUserService : Service() {

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val incomingHandler = Handler(Looper.getMainLooper()) { message ->
        when (message.what) {
            PrivilegedServiceProtocol.MSG_EXECUTE -> {
                val requestJson = message.data?.getString(PrivilegedServiceProtocol.KEY_REQUEST_JSON)
                val replyTo = message.replyTo
                scope.launch {
                    val result = runCatching {
                        val request = json.decodeFromString(PrivilegedRequest.serializer(), requestJson.orEmpty())
                        PrivilegedCommandExecutor.execute(request)
                    }.getOrElse { error ->
                        PrivilegedResult(
                            requestId = "",
                            action = "",
                            success = false,
                            code = "service_error",
                            message = error.message ?: "Privileged service failed.",
                            backend = PrivilegedCommandExecutor.currentBackend()
                        )
                    }
                    sendReply(replyTo, result)
                }
                true
            }
            else -> false
        }
    }
    private val messenger = Messenger(incomingHandler)

    override fun onBind(intent: Intent?): IBinder {
        Log.d(TAG, "Privileged user service bound")
        return messenger.binder
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun sendReply(replyTo: Messenger?, result: PrivilegedResult) {
        if (replyTo == null) {
            return
        }
        runCatching {
            val reply = Message.obtain(null, PrivilegedServiceProtocol.MSG_RESULT)
            reply.data = Bundle().apply {
                putString(
                    PrivilegedServiceProtocol.KEY_RESULT_JSON,
                    json.encodeToString(PrivilegedResult.serializer(), result)
                )
            }
            replyTo.send(reply)
        }.onFailure {
            Log.w(TAG, "Failed to deliver privileged result", it)
        }
    }

    private companion object {
        private const val TAG = "OmniPrivilegedSvc"
    }
}
