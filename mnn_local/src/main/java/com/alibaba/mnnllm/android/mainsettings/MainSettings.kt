// Created by ruoyi.sjd on 2025/2/28.
// Copyright (c) 2024 Alibaba Group Holding Limited All rights reserved.
package com.alibaba.mnnllm.android.mainsettings

import android.content.Context
import com.alibaba.mls.api.source.ModelSources
import com.alibaba.mnnllm.android.utils.DeviceUtils
import cn.com.omnimind.bot.mnnlocal.MnnLocalConfigStore


object MainSettings {

    fun getDownloadProvider(context: Context): ModelSources.ModelSourceType {
        val result = getDownloadProviderString(context)
        return when (result) {
            ModelSources.sourceHuffingFace -> ModelSources.ModelSourceType.HUGGING_FACE
            ModelSources.sourceModelScope -> ModelSources.ModelSourceType.MODEL_SCOPE
            else -> ModelSources.ModelSourceType.MODELERS
         }
    }

    fun setDownloadProvider(context: Context, source:String) {
        MnnLocalConfigStore.setDownloadProviderString(source)
    }

    fun getDownloadProviderString(context: Context):String {
        return MnnLocalConfigStore.getDownloadProviderString().ifEmpty {
            getDefaultDownloadProvider()
        }
    }

    private fun getDefaultDownloadProvider():String {
        return if (DeviceUtils.isChinese) ModelSources.sourceModelScope else ModelSources.sourceHuffingFace
    }

    fun isStopDownloadOnChatEnabled(context: Context): Boolean {
        return true
    }

    fun isApiServiceEnabled(context: Context): Boolean {
        return MnnLocalConfigStore.isApiEnabled()
    }

    /**
     * Get the default TTS model ID
     */
    fun getDefaultTtsModel(context: Context): String? {
        return MnnLocalConfigStore.getDefaultTtsModelId()
    }

    /**
     * Set the default TTS model ID
     */
    fun setDefaultTtsModel(context: Context, modelId: String) {
        MnnLocalConfigStore.setDefaultTtsModelId(modelId)
    }

    /**
     * Check if the given model is the current default TTS model
     */
    fun isDefaultTtsModel(context: Context, modelId: String): Boolean {
        return getDefaultTtsModel(context) == modelId
    }

    /**
     * Get the default ASR model ID
     */
    fun getDefaultAsrModel(context: Context): String? {
        return MnnLocalConfigStore.getDefaultAsrModelId()
    }

    /**
     * Set the default ASR model ID
     */
    fun setDefaultAsrModel(context: Context, modelId: String) {
        MnnLocalConfigStore.setDefaultAsrModelId(modelId)
    }

    /**
     * Check if the given model is the current default ASR model
     */
    fun isDefaultAsrModel(context: Context, modelId: String): Boolean {
        return getDefaultAsrModel(context) == modelId
    }

}
