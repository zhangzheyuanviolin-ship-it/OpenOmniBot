package com.alibaba.mnnllm.api.openai.service

import android.Manifest
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.annotation.Keep
import androidx.core.content.ContextCompat
import com.alibaba.mnnllm.api.openai.di.ServiceLocator
import com.alibaba.mnnllm.api.openai.manager.ApiNotificationManager
import com.alibaba.mnnllm.api.openai.manager.CurrentModelManager
import cn.com.omnimind.bot.mnnlocal.MnnLocalConfigStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import timber.log.Timber

@Keep
class OpenAIService : Service() {
    private val TAG = this::class.java.simpleName
    private lateinit var coordinator: ApiServiceCoordinator
    private var currentModelId: String? = null
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var startRequestCount: Int = 0

    companion object {
        private var isServiceRunning = false
        private var activeInstance: OpenAIService? = null

        fun getInstance(): OpenAIService? = activeInstance

        fun startService(context: Context, modelId: String? = null) {
            MnnLocalConfigStore.setApiEnabled(true)
            if (!modelId.isNullOrBlank()) {
                MnnLocalConfigStore.setActiveModelId(modelId)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                if (ContextCompat.checkSelfPermission(
                        context,
                        Manifest.permission.POST_NOTIFICATIONS
                    ) != PackageManager.PERMISSION_GRANTED
                ) {
                    if (context is android.app.Activity) {
                        Timber.tag("ServiceStartCondition").i("Requesting POST_NOTIFICATIONS permission.")
                        androidx.core.app.ActivityCompat.requestPermissions(
                            context,
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            1001 // Request code
                        )
                    } else {
                        Timber.tag("ServiceStartCondition").w("Context is not Activity, cannot request permission.")
                    }
                    Timber.tag("ServiceStartCondition").w("Notification permission not granted, but proceeding. Notification might be hidden.")
                    // Do not return here; let the service start.
                }
            }

            val serviceIntent = Intent(context, OpenAIService::class.java)
            //pass modelId toservice
            modelId?.let { serviceIntent.putExtra("modelId", it) }
            isServiceRunning = true
            try {
                context.startForegroundService(serviceIntent)
                Timber.tag("ServiceStartCondition").i("Foreground service started successfully")
            } catch (e: Exception) {
                Timber.tag("ServiceStartCondition").e(e, "Failed to start foreground service")
                isServiceRunning = false
                MnnLocalConfigStore.syncProviderState(ready = false)
                return
            }
        }

        /** * releaseserviceresourceandstopservice * * @param context contextobject * @param force whetherforcestop，defaultasfalse*/
        fun releaseService(context: Context, force: Boolean = false) {
            val serviceIntent = Intent(context, OpenAIService::class.java)
            MnnLocalConfigStore.setApiEnabled(false)
            
            try {
                if (force) {
                    context.stopService(serviceIntent)
                    Timber.tag("ServiceRelease").w("Service stopped forcefully")
                } else {
                    if (context.stopService(serviceIntent)) {
                        Timber.tag("ServiceRelease").i("Service stopped gracefully")
                    } else {
                        Timber.tag("ServiceRelease").w("Service was not running")
                    }
                }
            } catch (e: Exception) {
                Timber.tag("ServiceRelease").e(e, "Failed to stop service")
                if (force) {
                    try {
                        context.stopService(serviceIntent)
                        Timber.tag("ServiceRelease").w("Retry force stop succeeded")
                    } catch (e: Exception) {
                        Timber.tag("ServiceRelease").e(e, "Force stop also failed")
                    }
                }
            }

            isServiceRunning = false
            MnnLocalConfigStore.syncProviderState(ready = false)
            Timber.tag("ServiceLifecycle").i("OpenAIService resources released")
        }
    }



    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        isServiceRunning = true
        startRequestCount += 1

        val previousModelId = currentModelId
        val requestedModelId = intent?.getStringExtra("modelId") ?: MnnLocalConfigStore.getActiveModelId()
        if (!requestedModelId.isNullOrBlank()) {
            currentModelId = requestedModelId
            CurrentModelManager.setCurrentModelId(requestedModelId)
            MnnLocalConfigStore.setActiveModelId(requestedModelId)
            Timber.tag(TAG).i("Service started with modelId: $requestedModelId")
        }

        val notification = coordinator.getNotification()
        if (notification != null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(ApiNotificationManager.NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(ApiNotificationManager.NOTIFICATION_ID, notification)
            }
        }

        // Run startServer off main thread to avoid ANR: ensureSession (llmSession.load) is heavy
        val startModelId = if (!requestedModelId.isNullOrBlank()) requestedModelId else currentModelId
        serviceScope.launch {
            val startSuccess = coordinator.startServer(startModelId)
            MnnLocalConfigStore.syncProviderState(ready = startSuccess)
            if (!startSuccess && !requestedModelId.isNullOrBlank()) {
                currentModelId = previousModelId
                syncCurrentModelManager(previousModelId)
                Timber.tag(TAG).w("Failed to switch service runtime model, rolled back to previous modelId: $previousModelId")
            }
        }
        return START_STICKY
    }

    override fun onCreate() {
        super.onCreate()
        activeInstance = this
        coordinator = ApiServiceCoordinator(this)
        coordinator.initialize()
    }




    

    override fun onDestroy() {
        Timber.tag(TAG).i("Service is being destroyed")
        serviceScope.cancel()
        cleanup()
        MnnLocalConfigStore.syncProviderState(ready = false)
        if (activeInstance == this) {
            activeInstance = null
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder {
        Timber.tag(TAG).d("Service bound by client")
        return LocalBinder()
    }

    inner class LocalBinder : Binder() {
        fun getService(): OpenAIService = this@OpenAIService
    }


    /** * cleanupserviceresource * * includingstopforegroundserviceandcleanupcoordinatorresource*/
    private fun cleanup() {
        try {
            coordinator.cleanup()
            Timber.tag(TAG).d("Coordinator cleanup completed")
        } catch (e: Exception) {
            Timber.tag(TAG).e(e, "Failed to cleanup coordinator")
        }
        
        //clearglobalmodelID
        CurrentModelManager.clearCurrentModelId()
        ServiceLocator.getLlmRuntimeController().releaseSession()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                stopForeground(STOP_FOREGROUND_REMOVE)
                Timber.tag(TAG).d("Foreground service stopped (API >= TIRAMISU)")
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
                Timber.tag(TAG).d("Foreground service stopped (legacy API)")
            }
        } catch (e: Exception) {
            Timber.tag(TAG).e(e, "Failed to stop foreground service")
        } finally {
            Timber.tag(TAG).i("Service cleanup completed")
        }
    }
    fun updateNotification(contentTitle: String, contentText: String) {
        coordinator.updateNotification(contentTitle, contentText)
    }

    fun getServerPort(): Int? = coordinator.getServerPort()
    
    fun isServerRunning(): Boolean = coordinator.isServerRunning
    
    fun getCurrentModelId(): String? = currentModelId

    fun ensureModelReady(modelId: String?): Boolean {
        val normalizedModelId = modelId?.trim().orEmpty()
        if (normalizedModelId.isEmpty()) {
            return coordinator.startServer(currentModelId)
        }
        val previousModelId = currentModelId
        currentModelId = normalizedModelId
        CurrentModelManager.setCurrentModelId(normalizedModelId)
        MnnLocalConfigStore.setActiveModelId(normalizedModelId)
        val success = coordinator.startServer(normalizedModelId)
        if (!success) {
            currentModelId = previousModelId
            syncCurrentModelManager(previousModelId)
        }
        return success
    }

    fun getBootstrapCount(): Int = coordinator.getBootstrapCount()

    fun getStartRequestCount(): Int = startRequestCount

    private fun syncCurrentModelManager(modelId: String?) {
        if (modelId.isNullOrBlank()) {
            CurrentModelManager.clearCurrentModelId()
        } else {
            CurrentModelManager.setCurrentModelId(modelId)
        }
    }
}
