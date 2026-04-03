package cn.com.omnimind.bot.manager

import android.app.Activity
import android.os.Handler
import android.os.Looper
import com.alibaba.mnnllm.android.asr.AsrService
import cn.com.omnimind.bot.mnnlocal.MnnLocalConfigStore
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class MnnLocalSpeechRecognitionManager(
    private val activity: Activity,
) : SpeechRecognitionManager {

    companion object {
        private const val NOT_READY_CODE = "MNN_ASR_NOT_READY"
        private const val NOT_READY_MESSAGE = "MNN 本地 ASR 尚未配置，请先在本地模型页选择默认 ASR 模型。"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val handler = Handler(Looper.getMainLooper())
    private val initMutex = Mutex()

    private var eventSink: EventChannel.EventSink? = null
    private var asrService: AsrService? = null
    private var initialized = false
    private var initializing = false

    override val isAvailable: Boolean
        get() = MnnLocalConfigStore.getDefaultAsrModelId() != null

    override fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    override fun initialize(result: MethodChannel.Result) {
        if (!isAvailable) {
            result.error(NOT_READY_CODE, NOT_READY_MESSAGE, null)
            return
        }
        scope.launch {
            runCatching {
                ensureInitialized()
                true
            }.onSuccess {
                result.success(true)
            }.onFailure { error ->
                result.error(
                    NOT_READY_CODE,
                    error.message ?: "MNN 本地 ASR 初始化失败",
                    null
                )
            }
        }
    }

    override fun start(result: MethodChannel.Result): Boolean {
        if (!isAvailable) {
            result.error(NOT_READY_CODE, NOT_READY_MESSAGE, null)
            return false
        }
        scope.launch {
            runCatching {
                ensureInitialized()
                asrService?.startRecord()
                true
            }.onSuccess {
                result.success(true)
            }.onFailure { error ->
                result.error(
                    NOT_READY_CODE,
                    error.message ?: "MNN 本地 ASR 启动失败",
                    null
                )
            }
        }
        return true
    }

    override fun stop(result: MethodChannel.Result) {
        asrService?.stopRecord()
        result.success(null)
    }

    override fun stopSendingOnly(result: MethodChannel.Result) {
        asrService?.stopRecord()
        result.success(null)
    }

    override fun release() {
        asrService?.stopRecord()
        asrService = null
        initialized = false
        initializing = false
        eventSink = null
    }

    private suspend fun ensureInitialized() {
        if (initialized) {
            return
        }
        initMutex.withLock {
            if (initialized || initializing) {
                return
            }
            initializing = true
            try {
                val service = AsrService(activity)
                service.onRecognizeText = { text ->
                    handler.post {
                        eventSink?.success(text)
                    }
                }
                service.initRecognizer()
                asrService = service
                initialized = true
            } finally {
                initializing = false
            }
        }
    }
}
