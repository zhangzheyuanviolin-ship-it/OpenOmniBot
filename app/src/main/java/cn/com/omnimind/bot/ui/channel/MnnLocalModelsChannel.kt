package cn.com.omnimind.bot.ui.channel

import android.content.Context
import android.os.Handler
import android.os.Looper
import cn.com.omnimind.bot.mnnlocal.MnnLocalModelsManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MnnLocalModelsChannel {
    companion object {
        private const val METHOD_CHANNEL = "cn.com.omnimind.bot/MnnLocalModels"
        private const val EVENT_CHANNEL = "cn.com.omnimind.bot/MnnLocalModelsEvents"
        private const val ERROR_CODE = "MNN_LOCAL_ERROR"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var appContext: Context? = null
    private var eventSink: EventChannel.EventSink? = null

    fun onCreate(context: Context) {
        appContext = context.applicationContext
        MnnLocalModelsManager.setContext(context)
    }

    fun setChannel(flutterEngine: FlutterEngine) {
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        )
        methodChannel?.setMethodCallHandler(::handleMethodCall)

        eventChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL
        )
        eventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                MnnLocalModelsManager.setEventDispatcher { payload ->
                    mainHandler.post {
                        eventSink?.success(payload)
                    }
                }
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
                MnnLocalModelsManager.setEventDispatcher(null)
            }
        })
    }

    fun clear() {
        MnnLocalModelsManager.setEventDispatcher(null)
        eventSink = null
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        MnnLocalModelsManager.clear()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getOverview" -> runSuspend(result) {
                MnnLocalModelsManager.getOverview(
                    installedQuery = call.argument<String>("installedQuery"),
                    marketQuery = call.argument<String>("marketQuery"),
                    marketCategory = call.argument<String>("marketCategory"),
                )
            }

            "listInstalledModels" -> runSuspend(result) {
                MnnLocalModelsManager.listInstalledModels(
                    query = call.argument<String>("query"),
                    category = call.argument<String>("category"),
                )
            }

            "refreshInstalledModels" -> runSuspend(result) {
                MnnLocalModelsManager.refreshInstalledModels()
            }

            "listMarketModels" -> runSuspend(result) {
                MnnLocalModelsManager.listMarketModels(
                    query = call.argument<String>("query"),
                    category = call.argument<String>("category"),
                    refresh = call.argument<Boolean>("refresh") == true,
                )
            }

            "refreshMarketModels" -> runSuspend(result) {
                MnnLocalModelsManager.refreshMarketModels(
                    query = call.argument<String>("query"),
                    category = call.argument<String>("category"),
                )
            }

            "getConfig" -> {
                result.success(MnnLocalModelsManager.getConfig())
            }

            "saveConfig" -> {
                val args = (call.arguments as? Map<*, *>) ?: emptyMap<String, Any?>()
                result.success(MnnLocalModelsManager.saveConfig(args))
            }

            "setActiveModel" -> {
                result.success(
                    MnnLocalModelsManager.setActiveModel(
                        call.argument<String>("modelId")
                    )
                )
            }

            "startApiService" -> {
                result.success(
                    MnnLocalModelsManager.startApiService(
                        call.argument<String>("modelId")
                    )
                )
            }

            "stopApiService" -> {
                result.success(MnnLocalModelsManager.stopApiService())
            }

            "startDownload" -> {
                val modelId = call.argument<String>("modelId")
                if (modelId.isNullOrBlank()) {
                    result.error(ERROR_CODE, "modelId is required", null)
                } else {
                    MnnLocalModelsManager.startDownload(modelId)
                    result.success(true)
                }
            }

            "pauseDownload" -> {
                val modelId = call.argument<String>("modelId")
                if (modelId.isNullOrBlank()) {
                    result.error(ERROR_CODE, "modelId is required", null)
                } else {
                    MnnLocalModelsManager.pauseDownload(modelId)
                    result.success(true)
                }
            }

            "deleteModel" -> runSuspend(result) {
                val modelId = call.argument<String>("modelId")
                    ?: error("modelId is required")
                MnnLocalModelsManager.deleteModel(modelId)
            }

            "startGeneration" -> runSuspend(result) {
                val args = (call.arguments as? Map<*, *>) ?: emptyMap<String, Any?>()
                MnnLocalModelsManager.startGeneration(args)
            }

            "stopGeneration" -> {
                result.success(MnnLocalModelsManager.stopGeneration())
            }

            "resetInferenceSession" -> {
                MnnLocalModelsManager.resetInferenceSession()
                result.success(true)
            }

            "getBenchmarkState" -> {
                result.success(MnnLocalModelsManager.getBenchmarkState())
            }

            "startBenchmark" -> runSuspend(result) {
                val args = (call.arguments as? Map<*, *>) ?: emptyMap<String, Any?>()
                MnnLocalModelsManager.startBenchmark(args)
            }

            "stopBenchmark" -> {
                result.success(MnnLocalModelsManager.stopBenchmark())
            }

            else -> result.notImplemented()
        }
    }

    private fun runSuspend(
        result: MethodChannel.Result,
        block: suspend () -> Any?
    ) {
        scope.launch {
            runCatching { block() }
                .onSuccess { value -> result.success(value) }
                .onFailure { error ->
                    result.error(ERROR_CODE, error.message ?: "unknown_error", null)
                }
        }
    }
}
