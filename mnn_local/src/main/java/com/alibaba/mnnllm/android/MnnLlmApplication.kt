// Created by ruoyi.sjd on 2024/12/18.
// Copyright (c) 2024 Alibaba Group Holding Limited All rights reserved.
package com.alibaba.mnnllm.android

import android.app.Application
import com.alibaba.mls.api.ApplicationProvider
import com.alibaba.mls.api.download.ModelDownloadManager
import com.alibaba.mnnllm.android.update.UpdateChecker
import com.alibaba.mnnllm.android.utils.CrashUtil
import com.alibaba.mnnllm.android.utils.CurrentActivityTracker
import com.alibaba.mnnllm.android.utils.TimberConfig
import timber.log.Timber
import android.content.Context
import com.jaredrummler.android.device.DeviceName
import com.alibaba.mnnllm.android.modelist.ModelListManager
import com.alibaba.mnnllm.android.privacy.PrivacyPolicyManager
import com.google.firebase.crashlytics.FirebaseCrashlytics

class MnnLlmApplication : Application() {
    
    override fun onCreate() {
        super.onCreate()
        initialize(this)
    }

    fun applyCrashReportingConsent() {
        if (!BuildConfig.ENABLE_FIREBASE) {
            return
        }
        val consented = PrivacyPolicyManager.getInstance(this).isCrashReportingConsented()
        try {
            FirebaseCrashlytics.getInstance().setCrashlyticsCollectionEnabled(consented)
            FirebaseCrashlytics.getInstance().setCustomKey("user_crash_reporting_consent", consented)
        } catch (t: Throwable) {
            Timber.w(t, "Failed to apply Crashlytics consent state")
        }
    }

    companion object {
        private lateinit var instance: Application

        fun initialize(application: Application) {
            ApplicationProvider.set(application)
            UpdateChecker.registerDownloadReceiver(application.applicationContext)
            CrashUtil.init(application)
            instance = application
            DeviceName.init(application)
            CurrentActivityTracker.initialize(application)
            TimberConfig.initialize(application)
            ModelListManager.setContext(application)
            ModelDownloadManager.getInstance(application).setProgressCallbackIntervalMs(500L)
            runCatching {
                if (application is MnnLlmApplication) {
                    application.applyCrashReportingConsent()
                }
            }
            StethoInitializer.initialize(application)
        }

        fun getAppContext(): Context {
            return instance.applicationContext
        }
        
        /**
         * Get the application instance for accessing Timber configuration
         */
        fun getInstance(): Application {
            return instance
        }
    }
}
