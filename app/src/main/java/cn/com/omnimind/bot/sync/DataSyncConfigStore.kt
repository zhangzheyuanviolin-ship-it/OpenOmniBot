package cn.com.omnimind.bot.sync

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import cn.com.omnimind.baselib.service.DeviceInfoService
import java.util.UUID

class DataSyncConfigStore(
    private val context: Context
) {
    companion object {
        private const val PREFS_NAME = "data_sync_secure_config"
        private const val KEY_CONFIG_JSON = "config_json"
        private const val KEY_DEVICE_ID = "device_id"
    }

    private val prefs by lazy {
        val masterKey = MasterKey.Builder(context.applicationContext)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context.applicationContext,
            PREFS_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    fun getOrCreateDeviceId(): String {
        val cached = prefs.getString(KEY_DEVICE_ID, null)?.trim().orEmpty()
        if (cached.isNotEmpty()) return cached
        val raw = DeviceInfoService.getAndroidId(context)?.trim().orEmpty()
        val generated = if (raw.isNotEmpty()) {
            "android-${DataSyncCrypto.sha256Hex(raw).take(16)}"
        } else {
            "device-${UUID.randomUUID()}"
        }
        prefs.edit().putString(KEY_DEVICE_ID, generated).apply()
        return generated
    }

    fun getConfig(): DataSyncConfig {
        val saved = prefs.getString(KEY_CONFIG_JSON, null).orEmpty()
        if (saved.isBlank()) {
            return DataSyncConfig(deviceId = getOrCreateDeviceId())
        }
        return runCatching {
            dataSyncGson.fromJson(saved, dataSyncMapType) as Map<String, Any?>
        }.map { DataSyncConfig.fromMap(it) }
            .getOrDefault(DataSyncConfig())
            .let { config ->
                config.copy(deviceId = config.deviceId.ifBlank { getOrCreateDeviceId() }).sanitized()
            }
    }

    fun saveConfig(config: DataSyncConfig): DataSyncConfig {
        val sanitized = config.copy(
            deviceId = config.deviceId.ifBlank { getOrCreateDeviceId() }
        ).sanitized()
        prefs.edit()
            .putString(KEY_CONFIG_JSON, dataSyncGson.toJson(sanitized.toMap(includeSecrets = true)))
            .apply()
        return sanitized
    }

    fun updateEnabled(enabled: Boolean): DataSyncConfig {
        val updated = getConfig().copy(enabled = enabled, updatedAt = System.currentTimeMillis())
        return saveConfig(updated)
    }
}
