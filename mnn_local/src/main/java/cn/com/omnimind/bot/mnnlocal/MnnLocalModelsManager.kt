package cn.com.omnimind.bot.mnnlocal

import android.content.Context
import android.net.Uri
import com.alibaba.mls.api.ModelItem
import com.alibaba.mls.api.download.DownloadInfo
import com.alibaba.mls.api.download.DownloadListener
import com.alibaba.mls.api.download.DownloadState
import com.alibaba.mls.api.download.ModelDownloadManager
import com.alibaba.mls.api.source.ModelSources
import com.alibaba.mnnllm.android.benchmark.BenchmarkCallback
import com.alibaba.mnnllm.android.benchmark.BenchmarkErrorCode
import com.alibaba.mnnllm.android.benchmark.BenchmarkProgress
import com.alibaba.mnnllm.android.benchmark.BenchmarkResult
import com.alibaba.mnnllm.android.benchmark.BenchmarkService
import com.alibaba.mnnllm.android.benchmark.RuntimeParameters
import com.alibaba.mnnllm.android.benchmark.TestParameters
import com.alibaba.mnnllm.android.chat.PromptUtils
import com.alibaba.mnnllm.android.chat.model.ChatDataItem
import com.alibaba.mnnllm.android.llm.ChatService
import com.alibaba.mnnllm.android.llm.ChatSession
import com.alibaba.mnnllm.android.llm.GenerateProgressListener
import com.alibaba.mnnllm.android.llm.LlmSession
import com.alibaba.mnnllm.android.model.ModelTypeUtils
import com.alibaba.mnnllm.android.model.ModelUtils
import com.alibaba.mnnllm.android.modelist.ModelItemWrapper
import com.alibaba.mnnllm.android.modelist.ModelListManager
import com.alibaba.mnnllm.android.modelmarket.ModelMarketConfig
import com.alibaba.mnnllm.android.modelmarket.ModelMarketItem
import com.alibaba.mnnllm.android.modelmarket.ModelRepository
import com.alibaba.mnnllm.android.utils.VoiceModelPathUtils
import com.alibaba.mnnllm.api.openai.di.ServiceLocator
import com.alibaba.mnnllm.api.openai.manager.ApiServiceManager
import com.alibaba.mnnllm.api.openai.manager.CurrentModelManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

object MnnLocalModelsManager {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val generationMutex = Mutex()
    private val generationCancelled = AtomicBoolean(false)
    private val downloadListenerLock = Any()

    @Volatile
    private var appContext: Context? = null

    @Volatile
    private var activeSpecialSession: ChatSession? = null

    @Volatile
    private var activeSpecialModelId: String? = null

    @Volatile
    private var activeGenerationModelId: String? = null

    @Volatile
    private var activeRequestId: String? = null

    @Volatile
    private var eventDispatcher: ((Map<String, Any?>) -> Unit)? = null

    @Volatile
    private var downloadListenerRegistered = false

    private val benchmarkStateLock = Any()
    private val benchmarkResults = mutableListOf<Map<String, Any?>>()

    @Volatile
    private var benchmarkStatus: String = "idle"

    @Volatile
    private var benchmarkModelId: String? = null

    @Volatile
    private var benchmarkBackend: String = "cpu"

    @Volatile
    private var benchmarkProgress: Map<String, Any?>? = null

    @Volatile
    private var benchmarkErrorMessage: String = ""

    @Volatile
    private var benchmarkUpdatedAt: Long = 0L

    private val downloadListener = object : DownloadListener {
        override fun onDownloadStart(modelId: String) {
            emitDownloadUpdate(modelId)
        }

        override fun onDownloadProgress(modelId: String, downloadInfo: DownloadInfo) {
            emitDownloadUpdate(modelId, downloadInfo)
        }

        override fun onDownloadFinished(modelId: String, path: String) {
            emitDownloadUpdate(modelId)
            emitSimpleEvent("downloads_changed")
        }

        override fun onDownloadFailed(modelId: String, e: Exception) {
            emitDownloadUpdate(modelId)
            emitSimpleEvent("downloads_changed")
        }

        override fun onDownloadPaused(modelId: String) {
            emitDownloadUpdate(modelId)
            emitSimpleEvent("downloads_changed")
        }

        override fun onDownloadFileRemoved(modelId: String) {
            emitDownloadUpdate(modelId)
            emitSimpleEvent("downloads_changed")
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
        MnnLocalInitializer.initialize(applicationContext as android.app.Application)
        ensureDownloadListenerRegistered(applicationContext)
    }

    fun setEventDispatcher(dispatcher: ((Map<String, Any?>) -> Unit)?) {
        eventDispatcher = dispatcher
    }

    suspend fun ensureInitialized(context: Context? = appContext) {
        val targetContext = context ?: error("MNN local context is not initialized")
        setContext(targetContext)
        syncDownloadSource()
        ModelListManager.setContext(targetContext)
        ModelListManager.initialize(targetContext)
        ModelRepository.initialize()
        MnnLocalConfigStore.syncProviderState(ApiServiceManager.isApiServiceReady())
    }

    fun handleAppOpen(context: Context) {
        setContext(context)
        scope.launch {
            runCatching {
                ensureInitialized(context)
                if (
                    MnnLocalConfigStore.shouldAutoStartOnAppOpen() &&
                    MnnLocalConfigStore.isApiEnabled()
                ) {
                    val modelId = MnnLocalConfigStore.getActiveModelId()
                    if (!modelId.isNullOrBlank() && !ApiServiceManager.isApiServiceRunning()) {
                        ApiServiceManager.startApiService(context, modelId)
                    }
                }
                emitConfigChanged()
            }
        }
    }

    suspend fun getOverview(
        installedQuery: String? = null,
        marketQuery: String? = null,
        marketCategory: String? = null
    ): Map<String, Any?> {
        ensureInitialized()
        return mapOf(
            "config" to getConfig(),
            "installedModels" to listInstalledModels(installedQuery, "all"),
            "market" to listMarketModels(marketQuery, marketCategory, false),
        )
    }

    suspend fun listInstalledModels(
        query: String? = null,
        category: String? = null
    ): List<Map<String, Any?>> {
        ensureInitialized()
        val normalizedQuery = query?.trim()?.lowercase(Locale.getDefault()).orEmpty()
        val normalizedCategory = normalizeCategory(category)
        return installedModels()
            .filter { wrapper ->
                if (normalizedCategory != "all" && detectCategory(wrapper.modelItem) != normalizedCategory) {
                    return@filter false
                }
                if (normalizedQuery.isEmpty()) {
                    return@filter true
                }
                val haystacks = buildList {
                    add(wrapper.displayName)
                    add(wrapper.modelItem.modelId.orEmpty())
                    add(wrapper.modelItem.vendor.orEmpty())
                    addAll(wrapper.modelItem.getTags())
                }
                haystacks.any { it.lowercase(Locale.getDefault()).contains(normalizedQuery) }
            }
            .sortedWith(
                compareByDescending<ModelItemWrapper> { it.isPinned }
                    .thenByDescending { it.lastChatTime }
                    .thenByDescending { it.downloadTime }
                    .thenBy { it.displayName.lowercase(Locale.getDefault()) }
            )
            .map { wrapper -> wrapper.toInstalledMap() }
    }

    suspend fun refreshInstalledModels(): List<Map<String, Any?>> {
        ensureInitialized()
        ModelListManager.notifyModelListMayChange(ModelListManager.ChangeReason.MANUAL_REFRESH)
        return listInstalledModels()
    }

    suspend fun listMarketModels(
        query: String? = null,
        category: String? = null,
        refresh: Boolean = false
    ): Map<String, Any?> {
        ensureInitialized()
        val config = loadMarketConfig(refresh)
        val normalizedCategory = normalizeCategory(category)
        val normalizedQuery = query?.trim()?.lowercase(Locale.getDefault()).orEmpty()
        val allItems = when (normalizedCategory) {
            "asr" -> config.asrModels
            "tts" -> config.ttsModels
            "libs" -> config.libs
            "all", "llm" -> if (normalizedCategory == "llm") config.llmModels else {
                config.llmModels + config.asrModels + config.ttsModels + config.libs
            }
            else -> config.llmModels
        }
        val filtered = allItems.filter { item ->
            if (normalizedQuery.isEmpty()) {
                return@filter true
            }
            buildList {
                add(item.modelName)
                add(item.modelId)
                add(item.vendor)
                add(item.description.orEmpty())
                addAll(item.tags)
                addAll(item.extraTags)
            }.any { value ->
                value.lowercase(Locale.getDefault()).contains(normalizedQuery)
            }
        }
        return mapOf(
            "source" to MnnLocalConfigStore.getDownloadProviderString(),
            "availableSources" to ModelSources.sourceList,
            "category" to normalizedCategory,
            "models" to filtered.map { it.toMarketMap() },
        )
    }

    suspend fun refreshMarketModels(
        query: String? = null,
        category: String? = null
    ): Map<String, Any?> {
        return listMarketModels(query = query, category = category, refresh = true)
    }

    fun getConfig(): Map<String, Any?> {
        val context = appContext ?: error("MNN local context is not initialized")
        val serviceInfo = ApiServiceManager.getServerInfo()
        val voiceStatus = VoiceModelPathUtils.checkVoiceModelsStatus(context)
        val installed = ModelListManager.getCurrentModels().orEmpty()
        return mapOf(
            "autoStartOnAppOpen" to MnnLocalConfigStore.shouldAutoStartOnAppOpen(),
            "apiEnabled" to MnnLocalConfigStore.isApiEnabled(),
            "apiLanEnabled" to MnnLocalConfigStore.isLanEnabled(),
            "apiRunning" to ApiServiceManager.isApiServiceRunning(),
            "apiReady" to ApiServiceManager.isApiServiceReady(),
            "apiState" to ApiServiceManager.getServerState().name.lowercase(Locale.getDefault()),
            "apiHost" to serviceInfo.host,
            "apiPort" to MnnLocalConfigStore.getPort(),
            "apiKey" to MnnLocalConfigStore.getApiKey(),
            "baseUrl" to MnnLocalConfigStore.getLoopbackBaseUrl(),
            "activeModelId" to (CurrentModelManager.getCurrentModelId()
                ?: MnnLocalConfigStore.getActiveModelId()).orEmpty(),
            "speechRecognitionProvider" to MnnLocalConfigStore.getSpeechRecognitionProvider().storageValue,
            "defaultAsrModelId" to MnnLocalConfigStore.getDefaultAsrModelId().orEmpty(),
            "defaultTtsModelId" to MnnLocalConfigStore.getDefaultTtsModelId().orEmpty(),
            "downloadProvider" to MnnLocalConfigStore.getDownloadProviderString(),
            "availableSources" to ModelSources.sourceList,
            "voiceReady" to voiceStatus.first,
            "voiceStatusText" to voiceStatus.second,
            "installedAsrModels" to installed
                .filter { detectCategory(it.modelItem) == "asr" }
                .map { it.toInstalledMap() },
            "installedTtsModels" to installed
                .filter { detectCategory(it.modelItem) == "tts" }
                .map { it.toInstalledMap() },
        )
    }

    fun saveConfig(arguments: Map<*, *>): Map<String, Any?> {
        var downloadProviderChanged = false
        arguments["autoStartOnAppOpen"]?.let {
            MnnLocalConfigStore.setAutoStartOnAppOpen(it == true)
        }
        arguments["apiLanEnabled"]?.let {
            MnnLocalConfigStore.setLanEnabled(it == true)
        }
        arguments["apiPort"]?.let {
            val port = (it as? Number)?.toInt()
            if (port != null && port > 0) {
                MnnLocalConfigStore.setPort(port)
            }
        }
        arguments["apiKey"]?.let {
            MnnLocalConfigStore.setApiKey(it.toString())
        }
        arguments["activeModelId"]?.let {
            MnnLocalConfigStore.setActiveModelId(it.toString())
        }
        arguments["defaultAsrModelId"]?.let {
            MnnLocalConfigStore.setDefaultAsrModelId(it.toString())
        }
        arguments["defaultTtsModelId"]?.let {
            MnnLocalConfigStore.setDefaultTtsModelId(it.toString())
        }
        arguments["speechRecognitionProvider"]?.let {
            MnnLocalConfigStore.setSpeechRecognitionProvider(
                SpeechRecognitionProvider.fromStorageValue(it.toString())
            )
        }
        arguments["downloadProvider"]?.let {
            val nextProvider = it.toString()
            if (nextProvider != MnnLocalConfigStore.getDownloadProviderString()) {
                MnnLocalConfigStore.setDownloadProviderString(nextProvider)
                downloadProviderChanged = true
            }
        }
        syncDownloadSource()
        if (downloadProviderChanged) {
            ModelRepository.clear()
        }
        emitConfigChanged()
        return getConfig()
    }

    fun setActiveModel(modelId: String?): Map<String, Any?> {
        MnnLocalConfigStore.setActiveModelId(modelId)
        if (!modelId.isNullOrBlank()) {
            CurrentModelManager.setCurrentModelId(modelId)
        }
        emitConfigChanged()
        return getConfig()
    }

    fun startApiService(modelId: String? = null): Map<String, Any?> {
        val context = appContext ?: error("MNN local context is not initialized")
        val resolvedModelId = modelId?.takeIf { it.isNotBlank() } ?: MnnLocalConfigStore.getActiveModelId()
        if (!resolvedModelId.isNullOrBlank()) {
            MnnLocalConfigStore.setActiveModelId(resolvedModelId)
            CurrentModelManager.setCurrentModelId(resolvedModelId)
        }
        MnnLocalConfigStore.setApiEnabled(true)
        ApiServiceManager.startApiService(context, resolvedModelId)
        MnnLocalConfigStore.syncProviderState(ApiServiceManager.isApiServiceReady())
        emitConfigChanged()
        return getConfig()
    }

    fun stopApiService(): Map<String, Any?> {
        val context = appContext ?: error("MNN local context is not initialized")
        ApiServiceManager.stopApiService(context)
        MnnLocalConfigStore.setApiEnabled(false)
        MnnLocalConfigStore.syncProviderState(ApiServiceManager.isApiServiceReady())
        emitConfigChanged()
        return getConfig()
    }

    fun startDownload(modelId: String) {
        val context = appContext ?: error("MNN local context is not initialized")
        ensureDownloadListenerRegistered(context)
        ModelDownloadManager.getInstance(context).startDownload(modelId)
        emitDownloadUpdate(modelId)
    }

    fun pauseDownload(modelId: String) {
        val context = appContext ?: error("MNN local context is not initialized")
        ensureDownloadListenerRegistered(context)
        ModelDownloadManager.getInstance(context).pauseDownload(modelId)
        emitDownloadUpdate(modelId)
    }

    suspend fun deleteModel(modelId: String): List<Map<String, Any?>> {
        val context = appContext ?: error("MNN local context is not initialized")
        ModelDownloadManager.getInstance(context).deleteModel(modelId)
        if (activeSpecialModelId == modelId) {
            activeSpecialSession?.release()
            activeSpecialSession = null
            activeSpecialModelId = null
        }
        if (activeGenerationModelId == modelId) {
            resetInferenceSession()
        }
        ModelListManager.notifyModelListMayChange(ModelListManager.ChangeReason.MODEL_DELETED)
        emitSimpleEvent("downloads_changed")
        return listInstalledModels()
    }

    fun resetInferenceSession() {
        runCatching {
            ServiceLocator.getLlmRuntimeController().releaseSession()
        }
        runCatching {
            activeSpecialSession?.release()
        }
        activeSpecialSession = null
        activeSpecialModelId = null
        activeGenerationModelId = null
        activeRequestId = null
        generationCancelled.set(false)
        emitSimpleEvent("inference_reset")
    }

    suspend fun startGeneration(arguments: Map<*, *>): Map<String, Any?> {
        ensureInitialized()
        val context = appContext ?: error("MNN local context is not initialized")
        val modelId = arguments["modelId"]?.toString()?.takeIf { it.isNotBlank() }
            ?: MnnLocalConfigStore.getActiveModelId()
            ?: installedModels().firstOrNull()?.modelItem?.modelId
            ?: error("No installed model available")
        val wrapper = findInstalledModel(modelId) ?: error("Model not found: $modelId")
        val modelName = wrapper.displayName.ifBlank {
            ModelUtils.getModelName(modelId) ?: modelId
        }
        val requestId = UUID.randomUUID().toString()
        val prompt = arguments["prompt"]?.toString().orEmpty()
        val imagePath = arguments["imagePath"]?.toString()?.takeIf { it.isNotBlank() }
        val audioPath = arguments["audioPath"]?.toString()?.takeIf { it.isNotBlank() }
        val videoPath = arguments["videoPath"]?.toString()?.takeIf { it.isNotBlank() }
        val enableAudioOutput = arguments["enableAudioOutput"] == true
        val steps = (arguments["steps"] as? Number)?.toInt() ?: 20
        val seed = (arguments["seed"] as? Number)?.toInt() ?: 1024
        val useCfg = arguments["useCfg"] != false
        val cfgScale = (arguments["cfgScale"] as? Number)?.toFloat() ?: 4.5f

        generationCancelled.set(false)
        activeRequestId = requestId
        activeGenerationModelId = modelId
        MnnLocalConfigStore.setActiveModelId(modelId)
        CurrentModelManager.setCurrentModelId(modelId)
        emitEvent(
            "generation_started",
            mapOf("requestId" to requestId, "modelId" to modelId, "modelName" to modelName)
        )

        scope.launch(Dispatchers.IO) {
            generationMutex.withLock {
                runCatching {
                    val session = resolveSession(wrapper)
                    if (session is LlmSession) {
                        session.setEnableAudioOutput(enableAudioOutput)
                    }
                    val result = if (ModelTypeUtils.isDiffusionModel(modelName) || ModelTypeUtils.isSanaModel(modelName)) {
                        val outputPath = arguments["outputPath"]?.toString()?.takeIf { it.isNotBlank() }
                            ?: defaultOutputPath(context, modelId)
                        session.generate(
                            prompt,
                            hashMapOf(
                                "output" to outputPath,
                                "iterNum" to steps,
                                "randomSeed" to seed,
                                "imageInput" to (imagePath ?: ""),
                                "useCfg" to useCfg,
                                "cfgScale" to cfgScale,
                            ),
                            progressListener(requestId)
                        )
                    } else {
                        val inputPrompt = buildPrompt(
                            prompt = prompt,
                            imagePath = imagePath,
                            audioPath = audioPath,
                            videoPath = videoPath,
                        )
                        session.generate(
                            inputPrompt,
                            emptyMap(),
                            progressListener(requestId)
                        )
                    }
                    val finalCancelled = generationCancelled.get()
                    if (finalCancelled) {
                        runCatching { session.reset() }
                        emitEvent(
                            "generation_cancelled",
                            mapOf("requestId" to requestId, "modelId" to modelId)
                        )
                    } else {
                        emitEvent(
                            "generation_completed",
                            mapOf(
                                "requestId" to requestId,
                                "modelId" to modelId,
                                "result" to sanitizeMetrics(result),
                                "metricsText" to ModelUtils.generateBenchMarkString(result),
                            )
                        )
                    }
                }.onFailure { error ->
                    emitEvent(
                        "generation_error",
                        mapOf(
                            "requestId" to requestId,
                            "modelId" to modelId,
                            "message" to (error.message ?: "unknown_error"),
                        )
                    )
                }
                generationCancelled.set(false)
            }
        }

        return mapOf(
            "requestId" to requestId,
            "modelId" to modelId,
            "modelName" to modelName,
        )
    }

    fun stopGeneration(): Boolean {
        generationCancelled.set(true)
        emitSimpleEvent("generation_stop_requested")
        return true
    }

    fun getBenchmarkState(): Map<String, Any?> {
        val resultsSnapshot = synchronized(benchmarkStateLock) {
            benchmarkResults.toList()
        }
        return mapOf(
            "running" to (benchmarkStatus == "running"),
            "status" to benchmarkStatus,
            "modelId" to benchmarkModelId.orEmpty(),
            "backend" to benchmarkBackend,
            "progress" to benchmarkProgress,
            "results" to resultsSnapshot,
            "lastResult" to resultsSnapshot.lastOrNull(),
            "errorMessage" to benchmarkErrorMessage,
            "updatedAt" to benchmarkUpdatedAt,
        )
    }

    suspend fun startBenchmark(arguments: Map<*, *>): Map<String, Any?> {
        ensureInitialized()
        val context = appContext ?: error("MNN local context is not initialized")
        val modelId = arguments["modelId"]?.toString()?.takeIf { it.isNotBlank() }
            ?: MnnLocalConfigStore.getActiveModelId()
            ?: error("No active local model available")
        val wrapper = findInstalledModel(modelId) ?: error("Model not found: $modelId")
        if (detectCategory(wrapper.modelItem) != "llm") {
            error("Benchmark currently supports installed LLM models only")
        }

        val backend = arguments["backend"]?.toString()
            ?.trim()
            ?.lowercase(Locale.getDefault())
            ?.takeIf { it == "cpu" || it == "opencl" }
            ?: "cpu"
        val backendId = if (backend == "opencl") 3 else 0
        val threads = ((arguments["threads"] as? Number)?.toInt() ?: 4).coerceAtLeast(1)
        val repeat = ((arguments["repeat"] as? Number)?.toInt() ?: 5).coerceAtLeast(1)
        val nPrompt = ((arguments["nPrompt"] as? Number)?.toInt() ?: 512).coerceAtLeast(0)
        val nGenerate = ((arguments["nGenerate"] as? Number)?.toInt() ?: 128).coerceAtLeast(0)
        val kvCache = if (arguments["kvCache"] == true) "true" else "false"
        val useMmap = arguments["useMmap"] == true

        synchronized(benchmarkStateLock) {
            if (benchmarkStatus == "running" || BenchmarkService.getInstance().isBenchmarkRunning()) {
                error("Benchmark is already running")
            }
            benchmarkStatus = "running"
            benchmarkModelId = modelId
            benchmarkBackend = backend
            benchmarkProgress = mapOf(
                "progress" to 0,
                "statusMessage" to "正在初始化 Benchmark…",
                "progressType" to "initializing",
                "currentIteration" to 0,
                "totalIterations" to 0,
                "nPrompt" to nPrompt,
                "nGenerate" to nGenerate,
                "runTimeSeconds" to 0f,
                "prefillTimeSeconds" to 0f,
                "decodeTimeSeconds" to 0f,
                "prefillSpeed" to 0f,
                "decodeSpeed" to 0f,
            )
            benchmarkErrorMessage = ""
            benchmarkResults.clear()
            benchmarkUpdatedAt = System.currentTimeMillis()
        }

        emitEvent(
            "benchmark_started",
            mapOf("state" to getBenchmarkState())
        )

        val benchmarkService = BenchmarkService.getInstance()
        val initialized = benchmarkService.initializeModel(
            modelId = modelId,
            backendType = backend,
        )
        if (!initialized) {
            finalizeBenchmark(
                status = "error",
                errorMessage = "Benchmark 模型初始化失败",
                eventType = "benchmark_error"
            )
            error("Failed to initialize benchmark model")
        }

        benchmarkService.runBenchmark(
            context = context,
            modelId = modelId,
            callback = object : BenchmarkCallback {
                override fun onProgress(progress: BenchmarkProgress) {
                    synchronized(benchmarkStateLock) {
                        benchmarkProgress = progress.toMap()
                        benchmarkUpdatedAt = System.currentTimeMillis()
                    }
                    emitEvent(
                        "benchmark_progress",
                        mapOf(
                            "progress" to progress.toMap(),
                            "state" to getBenchmarkState(),
                        )
                    )
                }

                override fun onComplete(result: BenchmarkResult) {
                    val resultMap = result.toMap(backend = benchmarkBackend, repeat = repeat)
                    synchronized(benchmarkStateLock) {
                        benchmarkResults.add(resultMap)
                        benchmarkUpdatedAt = System.currentTimeMillis()
                    }
                    emitEvent(
                        "benchmark_result",
                        mapOf(
                            "result" to resultMap,
                            "state" to getBenchmarkState(),
                        )
                    )
                }

                override fun onBenchmarkError(errorCode: Int, message: String) {
                    if (errorCode == BenchmarkErrorCode.BENCHMARK_STOPPED) {
                        finalizeBenchmark(
                            status = "stopped",
                            errorMessage = message,
                            eventType = "benchmark_stopped"
                        )
                    } else {
                        finalizeBenchmark(
                            status = "error",
                            errorMessage = message,
                            eventType = "benchmark_error"
                        )
                    }
                }
            },
            runtimeParams = RuntimeParameters(
                model = listOf(modelId),
                backends = listOf(backendId),
                threads = listOf(threads),
                useMmap = useMmap,
                power = listOf(0),
                precision = listOf(2),
                memory = listOf(2),
                dynamicOption = listOf(0),
            ),
            testParams = TestParameters(
                nPrompt = listOf(nPrompt),
                nGenerate = listOf(nGenerate),
                nPrompGen = listOf(Pair(nPrompt, nGenerate)),
                nRepeat = listOf(repeat),
                kvCache = kvCache,
                loadTime = "false",
            )
        )

        scope.launch(Dispatchers.IO) {
            while (BenchmarkService.getInstance().isBenchmarkRunning()) {
                delay(500)
            }
            finalizeBenchmark(
                status = "completed",
                errorMessage = "",
                eventType = "benchmark_finished"
            )
        }

        return getBenchmarkState()
    }

    fun stopBenchmark(): Map<String, Any?> {
        BenchmarkService.getInstance().stopBenchmark()
        emitEvent(
            "benchmark_stop_requested",
            mapOf("state" to getBenchmarkState())
        )
        return getBenchmarkState()
    }

    fun clear() {
        eventDispatcher = null
        runCatching { BenchmarkService.getInstance().release() }
        resetInferenceSession()
    }

    private fun resolveSession(wrapper: ModelItemWrapper): ChatSession {
        val modelId = wrapper.modelItem.modelId ?: error("modelId is missing")
        val modelName = wrapper.displayName.ifBlank {
            ModelUtils.getModelName(modelId) ?: modelId
        }
        if (ModelTypeUtils.isDiffusionModel(modelName) || ModelTypeUtils.isSanaModel(modelName)) {
            if (activeSpecialSession != null && activeSpecialModelId == modelId) {
                return activeSpecialSession!!
            }
            activeSpecialSession?.release()
            val configPath = ModelUtils.getConfigPathForModel(wrapper.modelItem)
                ?: wrapper.modelItem.localPath
                ?: error("Model config not found for $modelId")
            val session = ChatService.provide().createSession(
                modelId = modelId,
                modelName = modelName,
                sessionIdParam = "local_models_${System.currentTimeMillis()}",
                historyList = null,
                configPath = configPath,
                useNewConfig = false,
                useCustomConfig = true,
            )
            session.setKeepHistory(true)
            session.load()
            activeSpecialSession = session
            activeSpecialModelId = modelId
            return session
        }

        val configPath = ModelUtils.getConfigPathForModel(wrapper.modelItem)
        val ensureResult = ServiceLocator.getLlmRuntimeController().ensureSession(
            modelId = modelId,
            forceReload = false,
            useAppConfig = true,
            configPath = configPath,
            sessionId = "local_models_${System.currentTimeMillis()}",
            historyList = null,
            deferLoad = true,
        )
        val session = ensureResult.session
            ?: error(ensureResult.reason ?: "Failed to prepare session")
        if (session is LlmSession && !session.isModelLoaded()) {
            session.load()
        }
        return session
    }

    private fun progressListener(requestId: String): GenerateProgressListener {
        return object : GenerateProgressListener {
            override fun onProgress(progress: String?): Boolean {
                if (progress != null) {
                    emitEvent(
                        "generation_chunk",
                        mapOf("requestId" to requestId, "text" to progress)
                    )
                }
                return generationCancelled.get()
            }
        }
    }

    private suspend fun installedModels(): List<ModelItemWrapper> {
        ensureInitialized()
        return ModelListManager.getCurrentModels().orEmpty()
    }

    private suspend fun findInstalledModel(modelId: String): ModelItemWrapper? {
        return installedModels().firstOrNull { it.modelItem.modelId == modelId }
    }

    private fun buildPrompt(
        prompt: String,
        imagePath: String?,
        audioPath: String?,
        videoPath: String?
    ): String {
        if (!audioPath.isNullOrBlank()) {
            val item = ChatDataItem.createAudioInputData(
                null,
                prompt,
                audioPath,
                0f
            )
            return PromptUtils.generateUserPrompt(item)
        }
        if (!imagePath.isNullOrBlank()) {
            val item = ChatDataItem.createImageInputData(
                null,
                prompt,
                listOf(Uri.fromFile(File(imagePath)))
            )
            return PromptUtils.generateUserPrompt(item)
        }
        if (!videoPath.isNullOrBlank()) {
            val item = ChatDataItem.createVideoInputData(null, prompt, videoPath)
            return PromptUtils.generateUserPrompt(item)
        }
        return prompt
    }

    private fun normalizeCategory(category: String?): String {
        return when (category?.trim()?.lowercase(Locale.getDefault())) {
            null, "", "all" -> "all"
            "llm" -> "llm"
            "asr" -> "asr"
            "tts" -> "tts"
            "libs" -> "libs"
            "diffusion" -> "diffusion"
            else -> "all"
        }
    }

    private fun detectCategory(modelItem: ModelItem): String {
        val tags = modelItem.getTags()
        val modelId = modelItem.modelId.orEmpty()
        val modelName = modelItem.modelName ?: ModelUtils.getModelName(modelId).orEmpty()
        return when {
            ModelTypeUtils.isAsrModelByTags(tags) -> "asr"
            ModelTypeUtils.isTtsModelByTags(tags) || ModelTypeUtils.isTtsModel(modelName) -> "tts"
            modelItem.modelMarketItem is ModelMarketItem &&
                ((modelItem.modelMarketItem as ModelMarketItem).categories.any {
                    it.equals("libs", ignoreCase = true)
                }) -> "libs"
            ModelTypeUtils.isDiffusionModel(modelName) -> "diffusion"
            else -> "llm"
        }
    }

    private fun ModelItemWrapper.toInstalledMap(): Map<String, Any?> {
        val modelId = modelItem.modelId.orEmpty()
        val downloadInfo = contextDownloadManager()?.getDownloadInfo(modelId)
        val category = detectCategory(modelItem)
        return mapOf(
            "id" to modelId,
            "name" to displayName,
            "path" to modelItem.localPath.orEmpty(),
            "source" to sourceTag.orEmpty(),
            "category" to category,
            "isLocal" to isLocal,
            "isPinned" to isPinned,
            "hasUpdate" to (hasUpdate || (downloadInfo?.hasUpdate == true)),
            "downloadSize" to downloadSize,
            "formattedSize" to formattedSize,
            "lastUsedAt" to lastChatTime,
            "downloadedAt" to downloadTime,
            "active" to (MnnLocalConfigStore.getActiveModelId() == modelId ||
                CurrentModelManager.getCurrentModelId() == modelId),
            "tags" to modelItem.getTags(),
            "vendor" to modelItem.vendor.orEmpty(),
            "download" to downloadInfo?.toMap(),
        )
    }

    private fun ModelMarketItem.toMarketMap(): Map<String, Any?> {
        val downloadInfo = contextDownloadManager()?.getDownloadInfo(modelId)
        val category = when {
            categories.any { it.equals("libs", ignoreCase = true) } -> "libs"
            ModelTypeUtils.isAsrModelByTags(tags) -> "asr"
            ModelTypeUtils.isTtsModelByTags(tags) -> "tts"
            ModelTypeUtils.isDiffusionModel(modelName) -> "diffusion"
            else -> "llm"
        }
        return mapOf(
            "id" to modelId,
            "name" to modelName,
            "vendor" to vendor,
            "description" to description.orEmpty(),
            "category" to category,
            "tags" to tags,
            "extraTags" to extraTags,
            "fileSize" to fileSize,
            "sizeB" to sizeB,
            "source" to currentSource,
            "repoPath" to currentRepoPath,
            "download" to downloadInfo?.toMap(),
        )
    }

    private fun contextDownloadManager(): ModelDownloadManager? {
        return appContext?.let { ModelDownloadManager.getInstance(it) }
    }

    private fun sanitizeMetrics(metrics: HashMap<String, Any>): Map<String, Any?> {
        return metrics.entries.associate { (key, value) ->
            key to when (value) {
                is Int, is Long, is Double, is Float, is Boolean, is String -> value
                else -> value?.toString()
            }
        }
    }

    private fun syncDownloadSource() {
        val provider = MnnLocalConfigStore.getDownloadProviderString()
        val sourceType = when (provider) {
            ModelSources.sourceHuffingFace -> ModelSources.ModelSourceType.HUGGING_FACE
            ModelSources.sourceModelers -> ModelSources.ModelSourceType.MODELERS
            else -> ModelSources.ModelSourceType.MODEL_SCOPE
        }
        ModelSources.setSourceType(sourceType)
    }

    private suspend fun loadMarketConfig(refresh: Boolean): ModelMarketConfig {
        return runCatching {
            if (refresh) {
                ModelRepository.forceRefresh()
            }
            ModelRepository.getMarketDataSuspend()
        }.getOrElse {
            ModelRepository.clear()
            ModelRepository.initialize()
                ?: ModelRepository.loadCachedOrAssets()
                ?: throw IllegalStateException("Failed to load model market", it)
        }
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

    private fun defaultOutputPath(context: Context, modelId: String): String {
        val dir = File(context.cacheDir, "mnn_outputs").apply { mkdirs() }
        val safeId = modelId.replace("/", "_")
        return File(dir, "${safeId}_${System.currentTimeMillis()}.png").absolutePath
    }

    private fun finalizeBenchmark(
        status: String,
        errorMessage: String,
        eventType: String
    ) {
        val shouldEmit = synchronized(benchmarkStateLock) {
            if (benchmarkStatus != "running") {
                false
            } else {
                benchmarkStatus = status
                benchmarkErrorMessage = errorMessage
                benchmarkUpdatedAt = System.currentTimeMillis()
                if (status == "completed") {
                    benchmarkProgress = (benchmarkProgress ?: emptyMap()) + mapOf(
                        "progress" to 100,
                        "progressType" to "completed",
                    )
                }
                true
            }
        }
        runCatching { BenchmarkService.getInstance().release() }
        if (shouldEmit) {
            emitEvent(
                eventType,
                mapOf(
                    "message" to errorMessage,
                    "state" to getBenchmarkState(),
                )
            )
        }
    }

    private fun emitConfigChanged() {
        emitEvent("config_changed", mapOf("config" to getConfig()))
    }

    private fun emitSimpleEvent(type: String) {
        emitEvent(type, emptyMap())
    }

    private fun emitDownloadUpdate(
        modelId: String,
        downloadInfo: DownloadInfo? = contextDownloadManager()?.getDownloadInfo(modelId)
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

    private fun com.alibaba.mls.api.download.DownloadInfo.toMap(): Map<String, Any?> {
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
            "errorMessage" to errorMessage,
            "progressStage" to progressStage,
            "currentFile" to currentFile,
            "downloadedTime" to downloadedTime,
            "hasUpdate" to hasUpdate,
        )
    }

    private fun BenchmarkProgress.toMap(): Map<String, Any?> {
        return mapOf(
            "progress" to progress,
            "statusMessage" to statusMessage,
            "progressType" to progressType.name.lowercase(Locale.getDefault()),
            "currentIteration" to currentIteration,
            "totalIterations" to totalIterations,
            "nPrompt" to nPrompt,
            "nGenerate" to nGenerate,
            "runTimeSeconds" to runTimeSeconds,
            "prefillTimeSeconds" to prefillTimeSeconds,
            "decodeTimeSeconds" to decodeTimeSeconds,
            "prefillSpeed" to prefillSpeed,
            "decodeSpeed" to decodeSpeed,
        )
    }

    private fun BenchmarkResult.toMap(backend: String, repeat: Int): Map<String, Any?> {
        val prefillSpeeds = if (testInstance.nPrompt > 0) {
            testInstance.prefillUs.map { costUs ->
                if (costUs <= 0L) 0.0 else 1_000_000.0 * testInstance.nPrompt / costUs
            }
        } else {
            emptyList()
        }
        val decodeSpeeds = if (testInstance.nGenerate > 0) {
            testInstance.decodeUs.map { costUs ->
                if (costUs <= 0L) 0.0 else 1_000_000.0 * testInstance.nGenerate / costUs
            }
        } else {
            emptyList()
        }
        return mapOf(
            "success" to success,
            "errorMessage" to errorMessage.orEmpty(),
            "backend" to backend,
            "repeat" to repeat,
            "modelId" to benchmarkModelId.orEmpty(),
            "nPrompt" to testInstance.nPrompt,
            "nGenerate" to testInstance.nGenerate,
            "threads" to testInstance.threads,
            "useMmap" to testInstance.useMmap,
            "prefillUs" to testInstance.prefillUs,
            "decodeUs" to testInstance.decodeUs,
            "prefillSpeedAvg" to prefillSpeeds.averageOrZero(),
            "decodeSpeedAvg" to decodeSpeeds.averageOrZero(),
            "prefillSpeedSamples" to prefillSpeeds,
            "decodeSpeedSamples" to decodeSpeeds,
            "title" to "PP ${testInstance.nPrompt} / TG ${testInstance.nGenerate}",
        )
    }

    private fun List<Double>.averageOrZero(): Double {
        return if (isEmpty()) 0.0 else average()
    }
}
