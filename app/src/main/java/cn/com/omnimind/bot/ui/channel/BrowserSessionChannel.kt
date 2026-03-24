package cn.com.omnimind.bot.ui.channel

import cn.com.omnimind.bot.agent.LiveAgentBrowserSessionManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class BrowserSessionChannel {
    companion object {
        private const val CHANNEL = "cn.com.omnimind.bot/AgentBrowserSession"
    }

    private var methodChannel: MethodChannel? = null

    fun setChannel(flutterEngine: FlutterEngine) {
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler(::handleMethodCall)
    }

    private fun handleMethodCall(
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        when (call.method) {
            "getLiveBrowserSessionSnapshot" -> {
                result.success(LiveAgentBrowserSessionManager.currentSnapshot())
            }

            else -> result.notImplemented()
        }
    }

    fun clear() {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
    }
}
