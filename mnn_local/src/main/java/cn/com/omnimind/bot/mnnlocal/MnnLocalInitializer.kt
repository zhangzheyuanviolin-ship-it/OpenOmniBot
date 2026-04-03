package cn.com.omnimind.bot.mnnlocal

import android.app.Application
import com.alibaba.mnnllm.android.MnnLlmApplication

object MnnLocalInitializer {
    @Volatile
    private var initialized = false

    fun initialize(application: Application) {
        if (initialized) {
            return
        }
        synchronized(this) {
            if (initialized) {
                return
            }
            MnnLlmApplication.initialize(application)
            MnnLocalConfigStore.syncProviderState(ready = false)
            initialized = true
        }
    }
}
