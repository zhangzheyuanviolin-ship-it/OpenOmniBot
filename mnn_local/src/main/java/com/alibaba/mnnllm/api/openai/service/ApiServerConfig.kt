package com.alibaba.mnnllm.api.openai.service

import android.content.Context
import androidx.annotation.Keep
import cn.com.omnimind.bot.mnnlocal.MnnLocalConfigStore
import timber.log.Timber

/** * APIserviceconfigmanagingclass * responsible for managingserviceconfigparameter,includingport,IPaddress,CORSandauthenticationsettings*/
@Keep
object ApiServerConfig {
    private const val TAG = "ApiServerConfig"

    /** * initializeconfig * if it'sfirst timerunning,willsavedefaultconfigtoSharedPreferences*/
    fun initializeConfig(context: Context) {
        MnnLocalConfigStore.syncProviderState(ready = false)
        logCurrentConfig(context)
    }

    /** * getserviceport*/
    fun getPort(context: Context): Int {
        return MnnLocalConfigStore.getPort()
    }

    /** * getbindIPaddress*/
    fun getIpAddress(context: Context): String {
        return MnnLocalConfigStore.getBindHost()
    }

    /** * getCORSenablestate*/
    fun isCorsEnabled(context: Context): Boolean {
        return false
    }

    /** * getCORSallowedsource*/
    fun getCorsOrigins(context: Context): String {
        return ""
    }

    /** * getauthenticationenablestate*/
    fun isAuthEnabled(context: Context): Boolean {
        return true
    }

    fun useHttpsUrl(context: Context): Boolean {
        return false
    }

    /**
     * getAPIkey*/
    fun getApiKey(context: Context): String {
        return MnnLocalConfigStore.getApiKey()
    }

    /**
     * saveconfig*/
    fun saveConfig(
        context: Context,
        port: Int,
        ipAddress: String,
        corsEnabled: Boolean,
        corsOrigins: String,
        authEnabled: Boolean,
        apiKey: String,
        useHttpsUrl: Boolean
    ) {
        MnnLocalConfigStore.setPort(port)
        MnnLocalConfigStore.setLanEnabled(ipAddress != "127.0.0.1")
        MnnLocalConfigStore.setApiKey(apiKey)
        Timber.Forest.tag(TAG).i("Config saved: port=$port, ip=$ipAddress, cors=$corsEnabled, auth=$authEnabled, useHttpsUrl=$useHttpsUrl")
    }

    /** * resetasdefaultconfig*/
    fun resetToDefault(context: Context) {
        MnnLocalConfigStore.setPort(8080)
        MnnLocalConfigStore.setLanEnabled(false)
        MnnLocalConfigStore.setApiKey(MnnLocalConfigStore.getApiKey())
        Timber.Forest.tag(TAG).i("Config reset to default values")
    }

    /** * recordcurrentconfigtolog*/
    private fun logCurrentConfig(context: Context) {
        val port = getPort(context)
        val ipAddress = getIpAddress(context)
        val corsEnabled = isCorsEnabled(context)
        val authEnabled = isAuthEnabled(context)
        val httpsUrl = useHttpsUrl(context)

        Timber.Forest.tag(TAG).i("Current config - Port: $port, IP: $ipAddress, CORS: $corsEnabled, Auth: $authEnabled, HTTPS URL: $httpsUrl")
    }
}
