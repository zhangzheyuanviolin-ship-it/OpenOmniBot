package cn.com.omnimind.bot.ui.channel

import android.content.Context
import cn.com.omnimind.bot.sync.DataSyncConfig
import cn.com.omnimind.bot.sync.DataSyncManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class DataSyncChannel {
    private val channelName = "cn.com.omnimind.bot/DataSync"
    private val scope = CoroutineScope(Dispatchers.IO)
    private var context: Context? = null
    private var channel: MethodChannel? = null

    fun onCreate(context: Context) {
        this.context = context.applicationContext
    }

    fun setChannel(flutterEngine: FlutterEngine) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            val safeContext = context
            if (safeContext == null) {
                result.error("CONTEXT_ERROR", "Context not initialized", null)
                return@setMethodCallHandler
            }
            val manager = DataSyncManager.get(safeContext)
            scope.launch {
                runCatching {
                    when (call.method) {
                        "getConfig" -> manager.getConfig().toMap(includeSecrets = true)
                        "saveConfig" -> {
                            val raw = call.arguments<Map<String, Any?>>() ?: emptyMap()
                            manager.saveConfig(DataSyncConfig.fromMap(raw)).toMap(includeSecrets = true)
                        }
                        "testConnection" -> {
                            val raw = call.arguments<Map<String, Any?>>() ?: emptyMap()
                            val candidate = if (raw.isEmpty()) null else DataSyncConfig.fromMap(raw)
                            manager.testConnection(candidate)
                        }
                        "setEnabled" -> {
                            val enabled = call.argument<Boolean>("enabled") == true
                            manager.setEnabled(enabled).toMap()
                        }
                        "syncNow" -> manager.requestSyncNow().toMap()
                        "getStatus" -> manager.getStatus().toMap()
                        "exportPairingPayload" -> {
                            val passphrase = call.argument<String>("passphrase").orEmpty()
                            manager.exportPairingPayload(passphrase).toMap()
                        }
                        "importPairingPayload" -> {
                            val encodedPayload = call.argument<String>("encodedPayload").orEmpty()
                            val passphrase = call.argument<String>("passphrase").orEmpty()
                            manager.importPairingPayload(encodedPayload, passphrase).toMap()
                        }
                        "listConflicts" -> manager.listConflicts().map { it.toMap() }
                        "ackConflict" -> {
                            val id = call.argument<Number>("id")?.toLong() ?: 0L
                            mapOf("success" to manager.ackConflict(id))
                        }
                        "reindexLocalSnapshot" -> manager.reindexLocalSnapshot().toMap()
                        else -> null
                    }
                }.onSuccess { payload ->
                    withContext(Dispatchers.Main) {
                        if (payload == null) {
                            result.notImplemented()
                        } else {
                            result.success(payload)
                        }
                    }
                }.onFailure { error ->
                    withContext(Dispatchers.Main) {
                        result.error("DATA_SYNC_ERROR", error.message, null)
                    }
                }
            }
        }
    }

    fun clear() {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
