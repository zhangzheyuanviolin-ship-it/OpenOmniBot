package cn.com.omnimind.bot.sync

import android.content.Context

class DataSyncStatusStore(
    context: Context
) {
    companion object {
        private const val PREFS_NAME = "data_sync_status_store"
        private const val KEY_STATUS_JSON = "status_json"
    }

    private val prefs =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun read(): DataSyncStatus {
        val raw = prefs.getString(KEY_STATUS_JSON, null).orEmpty()
        if (raw.isBlank()) {
            return DataSyncStatus()
        }
        return runCatching {
            @Suppress("UNCHECKED_CAST")
            val map = dataSyncGson.fromJson(raw, dataSyncMapType) as Map<String, Any?>
            DataSyncStatus.fromMap(map)
        }.getOrDefault(DataSyncStatus())
    }

    fun write(status: DataSyncStatus) {
        prefs.edit().putString(KEY_STATUS_JSON, dataSyncGson.toJson(status.toMap())).apply()
    }
}
