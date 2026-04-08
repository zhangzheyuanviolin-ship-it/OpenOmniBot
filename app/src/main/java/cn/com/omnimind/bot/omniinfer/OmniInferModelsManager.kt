package cn.com.omnimind.bot.omniinfer

import android.content.Context
import android.util.Log
import cn.com.omnimind.baselib.llm.MnnLocalProviderStateStore
import com.omniinfer.server.OmniInferServer
import com.tencent.mmkv.MMKV
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.internal.closeQuietly
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

object OmniInferModelsManager {
    private const val TAG = "OmniInferModels"
    private const val MARKET_URL =
        "https://omnimind-model.oss-cn-beijing.aliyuncs.com/llama.cpp/model_market.json"
    private const val MMKV_ID = "omniinfer_config"

    private var appContext: Context? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val client = OkHttpClient.Builder()
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    // Cached market data
    private var cachedMarketJson: JsonObject? = null
    private var cachedMarketModels: List<JsonObject> = emptyList()

    // Download state: modelId -> DownloadTask
    private val activeDownloads = ConcurrentHashMap<String, DownloadTask>()

    // Event dispatcher (set by channel)
    private var eventDispatcher: ((Map<String, Any?>) -> Unit)? = null

    private val mmkv: MMKV by lazy { MMKV.mmkvWithID(MMKV_ID) }

    fun setContext(context: Context) {
        appContext = context.applicationContext
    }

    fun setEventDispatcher(dispatcher: ((Map<String, Any?>) -> Unit)?) {
        eventDispatcher = dispatcher
    }

    fun clear() {
        activeDownloads.values.forEach { it.cancel() }
        activeDownloads.clear()
        eventDispatcher = null
    }

    // ── Config ──

    fun getConfig(): Map<String, Any?> {
        val port = mmkv.decodeInt("apiPort", 9099)
        val activeModelId = mmkv.decodeString("activeModelId", "") ?: ""
        val autoStart = mmkv.decodeBool("autoStartOnAppOpen", false)
        val downloadProvider = mmkv.decodeString("downloadProvider", "ModelScope") ?: "ModelScope"
        val running = OmniInferServer.isReady()

        return mapOf(
            "backend" to "llama.cpp",
            "autoStartOnAppOpen" to autoStart,
            "apiEnabled" to true,
            "apiLanEnabled" to false,
            "apiRunning" to running,
            "apiReady" to running,
            "apiState" to if (running) "running" else "stopped",
            "apiHost" to "127.0.0.1",
            "apiPort" to port,
            "apiKey" to "",
            "baseUrl" to "http://127.0.0.1:$port",
            "activeModelId" to activeModelId,
            "speechRecognitionProvider" to "system",
            "defaultAsrModelId" to "",
            "defaultTtsModelId" to "",
            "downloadProvider" to downloadProvider,
            "availableSources" to listOf("ModelScope", "HuggingFace"),
            "voiceReady" to false,
            "voiceStatusText" to "",
            "installedAsrModels" to emptyList<Any>(),
            "installedTtsModels" to emptyList<Any>(),
        )
    }

    fun saveConfig(args: Map<*, *>): Map<String, Any?> {
        args["apiPort"]?.let { mmkv.encode("apiPort", (it as Number).toInt()) }
        args["activeModelId"]?.let { mmkv.encode("activeModelId", it as String) }
        args["autoStartOnAppOpen"]?.let { mmkv.encode("autoStartOnAppOpen", it as Boolean) }
        args["downloadProvider"]?.let { mmkv.encode("downloadProvider", it as String) }
        return getConfig()
    }

    fun setActiveModel(modelId: String?): Map<String, Any?> {
        mmkv.encode("activeModelId", modelId ?: "")
        return getConfig()
    }

    // ── Installed Models ──

    private fun getModelDir(): File {
        val ctx = appContext ?: throw IllegalStateException("Context not set")
        val dir = File(ctx.getExternalFilesDir(null), "omniinfer-llama")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    fun listInstalledModels(query: String? = null, category: String? = null): List<Map<String, Any?>> {
        val dir = getModelDir()
        val files = dir.listFiles { f -> f.isFile && f.name.endsWith(".gguf") } ?: emptyArray()
        return files
            .sortedByDescending { it.lastModified() }
            .filter { file ->
                if (query.isNullOrBlank()) true
                else file.name.lowercase().contains(query.lowercase())
            }
            .map { file ->
                val id = file.nameWithoutExtension
                val download = activeDownloads[id]
                modelFileToMap(file, download)
            }
    }

    private fun modelFileToMap(file: File, download: DownloadTask? = null): Map<String, Any?> {
        val id = file.nameWithoutExtension
        val sizeBytes = file.length()
        val activeModelId = mmkv.decodeString("activeModelId", "") ?: ""
        return mapOf(
            "id" to id,
            "name" to id,
            "category" to "llm",
            "source" to "llama.cpp",
            "description" to "",
            "path" to file.absolutePath,
            "vendor" to "",
            "tags" to listOf("GGUF"),
            "extraTags" to emptyList<String>(),
            "active" to (id == activeModelId),
            "isLocal" to true,
            "isPinned" to false,
            "hasUpdate" to false,
            "fileSize" to sizeBytes,
            "sizeB" to sizeBytes.toDouble(),
            "formattedSize" to formatSize(sizeBytes),
            "lastUsedAt" to 0,
            "downloadedAt" to file.lastModified(),
            "download" to download?.toMap(),
        )
    }

    suspend fun refreshInstalledModels(): List<Map<String, Any?>> {
        return listInstalledModels()
    }

    // ── Market Models ──

    suspend fun listMarketModels(
        query: String? = null,
        category: String? = null,
        refresh: Boolean = false
    ): Map<String, Any?> {
        if (refresh || cachedMarketJson == null) {
            fetchMarketJson()
        }
        val source = mmkv.decodeString("downloadProvider", "ModelScope") ?: "ModelScope"
        val models = cachedMarketModels
            .filter { model ->
                if (query.isNullOrBlank()) true
                else {
                    val name = model["modelName"]?.jsonPrimitive?.contentOrNull ?: ""
                    val vendor = model["vendor"]?.jsonPrimitive?.contentOrNull ?: ""
                    name.lowercase().contains(query.lowercase()) ||
                        vendor.lowercase().contains(query.lowercase())
                }
            }
            .flatMap { model -> marketModelToMaps(model, source) }

        return mapOf(
            "source" to source,
            "category" to "llm",
            "availableSources" to listOf("ModelScope", "HuggingFace"),
            "models" to models,
        )
    }

    suspend fun refreshMarketModels(
        query: String? = null,
        category: String? = null,
    ): Map<String, Any?> {
        return listMarketModels(query = query, category = category, refresh = true)
    }

    private suspend fun fetchMarketJson() {
        try {
            val request = Request.Builder().url(MARKET_URL).get().build()
            val response = withContext(Dispatchers.IO) { client.newCall(request).execute() }
            val body = response.body?.string() ?: return
            val json = Json.parseToJsonElement(body).jsonObject
            cachedMarketJson = json
            cachedMarketModels = json["models"]?.jsonArray
                ?.mapNotNull { it.jsonObject }
                ?: emptyList()
            Log.i(TAG, "Fetched ${cachedMarketModels.size} market models")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to fetch market JSON", e)
        }
    }

    /**
     * Convert one market model entry (which may have multiple quants) into
     * multiple MnnLocalModel-compatible maps (one per quant).
     */
    private fun marketModelToMaps(model: JsonObject, source: String): List<Map<String, Any?>> {
        val modelName = model["modelName"]?.jsonPrimitive?.contentOrNull ?: return emptyList()
        val vendor = model["vendor"]?.jsonPrimitive?.contentOrNull ?: ""
        val tags = model["tags"]?.jsonArray?.mapNotNull { it.jsonPrimitive.contentOrNull } ?: emptyList()
        val params = model["params"]?.jsonPrimitive?.contentOrNull ?: ""
        val license = model["license"]?.jsonPrimitive?.contentOrNull ?: ""
        val quants = model["quants"]?.jsonObject ?: return emptyList()
        val sources = model["sources"]?.jsonObject

        val installedDir = getModelDir()

        return quants.entries.map { (quantName, quantObj) ->
            val sizeBytes = quantObj.jsonObject["size_bytes"]?.jsonPrimitive?.longOrNull ?: 0L
            val fileName = "$modelName-$quantName.gguf"
            val id = "$modelName-$quantName"
            val localFile = File(installedDir, fileName)
            val isLocal = localFile.exists() && localFile.length() > 0
            val download = activeDownloads[id]
            val repo = sources?.get(source)?.jsonPrimitive?.contentOrNull ?: ""

            mapOf(
                "id" to id,
                "name" to "$modelName $quantName",
                "category" to "llm",
                "source" to source,
                "description" to "Params: $params | License: $license | Repo: $repo",
                "path" to localFile.absolutePath,
                "vendor" to vendor,
                "tags" to (tags + listOf("GGUF", quantName)),
                "extraTags" to listOf(params),
                "active" to false,
                "isLocal" to isLocal,
                "isPinned" to false,
                "hasUpdate" to false,
                "fileSize" to sizeBytes,
                "sizeB" to sizeBytes.toDouble(),
                "formattedSize" to formatSize(sizeBytes),
                "lastUsedAt" to 0,
                "downloadedAt" to if (isLocal) localFile.lastModified() else 0L,
                "download" to download?.toMap(),
            )
        }
    }

    // ── Overview ──

    suspend fun getOverview(
        installedQuery: String? = null,
        marketQuery: String? = null,
        marketCategory: String? = null,
    ): Map<String, Any?> {
        return mapOf(
            "config" to getConfig(),
            "installedModels" to listInstalledModels(query = installedQuery),
            "market" to listMarketModels(query = marketQuery, category = marketCategory),
        )
    }

    // ── Download ──

    fun startDownload(modelId: String) {
        if (activeDownloads.containsKey(modelId)) {
            Log.w(TAG, "Download already in progress: $modelId")
            return
        }
        val source = mmkv.decodeString("downloadProvider", "ModelScope") ?: "ModelScope"
        val (repo, quantName) = findRepoAndQuantForModel(modelId, source) ?: run {
            Log.e(TAG, "No repo found for $modelId in source=$source")
            emitEvent("download_error", mapOf("modelId" to modelId, "error" to "No download source"))
            return
        }
        // Derive filename from repo name: e.g. "unsloth/gemma-4-E2B-it-GGUF" -> "gemma-4-E2B-it"
        val repoBaseName = repo.substringAfterLast("/")
            .removeSuffix("-GGUF").removeSuffix("-gguf")
        val remoteFileName = "$repoBaseName-$quantName.gguf"
        val localFileName = "$modelId.gguf"
        val url = buildDownloadUrl(source, repo, remoteFileName)
        val destFile = File(getModelDir(), localFileName)

        Log.i(TAG, "Starting download: $modelId -> $url")
        val task = DownloadTask(modelId, url, destFile)
        activeDownloads[modelId] = task
        task.start()
    }

    fun pauseDownload(modelId: String) {
        activeDownloads[modelId]?.cancel()
        activeDownloads.remove(modelId)
        emitEvent("downloads_changed", mapOf("modelId" to modelId))
    }

    suspend fun deleteModel(modelId: String): List<Map<String, Any?>> {
        val file = File(getModelDir(), "$modelId.gguf")
        if (file.exists()) file.delete()
        activeDownloads.remove(modelId)
        return listInstalledModels()
    }

    /**
     * Returns (repo, quantName) pair for a given modelId and source.
     */
    private fun findRepoAndQuantForModel(modelId: String, source: String): Pair<String, String>? {
        for (model in cachedMarketModels) {
            val modelName = model["modelName"]?.jsonPrimitive?.contentOrNull ?: continue
            val quants = model["quants"]?.jsonObject ?: continue
            for (quantName in quants.keys) {
                if ("$modelName-$quantName" == modelId) {
                    val repo = model["sources"]?.jsonObject?.get(source)?.jsonPrimitive?.contentOrNull
                        ?: return null
                    return Pair(repo, quantName)
                }
            }
        }
        return null
    }

    private fun buildDownloadUrl(source: String, repo: String, fileName: String): String {
        return when (source) {
            "HuggingFace" -> "https://huggingface.co/$repo/resolve/main/$fileName"
            "ModelScope" -> "https://modelscope.cn/models/$repo/resolve/master/$fileName"
            else -> "https://modelscope.cn/models/$repo/resolve/master/$fileName"
        }
    }

    // ── API Service ──

    fun startApiService(modelId: String?): Map<String, Any?> {
        val id = modelId ?: mmkv.decodeString("activeModelId", "") ?: ""
        if (id.isBlank()) {
            Log.w(TAG, "No model selected")
            return getConfig()
        }
        val file = File(getModelDir(), "$id.gguf")
        if (!file.exists()) {
            Log.e(TAG, "Model file not found: ${file.absolutePath}")
            return getConfig()
        }
        val port = mmkv.decodeInt("apiPort", 9099)
        mmkv.encode("activeModelId", id)
        val success = OmniInferServer.loadModel(
            modelPath = file.absolutePath,
            backend = "llama.cpp",
            port = port,
        )
        // Sync provider state so the agent system can discover this local provider
        MnnLocalProviderStateStore.update(port = port, apiKey = "", ready = success)
        return getConfig()
    }

    fun stopApiService(): Map<String, Any?> {
        OmniInferServer.stop()
        MnnLocalProviderStateStore.update(port = 9099, apiKey = "", ready = false)
        return getConfig()
    }

    /**
     * Called by LocalModelProviderBridge delegate to ensure a model is ready for inference.
     * If OmniInfer already has a model loaded, returns true.
     * Otherwise tries to find and load the requested model as a GGUF file.
     */
    fun ensureModelReady(modelId: String): Boolean {
        if (OmniInferServer.isReady()) return true
        val ctx = appContext ?: return false
        // Try to find model file
        val dir = getModelDir()
        val file = File(dir, "$modelId.gguf")
        if (!file.exists()) {
            // Try matching by name prefix (modelId might not have .gguf suffix)
            val match = dir.listFiles { f -> f.isFile && f.name.endsWith(".gguf") }
                ?.firstOrNull { it.nameWithoutExtension == modelId }
                ?: return false
            return loadAndWait(match.absolutePath)
        }
        return loadAndWait(file.absolutePath)
    }

    private fun loadAndWait(modelPath: String): Boolean {
        val port = mmkv.decodeInt("apiPort", 9099)
        val success = OmniInferServer.loadModel(
            modelPath = modelPath,
            backend = "llama.cpp",
            port = port,
        )
        if (success) {
            MnnLocalProviderStateStore.update(port = port, apiKey = "", ready = true)
        }
        return success
    }

    // ── Download Task ──

    private class DownloadTask(
        val modelId: String,
        val url: String,
        val destFile: File,
    ) {
        private var call: Call? = null
        private val cancelled = AtomicBoolean(false)

        fun cancel() {
            cancelled.set(true)
            call?.cancel()
        }

        fun toMap(): Map<String, Any?> {
            return mapOf(
                "state" to 1,
                "stateLabel" to "downloading",
                "progress" to progress,
                "savedSize" to savedSize,
                "totalSize" to totalSize,
                "speedInfo" to "",
                "errorMessage" to "",
                "progressStage" to "downloading",
                "currentFile" to destFile.name,
                "hasUpdate" to false,
            )
        }

        @Volatile var progress: Double = 0.0
        @Volatile var savedSize: Long = 0L
        @Volatile var totalSize: Long = 0L

        fun start() {
            OmniInferModelsManager.scope.launch {
                try {
                    val tempFile = File(destFile.parent, destFile.name + ".part")
                    var existingSize = if (tempFile.exists()) tempFile.length() else 0L

                    val requestBuilder = Request.Builder().url(url)
                    if (existingSize > 0) {
                        requestBuilder.header("Range", "bytes=$existingSize-")
                    }

                    call = OmniInferModelsManager.client.newCall(requestBuilder.build())
                    val response = call!!.execute()

                    if (!response.isSuccessful && response.code != 206) {
                        throw IOException("HTTP ${response.code}")
                    }

                    val body = response.body ?: throw IOException("Empty body")
                    val contentLength = body.contentLength()
                    totalSize = if (response.code == 206) existingSize + contentLength else contentLength
                    savedSize = if (response.code == 206) existingSize else 0L

                    val raf = RandomAccessFile(tempFile, "rw")
                    if (response.code == 206) {
                        raf.seek(existingSize)
                    } else {
                        raf.setLength(0)
                        savedSize = 0L
                    }

                    val buffer = ByteArray(8192)
                    val source = body.byteStream()
                    var lastEmitTime = 0L

                    while (!cancelled.get()) {
                        val read = source.read(buffer)
                        if (read == -1) break
                        raf.write(buffer, 0, read)
                        savedSize += read
                        progress = if (totalSize > 0) savedSize.toDouble() / totalSize else 0.0

                        val now = System.currentTimeMillis()
                        if (now - lastEmitTime > 500) {
                            lastEmitTime = now
                            OmniInferModelsManager.emitEvent("downloads_changed", mapOf("modelId" to modelId))
                        }
                    }

                    raf.close()
                    source.close()
                    body.closeQuietly()

                    if (!cancelled.get()) {
                        tempFile.renameTo(destFile)
                        Log.i(TAG, "Download complete: $modelId")
                        OmniInferModelsManager.activeDownloads.remove(modelId)
                        OmniInferModelsManager.emitEvent("downloads_changed", mapOf("modelId" to modelId))
                        OmniInferModelsManager.emitEvent("installed_changed", emptyMap())
                    }
                } catch (e: Exception) {
                    if (!cancelled.get()) {
                        Log.e(TAG, "Download failed: $modelId", e)
                        OmniInferModelsManager.activeDownloads.remove(modelId)
                        OmniInferModelsManager.emitEvent("download_error", mapOf(
                            "modelId" to modelId,
                            "error" to (e.message ?: "unknown")
                        ))
                    }
                }
            }
        }
    }

    // ── Helpers ──

    private fun emitEvent(type: String, payload: Map<String, Any?>) {
        eventDispatcher?.invoke(mapOf("type" to type) + payload)
    }

    private fun formatSize(bytes: Long): String {
        return when {
            bytes >= 1_073_741_824 -> "%.1f GB".format(bytes / 1_073_741_824.0)
            bytes >= 1_048_576 -> "%.1f MB".format(bytes / 1_048_576.0)
            bytes >= 1024 -> "%.1f KB".format(bytes / 1024.0)
            else -> "$bytes B"
        }
    }
}
