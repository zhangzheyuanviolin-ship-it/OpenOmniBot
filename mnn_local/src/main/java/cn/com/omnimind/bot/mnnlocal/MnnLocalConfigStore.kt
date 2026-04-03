package cn.com.omnimind.bot.mnnlocal

import cn.com.omnimind.baselib.llm.MnnLocalProviderStateStore
import com.alibaba.mls.api.source.ModelSources
import com.tencent.mmkv.MMKV
import java.util.UUID

enum class SpeechRecognitionProvider(val storageValue: String) {
    SYSTEM("system"),
    MNN_LOCAL("mnn_local"),
    DISABLED("disabled");

    companion object {
        fun fromStorageValue(raw: String?): SpeechRecognitionProvider {
            return entries.firstOrNull { it.storageValue == raw?.trim() } ?: SYSTEM
        }
    }
}

object MnnLocalConfigStore {
    private const val KEY_AUTOSTART_ON_APP_OPEN = "mnn_local_autostart_on_app_open"
    private const val KEY_API_ENABLED = "mnn_local_api_enabled"
    private const val KEY_API_LAN_ENABLED = "mnn_local_api_lan_enabled"
    private const val KEY_ACTIVE_MODEL_ID = "mnn_local_active_model_id"
    private const val KEY_API_PORT = "mnn_local_api_port"
    private const val KEY_API_KEY = "mnn_local_api_key"
    private const val KEY_SPEECH_PROVIDER = "speech_recognition_provider"
    private const val KEY_DEFAULT_ASR_MODEL = "mnn_local_default_asr_model"
    private const val KEY_DEFAULT_TTS_MODEL = "mnn_local_default_tts_model"
    private const val KEY_DOWNLOAD_PROVIDER = "mnn_local_download_provider"

    private const val DEFAULT_PORT = 8080

    private fun mmkv(): MMKV? = MMKV.defaultMMKV()

    fun shouldAutoStartOnAppOpen(): Boolean {
        return mmkv()?.decodeBool(KEY_AUTOSTART_ON_APP_OPEN, false) ?: false
    }

    fun setAutoStartOnAppOpen(enabled: Boolean) {
        mmkv()?.encode(KEY_AUTOSTART_ON_APP_OPEN, enabled)
    }

    fun isApiEnabled(): Boolean {
        return mmkv()?.decodeBool(KEY_API_ENABLED, false) ?: false
    }

    fun setApiEnabled(enabled: Boolean) {
        mmkv()?.encode(KEY_API_ENABLED, enabled)
        syncProviderState(ready = false)
    }

    fun isLanEnabled(): Boolean {
        return mmkv()?.decodeBool(KEY_API_LAN_ENABLED, false) ?: false
    }

    fun setLanEnabled(enabled: Boolean) {
        mmkv()?.encode(KEY_API_LAN_ENABLED, enabled)
    }

    fun getActiveModelId(): String? {
        return mmkv()?.decodeString(KEY_ACTIVE_MODEL_ID)?.trim()?.takeIf { it.isNotEmpty() }
    }

    fun setActiveModelId(modelId: String?) {
        if (modelId.isNullOrBlank()) {
            mmkv()?.removeValueForKey(KEY_ACTIVE_MODEL_ID)
        } else {
            mmkv()?.encode(KEY_ACTIVE_MODEL_ID, modelId.trim())
        }
    }

    fun getPort(): Int {
        return mmkv()?.decodeInt(KEY_API_PORT, DEFAULT_PORT)?.takeIf { it > 0 } ?: DEFAULT_PORT
    }

    fun setPort(port: Int) {
        mmkv()?.encode(KEY_API_PORT, port)
        syncProviderState(ready = false)
    }

    fun getApiKey(): String {
        val cached = mmkv()?.decodeString(KEY_API_KEY)?.trim().orEmpty()
        if (cached.isNotEmpty()) {
            return cached
        }
        val generated = UUID.randomUUID().toString().replace("-", "")
        mmkv()?.encode(KEY_API_KEY, generated)
        syncProviderState(ready = false)
        return generated
    }

    fun setApiKey(apiKey: String) {
        mmkv()?.encode(KEY_API_KEY, apiKey.trim())
        syncProviderState(ready = false)
    }

    fun getSpeechRecognitionProvider(): SpeechRecognitionProvider {
        return SpeechRecognitionProvider.fromStorageValue(
            mmkv()?.decodeString(KEY_SPEECH_PROVIDER)
        )
    }

    fun setSpeechRecognitionProvider(provider: SpeechRecognitionProvider) {
        mmkv()?.encode(KEY_SPEECH_PROVIDER, provider.storageValue)
    }

    fun getDefaultAsrModelId(): String? {
        return mmkv()?.decodeString(KEY_DEFAULT_ASR_MODEL)?.trim()?.takeIf { it.isNotEmpty() }
    }

    fun setDefaultAsrModelId(modelId: String?) {
        if (modelId.isNullOrBlank()) {
            mmkv()?.removeValueForKey(KEY_DEFAULT_ASR_MODEL)
        } else {
            mmkv()?.encode(KEY_DEFAULT_ASR_MODEL, modelId.trim())
        }
    }

    fun getDefaultTtsModelId(): String? {
        return mmkv()?.decodeString(KEY_DEFAULT_TTS_MODEL)?.trim()?.takeIf { it.isNotEmpty() }
    }

    fun setDefaultTtsModelId(modelId: String?) {
        if (modelId.isNullOrBlank()) {
            mmkv()?.removeValueForKey(KEY_DEFAULT_TTS_MODEL)
        } else {
            mmkv()?.encode(KEY_DEFAULT_TTS_MODEL, modelId.trim())
        }
    }

    fun getDownloadProviderString(): String {
        return mmkv()?.decodeString(KEY_DOWNLOAD_PROVIDER)?.trim()?.takeIf { it.isNotEmpty() }
            ?: ModelSources.sourceModelers
    }

    fun setDownloadProviderString(source: String) {
        mmkv()?.encode(KEY_DOWNLOAD_PROVIDER, source)
    }

    fun getBindHost(): String {
        return if (isLanEnabled()) "0.0.0.0" else "127.0.0.1"
    }

    fun getLoopbackBaseUrl(): String {
        return "http://127.0.0.1:${getPort()}"
    }

    fun syncProviderState(ready: Boolean) {
        MnnLocalProviderStateStore.update(
            port = getPort(),
            apiKey = getApiKey(),
            ready = ready
        )
    }
}
