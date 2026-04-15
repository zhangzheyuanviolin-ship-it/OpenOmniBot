package cn.com.omnimind.bot.ui.channel

import android.annotation.SuppressLint
import android.content.Context
import cn.com.omnimind.bot.manager.AsrServiceIatSpeechRecognitionManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class SpeechRecognitionChannel {
    @SuppressLint("StaticFieldLeak")
    private var asrServiceManager: AsrServiceIatSpeechRecognitionManager? = null

    private val methodChannelName = "cn.com.omnimind.bot/SpeechRecognition"
    private val eventChannelName = "cn.com.omnimind.bot/SpeechRecognitionEvents"
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null

    fun onCreate(context: Context) {
        asrServiceManager = AsrServiceIatSpeechRecognitionManager(context)
    }

    fun setChannel(flutterEngine: FlutterEngine) {
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
        methodChannel?.setMethodCallHandler { call, result ->
            val manager = asrServiceManager
            when (call.method) {
                "initialize" -> manager?.initialize(result)
                    ?: result.error("NO_MANAGER", "SpeechRecognitionManager is null", null)

                "startRecording" -> manager?.start(result)
                    ?: result.error("NO_MANAGER", "SpeechRecognitionManager is null", null)

                "stopRecording" -> manager?.stop(result)
                    ?: result.error("NO_MANAGER", "SpeechRecognitionManager is null", null)

                "stopSendingOnly" -> manager?.stopSendingOnly(result)
                    ?: result.error("NO_MANAGER", "SpeechRecognitionManager is null", null)

                "release" -> {
                    asrServiceManager?.release()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
        eventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                asrServiceManager?.setEventSink(events)
            }

            override fun onCancel(arguments: Any?) {
                asrServiceManager?.setEventSink(null)
            }
        })
    }

    fun clear() {
        asrServiceManager?.release()
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
    }
}
