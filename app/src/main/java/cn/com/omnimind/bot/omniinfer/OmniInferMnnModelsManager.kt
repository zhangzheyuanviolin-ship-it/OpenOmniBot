package cn.com.omnimind.bot.omniinfer

import android.content.Context
import com.alibaba.mls.api.download.DownloadInfo
import com.alibaba.mls.api.download.DownloadListener
import com.alibaba.mls.api.download.DownloadState
import com.alibaba.mls.api.download.ModelDownloadManager
import com.alibaba.mls.api.source.ModelSources
import com.tencent.mmkv.MMKV
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale

object OmniInferMnnModelsManager {
    private const val BACKEND_NAME = OmniInferLocalRuntime.BACKEND_OMNIINFER_MNN
    private const val MMKV_ID = "omniinfer_config"
    private const val KEY_ACTIVE_MODEL_ID = "omniinfer_mnn_active_model_id"
    private const val KEY_AUTO_START = "omniinfer_mnn_auto_start_on_app_open"
    private const val KEY_DOWNLOAD_PROVIDER = "omniinfer_mnn_download_provider"
    private const val MANUAL_MODELS_ROOT = "/data/local/tmp/mnn_models"

    private data class InstalledModelRecord(
        val id: String,
        val name: String,
        val path: String,
        val configPath: String,
        val source: String,
        val description: String,
        val vendor: String,
        val tags: List<String>,
        val extraTags: List<String>,
        val fileSize: Long,
        val downloadedAt: Long,
        val readOnly: Boolean,
        val downloadInfo: DownloadInfo?,
    )

    private var appContext: Context? = null
    private var eventDispatcher: ((Map<String, Any?>) -> Unit)? = null
    private val mmkv: MMKV by lazy { MMKV.mmkvWithID(MMKV_ID) }
    private val downloadListenerLock = Any()

    @Volatile
    private var downloadListenerRegistered = false

    private val downloadListener = object : DownloadListener {
        override fun onDownloadStart(modelId: String) {
            emitDownloadUpdate(modelId)
        }

        override fun onDownloadProgress(modelId: String, downloadInfo: DownloadInfo) {
            emitDownloadUpdate(modelId, downloadInfo)
        }

        override fun onDownloadFinished(modelId: String, path: String) {
            emitDownloadUpdate(modelId)
            emitEvent("downloads_changed", emptyMap())
        }

        override fun onDownloadFailed(modelId: String, e: Exception) {
            emitDownloadUpdate(modelId)
            emitEvent("downloads_changed", emptyMap())
        }

        override fun onDownloadPaused(modelId: String) {
            emitDownloadUpdate(modelId)
            emitEvent("downloads_changed", emptyMap())
        }

        override fun onDownloadFileRemoved(modelId: String) {
            emitDownloadUpdate(modelId)
            emitEvent("downloads_changed", emptyMap())
        }

        override fun onDownloadTotalSize(modelId: String, totalSize: Long) {
            emitDownloadUpdate(modelId)
        }

        override fun onDownloadHasUpdate(modelId: String, downloadInfo: DownloadInfo) {
            emitDownloadUpdate(modelId, downloadInfo)
        }
    }

    fun setContext(context: Context) {
        val applicationContext = context.applicationContext
        appContext = applicationContext
        OmniInferLocalRuntime.setContext(applicationContext)
        OmniInferMnnMarketRepository.setContext(applicationContext)
        ensureDownloadListenerRegistered(applicationContext)
    }

    fun setEventDispatcher(dispatcher: ((Map<String, Any?>) -> Unit)?) {
        eventDispatcher = dispatcher
    }

    fun clear() {
        eventDispatcher = null
    }

    fun handleAppOpen() {
        if (shouldAutoStartOnAppOpen()) {
            startApiService(getActiveModelId())
        }
    }

    suspend fun getOverview(
        installedQuery: String? = null,
        marketQuery: String? = null,
        marketCategory: String? = null,
    ): Map<String, Any?> {
        return mapOf(
            "config" to getConfig(),
            "installedModels" to listInstalledModels(installedQuery, marketCategory),
            "market" to listMarketModels(marketQuery, marketCategory, refresh = false),
        )
    }

    fun listInstalledModels(
        query: String? = null,
        category: String? = null,
    ): List<Map<String, Any?>> {
        ensureContext()
        val normalizedQuery = query?.trim()?.lowercase(Locale.getDefault()).orEmpty()
        return installedRecords()
            .filter { record ->
                if (normalizedQuery.isEmpty()) {
                    true
                } else {
                    listOf(
                        record.id,
                        record.name,
                        record.vendor,
                        record.description,
                        record.path,
                    ).plus(record.tags)
                        .plus(record.extraTags)
                        .any { value -> value.lowercase(Locale.getDefault()).contains(normalizedQuery) }
                }
            }
            .sortedWith(
                compareByDescending<InstalledModelRecord> { it.downloadedAt }
                    .thenBy { it.name.lowercase(Locale.getDefault()) }
            )
            .map(::installedRecordToMap)
    }

    suspend fun refreshInstalledModels(): List<Map<String, Any?>> {
        return listInstalledModels()
    }

    suspend fun listMarketModels(
        query: String? = null,
        category: String? = null,
        refresh: Boolean = false,
    ): Map<String, Any?> {
        ensureContext()
        val selectedSource = getDownloadProvider()
        val normalizedQuery = query?.trim()?.lowercase(Locale.getDefault()).orEmpty()
        val models = OmniInferMnnMarketRepository.listModels(selectedSource, refresh)
            .filter { resolved ->
                if (normalizedQuery.isEmpty()) {
                    true
                } else {
                    buildList {
                        add(resolved.modelId)
                        add(resolved.item.modelName)
                        add(resolved.item.vendor.orEmpty())
                        addAll(resolved.item.tags)
                        addAll(resolved.item.extraTags)
                    }.any { value -> value.lowercase(Locale.getDefault()).contains(normalizedQuery) }
                }
            }
            .map(::marketModelToMap)
        return mapOf(
            "source" to selectedSource,
            "availableSources" to ModelSources.sourceList,
            "category" to "llm",
            "models" to models,
        )
    }

    suspend fun refreshMarketModels(
        query: String? = null,
        category: String? = null,
    ): Map<String, Any?> {
        return listMarketModels(query = query, category = category, refresh = true)
    }

    fun getConfig(): Map<String, Any?> {
        ensureContext()
        return mapOf(
            "backend" to BACKEND_NAME,
            "autoStartOnAppOpen" to shouldAutoStartOnAppOpen(),
            "apiRunning" to OmniInferLocalRuntime.isReady(),
            "apiReady" to OmniInferLocalRuntime.isReady(),
            "apiState" to if (OmniInferLocalRuntime.isReady()) "running" else "stopped",
            "apiHost" to OmniInferLocalRuntime.getHost(),
            "apiPort" to OmniInferLocalRuntime.getPort(),
            "baseUrl" to OmniInferLocalRuntime.getBaseUrl(),
            "activeModelId" to getActiveModelId(),
            "downloadProvider" to getDownloadProvider(),
            "availableSources" to ModelSources.sourceList,
            "loadedBackend" to OmniInferLocalRuntime.getLoadedBackend(),
            "loadedModelId" to OmniInferLocalRuntime.getLoadedModelId(),
        )
    }

    fun saveConfig(arguments: Map<*, *>): Map<String, Any?> {
        arguments["autoStartOnAppOpen"]?.let {
            mmkv.encode(KEY_AUTO_START, it == true)
        }
        arguments["apiPort"]?.let {
            val port = (it as? Number)?.toInt()
            if (port != null && port > 0) {
                OmniInferLocalRuntime.setPort(port)
            }
        }
        arguments["activeModelId"]?.let {
            mmkv.encode(KEY_ACTIVE_MODEL_ID, it.toString())
        }
        arguments["downloadProvider"]?.let {
            mmkv.encode(KEY_DOWNLOAD_PROVIDER, normalizeSource(it.toString()))
        }
        emitConfigChanged()
        return getConfig()
    }

    fun setActiveModel(modelId: String?): Map<String, Any?> {
        mmkv.encode(KEY_ACTIVE_MODEL_ID, modelId?.trim().orEmpty())
        emitConfigChanged()
        return getConfig()
    }

    fun startApiService(modelId: String? = null): Map<String, Any?> {
        val targetModelId = modelId?.trim().orEmpty().ifBlank { getActiveModelId() }
        if (targetModelId.isBlank()) {
            return getConfig()
        }
        val resolved = findInstalledRecord(targetModelId) ?: return getConfig()
        mmkv.encode(KEY_ACTIVE_MODEL_ID, resolved.id)
        OmniInferLocalRuntime.loadModel(
            modelId = resolved.id,
            modelPath = resolved.configPath,
            backend = BACKEND_NAME,
        )
        emitConfigChanged()
        return getConfig()
    }

    fun ensureModelReady(modelId: String): Boolean {
        val normalizedModelId = modelId.trim()
        if (normalizedModelId.isEmpty()) {
            return false
        }
        val resolved = findInstalledRecord(normalizedModelId) ?: return false
        if (OmniInferLocalRuntime.isModelLoaded(BACKEND_NAME, resolved.id)) {
            return true
        }
        mmkv.encode(KEY_ACTIVE_MODEL_ID, resolved.id)
        return OmniInferLocalRuntime.loadModel(
            modelId = resolved.id,
            modelPath = resolved.configPath,
            backend = BACKEND_NAME,
        )
    }

    fun stopApiService(): Map<String, Any?> {
        OmniInferLocalRuntime.stop()
        emitConfigChanged()
        return getConfig()
    }

    fun startDownload(modelId: String) {
        val context = ensureContext()
        ensureDownloadListenerRegistered(context)
        ModelDownloadManager.getInstance(context).startDownload(modelId)
        emitDownloadUpdate(modelId)
    }

    fun pauseDownload(modelId: String) {
        val context = ensureContext()
        ensureDownloadListenerRegistered(context)
        ModelDownloadManager.getInstance(context).pauseDownload(modelId)
        emitDownloadUpdate(modelId)
    }

    suspend fun deleteModel(modelId: String): List<Map<String, Any?>> {
        val normalizedModelId = modelId.trim()
        val target = findInstalledRecord(normalizedModelId) ?: return listInstalledModels()
        if (target.readOnly) {
            return listInstalledModels()
        }
        val context = ensureContext()
        if (OmniInferLocalRuntime.isModelLoaded(BACKEND_NAME, normalizedModelId)) {
            OmniInferLocalRuntime.stop()
        }
        ModelDownloadManager.getInstance(context).deleteModel(normalizedModelId)
        if (getActiveModelId() == normalizedModelId) {
            mmkv.encode(KEY_ACTIVE_MODEL_ID, "")
        }
        emitConfigChanged()
        emitEvent("downloads_changed", emptyMap())
        return listInstalledModels()
    }

    private fun ensureContext(): Context {
        return appContext ?: error("OmniInfer MNN context is not initialized")
    }

    private fun getActiveModelId(): String {
        return mmkv.decodeString(KEY_ACTIVE_MODEL_ID, "").orEmpty()
    }

    private fun shouldAutoStartOnAppOpen(): Boolean {
        return mmkv.decodeBool(KEY_AUTO_START, false)
    }

    private fun getDownloadProvider(): String {
        return normalizeSource(mmkv.decodeString(KEY_DOWNLOAD_PROVIDER, ModelSources.sourceModelScope))
    }

    private fun normalizeSource(rawSource: String?): String {
        val source = rawSource?.trim().orEmpty()
        return if (ModelSources.sourceList.contains(source)) {
            source
        } else {
            ModelSources.sourceModelScope
        }
    }

    private fun installedRecords(): List<InstalledModelRecord> {
        val records = LinkedHashMap<String, InstalledModelRecord>()
        downloadedRecords().forEach { records.putIfAbsent(it.id, it) }
        manualRecords().forEach { records.putIfAbsent(it.id, it) }
        return records.values.toList()
    }

    private fun downloadedRecords(): List<InstalledModelRecord> {
        val context = ensureContext()
        val downloadManager = ModelDownloadManager.getInstance(context)
        return OmniInferMnnMarketRepository.allModels().mapNotNull { resolved ->
            val downloadPath = downloadManager.getDownloadedFile(resolved.modelId) ?: return@mapNotNull null
            val configFile = File(downloadPath, "config.json")
            if (!configFile.exists()) {
                return@mapNotNull null
            }
            InstalledModelRecord(
                id = resolved.modelId,
                name = resolved.item.modelName.ifBlank { resolved.modelId.substringAfterLast('/') },
                path = downloadPath.absolutePath,
                configPath = configFile.absolutePath,
                source = resolved.source,
                description = buildDescription(resolved.item),
                vendor = resolved.item.vendor.orEmpty(),
                tags = (resolved.item.tags + listOf("MNN")).distinct(),
                extraTags = resolved.item.extraTags,
                fileSize = resolved.item.fileSize,
                downloadedAt = downloadPath.lastModified(),
                readOnly = false,
                downloadInfo = downloadManager.getDownloadInfo(resolved.modelId),
            )
        }
    }

    private fun manualRecords(): List<InstalledModelRecord> {
        val modelsRoot = File(MANUAL_MODELS_ROOT)
        if (!modelsRoot.exists() || !modelsRoot.isDirectory) {
            return emptyList()
        }
        return modelsRoot.listFiles()
            ?.filter { it.isDirectory }
            ?.mapNotNull { modelDir ->
                val configFile = File(modelDir, "config.json")
                if (!configFile.exists()) {
                    null
                } else {
                    InstalledModelRecord(
                        id = "local/${modelDir.absolutePath}",
                        name = modelDir.name,
                        path = modelDir.absolutePath,
                        configPath = configFile.absolutePath,
                        source = "local",
                        description = "鎵嬪姩鏀剧疆鐩綍妯″瀷",
                        vendor = "",
                        tags = listOf("MNN", "Manual"),
                        extraTags = emptyList(),
                        fileSize = 0L,
                        downloadedAt = modelDir.lastModified(),
                        readOnly = true,
                        downloadInfo = null,
                    )
                }
            }
            ?.sortedByDescending { it.downloadedAt }
            .orEmpty()
    }

    private fun findInstalledRecord(modelId: String): InstalledModelRecord? {
        val normalizedModelId = modelId.trim()
        if (normalizedModelId.isEmpty()) {
            return null
        }
        return installedRecords().firstOrNull { it.id == normalizedModelId }
    }

    private fun installedRecordToMap(record: InstalledModelRecord): Map<String, Any?> {
        val activeModelId = getActiveModelId()
        val fileSize = record.fileSize.takeIf { it > 0L } ?: record.downloadInfo?.totalSize ?: 0L
        return mapOf(
            "id" to record.id,
            "name" to record.name,
            "category" to "llm",
            "source" to record.source,
            "description" to record.description,
            "path" to record.path,
            "vendor" to record.vendor,
            "tags" to record.tags,
            "extraTags" to record.extraTags,
            "active" to (record.id == activeModelId || record.id == OmniInferLocalRuntime.getLoadedModelId()),
            "isLocal" to true,
            "isPinned" to false,
            "hasUpdate" to (record.downloadInfo?.hasUpdate == true),
            "fileSize" to fileSize,
            "sizeB" to fileSize.toDouble(),
            "formattedSize" to formatSize(fileSize),
            "lastUsedAt" to 0,
            "downloadedAt" to record.downloadedAt,
            "download" to record.downloadInfo?.toMap(),
            "readOnly" to record.readOnly,
        )
    }

    private fun marketModelToMap(model: OmniInferMnnMarketRepository.ResolvedMarketModel): Map<String, Any?> {
        val context = ensureContext()
        val downloadManager = ModelDownloadManager.getInstance(context)
        val downloadedFile = downloadManager.getDownloadedFile(model.modelId)
        val downloadInfo = downloadManager.getDownloadInfo(model.modelId)
        val fileSize = if (model.item.fileSize > 0L) model.item.fileSize else downloadInfo.totalSize
        return mapOf(
            "id" to model.modelId,
            "name" to model.item.modelName,
            "category" to "llm",
            "source" to model.source,
            "description" to buildDescription(model.item),
            "path" to downloadedFile?.absolutePath.orEmpty(),
            "vendor" to model.item.vendor.orEmpty(),
            "tags" to (model.item.tags + listOf("MNN")).distinct(),
            "extraTags" to model.item.extraTags,
            "active" to (model.modelId == getActiveModelId()),
            "isLocal" to (downloadedFile != null),
            "isPinned" to false,
            "hasUpdate" to downloadInfo.hasUpdate,
            "fileSize" to fileSize,
            "sizeB" to fileSize.toDouble(),
            "formattedSize" to formatSize(fileSize),
            "lastUsedAt" to 0,
            "downloadedAt" to (downloadedFile?.lastModified() ?: 0L),
            "download" to downloadInfo.toMap(),
            "readOnly" to false,
        )
    }

    private fun buildDescription(item: OmniInferMnnMarketRepository.MarketItem): String {
        return buildList {
            item.vendor?.takeIf { it.isNotBlank() }?.let { add(it) }
            if (item.tags.isNotEmpty()) {
                add(item.tags.joinToString(separator = " / "))
            }
        }.joinToString(separator = " 路 ")
    }

    private fun ensureDownloadListenerRegistered(context: Context) {
        if (downloadListenerRegistered) {
            return
        }
        synchronized(downloadListenerLock) {
            if (downloadListenerRegistered) {
                return
            }
            ModelDownloadManager.getInstance(context).addListener(downloadListener)
            downloadListenerRegistered = true
        }
    }

    private fun emitConfigChanged() {
        emitEvent("config_changed", mapOf("config" to getConfig()))
    }

    private fun emitDownloadUpdate(
        modelId: String,
        downloadInfo: DownloadInfo? = appContext?.let { ModelDownloadManager.getInstance(it).getDownloadInfo(modelId) },
    ) {
        emitEvent(
            "download_update",
            mapOf(
                "modelId" to modelId,
                "download" to downloadInfo?.toMap(),
            )
        )
    }

    private fun emitEvent(type: String, payload: Map<String, Any?>) {
        eventDispatcher?.invoke(
            buildMap {
                put("type", type)
                putAll(payload)
            }
        )
    }

    private fun DownloadInfo.toMap(): Map<String, Any?> {
        return mapOf(
            "state" to downloadState,
            "stateLabel" to when (downloadState) {
                DownloadState.NOT_START -> "not_started"
                DownloadState.PREPARING -> "preparing"
                DownloadState.DOWNLOADING -> "downloading"
                DownloadState.DOWNLOAD_SUCCESS -> "completed"
                DownloadState.DOWNLOAD_FAILED -> "failed"
                DownloadState.DOWNLOAD_PAUSED -> "paused"
                DownloadState.DOWNLOAD_CANCELLED -> "cancelled"
                else -> "unknown"
            },
            "progress" to progress,
            "savedSize" to savedSize,
            "totalSize" to totalSize,
            "speedInfo" to speedInfo,
            "errorMessage" to errorMessage.orEmpty(),
            "progressStage" to progressStage,
            "currentFile" to currentFile.orEmpty(),
            "downloadedTime" to downloadedTime,
            "hasUpdate" to hasUpdate,
        )
    }

    private fun formatSize(bytes: Long): String {
        if (bytes <= 0L) {
            return ""
        }
        return when {
            bytes >= 1_073_741_824 -> String.format(Locale.US, "%.1f GB", bytes / 1_073_741_824.0)
            bytes >= 1_048_576 -> String.format(Locale.US, "%.1f MB", bytes / 1_048_576.0)
            bytes >= 1024 -> String.format(Locale.US, "%.1f KB", bytes / 1024.0)
            else -> "$bytes B"
        }
    }
}

