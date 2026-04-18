package cn.com.omnimind.bot.sync

import android.content.Context
import cn.com.omnimind.bot.agent.WorkspaceMemoryService
import cn.com.omnimind.bot.mcp.RemoteMcpConfigStore
import cn.com.omnimind.bot.mcp.RemoteMcpServerConfig
import com.tencent.mmkv.MMKV

class DataSyncSettingsSnapshot(
    private val context: Context
) {
    companion object {
        private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_THEME = "flutter.theme_option"
        private const val KEY_LANGUAGE = "flutter.language_option"
        private const val KEY_AUTO_BACK = "flutter.auto_back_to_chat_after_task"
        private const val KEY_AVATAR = "flutter.avatarIndex"
        private const val KEY_NICKNAME = "flutter.nickname"
        private const val KEY_VIBRATE = "app_vibrate"
    }

    private val flutterPrefs by lazy {
        context.applicationContext.getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
    }

    private val mmkv: MMKV?
        get() = MMKV.defaultMMKV()

    fun capture(): Map<String, Any?> {
        val memoryService = WorkspaceMemoryService(context.applicationContext)
        val embedding = memoryService.getEmbeddingConfigForUi()
        val rollup = memoryService.getRollupStatusForUi()
        val remoteMcp = RemoteMcpConfigStore.listServers()
            .sortedBy { it.id }
            .map(::sanitizeRemoteMcpConfig)
        return linkedMapOf(
            "themeOption" to flutterPrefs.getString(KEY_THEME, "system").orEmpty(),
            "languageOption" to flutterPrefs.getString(KEY_LANGUAGE, "system").orEmpty(),
            "autoBackToChatAfterTask" to flutterPrefs.getBoolean(KEY_AUTO_BACK, true),
            "avatarIndex" to flutterPrefs.getInt(KEY_AVATAR, 0),
            "nickname" to flutterPrefs.getString(KEY_NICKNAME, "").orEmpty(),
            "vibrationEnabled" to (mmkv?.decodeBool(KEY_VIBRATE, true) ?: true),
            "workspaceMemoryEmbeddingEnabled" to embedding.enabled,
            "workspaceMemoryRollupEnabled" to rollup.enabled,
            "remoteMcpServers" to remoteMcp
        )
    }

    fun captureHash(snapshot: Map<String, Any?> = capture()): String {
        return DataSyncCrypto.sha256Hex(dataSyncGson.toJson(snapshot))
    }

    fun apply(snapshot: Map<String, Any?>) {
        flutterPrefs.edit()
            .putString(KEY_THEME, snapshot["themeOption"]?.toString() ?: "system")
            .putString(KEY_LANGUAGE, snapshot["languageOption"]?.toString() ?: "system")
            .putBoolean(KEY_AUTO_BACK, snapshot["autoBackToChatAfterTask"] == true)
            .putInt(KEY_AVATAR, snapshot["avatarIndex"].toIntValue())
            .putString(KEY_NICKNAME, snapshot["nickname"]?.toString().orEmpty())
            .apply()
        mmkv?.encode(KEY_VIBRATE, snapshot["vibrationEnabled"] != false)

        val memoryService = WorkspaceMemoryService(context.applicationContext)
        val currentEmbedding = memoryService.getEmbeddingConfigForUi()
        memoryService.saveEmbeddingConfigForUi(
            enabled = snapshot["workspaceMemoryEmbeddingEnabled"] != false,
            providerProfileId = currentEmbedding.providerProfileId,
            modelId = currentEmbedding.modelId
        )
        memoryService.saveRollupEnabled(snapshot["workspaceMemoryRollupEnabled"] != false)

        val remoteMcpServers = (snapshot["remoteMcpServers"] as? List<*>)?.mapNotNull { item ->
            (item as? Map<*, *>)?.let { raw ->
                @Suppress("UNCHECKED_CAST")
                RemoteMcpServerConfig.fromMap(raw as Map<String, Any?>)
            }
        }.orEmpty()
        applyRemoteMcpServers(remoteMcpServers)
    }

    private fun applyRemoteMcpServers(targetServers: List<RemoteMcpServerConfig>) {
        val currentServers = RemoteMcpConfigStore.listServers()
        currentServers
            .filter { current -> targetServers.none { it.id == current.id } }
            .forEach { RemoteMcpConfigStore.deleteServer(it.id) }
        targetServers.forEach { RemoteMcpConfigStore.upsertServer(it) }
    }

    private fun sanitizeRemoteMcpConfig(config: RemoteMcpServerConfig): Map<String, Any?> {
        return linkedMapOf(
            "id" to config.id,
            "name" to config.name,
            "endpointUrl" to config.endpointUrl,
            "bearerToken" to config.bearerToken,
            "enabled" to config.enabled
        )
    }
}
