package cn.com.omnimind.bot.ui.channel

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import cn.com.omnimind.bot.manager.AsrServiceIatSpeechRecognitionManager
import cn.com.omnimind.bot.manager.MnnLocalSpeechRecognitionManager
import cn.com.omnimind.bot.manager.SpeechRecognitionManager
import cn.com.omnimind.bot.mnnlocal.MnnLocalConfigStore
import cn.com.omnimind.bot.mnnlocal.SpeechRecognitionProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class SpeechRecognitionChannel {
    @SuppressLint("StaticFieldLeak")
    private var asrServiceManager: AsrServiceIatSpeechRecognitionManager? = null
    @SuppressLint("StaticFieldLeak")
    private var mnnLocalSpeechRecognitionManager: MnnLocalSpeechRecognitionManager? = null

    private fun activeManager(): SpeechRecognitionManager? {
        return when (MnnLocalConfigStore.getSpeechRecognitionProvider()) {
            SpeechRecognitionProvider.MNN_LOCAL -> mnnLocalSpeechRecognitionManager
            SpeechRecognitionProvider.DISABLED -> null
            SpeechRecognitionProvider.SYSTEM -> asrServiceManager
        }
    }

    private val TAG = "[SpeechRecognitionChannel]"
    private val METHOD_CHANNEL = "cn.com.omnimind.bot/SpeechRecognition"
    private val EVENT_CHANNEL = "cn.com.omnimind.bot/SpeechRecognitionEvents"
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null

    fun onCreate(context: Context) {
        // 仅走 asr-service
        asrServiceManager = AsrServiceIatSpeechRecognitionManager(context)
        mnnLocalSpeechRecognitionManager = (context as? Activity)?.let {
            MnnLocalSpeechRecognitionManager(it)
        }
    }

    fun setChannel(flutterEngine: FlutterEngine) {
        // Method Channel for controlling speech recognition
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            val manager = activeManager()
            when (call.method) {
                "initialize" -> manager?.initialize(result) ?: result.error("NO_MANAGER", "SpeechRecognitionManager is null", null)
                "startRecording" -> manager?.start(result) ?: result.error("NO_MANAGER", "SpeechRecognitionManager is null", null)
                "stopRecording" -> manager?.stop(result) ?: result.error("NO_MANAGER", "SpeechRecognitionManager is null", null)
                "stopSendingOnly" -> manager?.stopSendingOnly(result)
                    ?: result.error("NO_MANAGER", "SpeechRecognitionManager is null", null)
                "release" -> {
                    asrServiceManager?.release()
                    mnnLocalSpeechRecognitionManager?.release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Event Channel for streaming speech recognition results
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
        eventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                val manager = activeManager()
                // 只给当前生效的 manager 绑定 sink，避免重复回调
                asrServiceManager?.setEventSink(if (manager === asrServiceManager) events else null)
                mnnLocalSpeechRecognitionManager?.setEventSink(
                    if (manager === mnnLocalSpeechRecognitionManager) events else null
                )
            }

            override fun onCancel(arguments: Any?) {
                asrServiceManager?.setEventSink(null)
                mnnLocalSpeechRecognitionManager?.setEventSink(null)
            }
        })
    }

    fun clear() {
        asrServiceManager?.release()
        mnnLocalSpeechRecognitionManager?.release()
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
    }
}
