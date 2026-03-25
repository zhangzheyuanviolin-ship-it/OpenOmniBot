package cn.com.omnimind.bot.agent

import android.content.Context
import cn.com.omnimind.baselib.llm.ModelProviderConfigStore
import cn.com.omnimind.baselib.llm.ModelSceneRegistry
import cn.com.omnimind.baselib.llm.SceneModelBindingStore
import cn.com.omnimind.baselib.util.OmniLog
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.tencent.mmkv.MMKV
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.concurrent.TimeUnit
import kotlin.math.sqrt

data class WorkspaceMemoryEmbeddingConfig(
    val enabled: Boolean,
    val configured: Boolean,
    val sceneId: String,
    val providerProfileId: String?,
    val providerProfileName: String?,
    val modelId: String?,
    val apiBase: String?,
    val hasApiKey: Boolean
)

data class WorkspaceMemorySearchHit(
    val id: String,
    val text: String,
    val source: String,
    val date: String?,
    val score: Double
)

data class WorkspaceMemorySearchResult(
    val query: String,
    val usedEmbedding: Boolean,
    val fallbackLexical: Boolean,
    val hits: List<WorkspaceMemorySearchHit>
)

data class WorkspaceMemoryPromptContext(
    val soul: String,
    val longTermMemory: String,
    val todayShortMemory: String
)

data class WorkspaceMemoryRollupStatus(
    val enabled: Boolean,
    val lastRunAtMillis: Long?,
    val lastRunSummary: String?
)

private data class MemoryChunk(
    val id: String,
    val source: String,
    val date: String?,
    val text: String
)

private data class MemoryIndexEntry(
    val id: String,
    val source: String,
    val date: String?,
    val text: String,
    val embedding: List<Double> = emptyList(),
    val updatedAt: Long = System.currentTimeMillis()
)

class WorkspaceMemoryService(
    private val context: Context,
    private val workspaceManager: AgentWorkspaceManager = AgentWorkspaceManager(context)
) {
    companion object {
        const val SCENE_MEMORY_EMBEDDING = "scene.memory.embedding"
        const val SCENE_MEMORY_ROLLUP = "scene.memory.rollup"

        private const val TAG = "WorkspaceMemoryService"
        private const val KEY_EMBEDDING_ENABLED = "workspace_memory_embedding_enabled_v1"
        private const val KEY_ROLLUP_ENABLED = "workspace_memory_rollup_enabled_v1"
        private const val KEY_ROLLUP_LAST_RUN_AT = "workspace_memory_rollup_last_run_at_v1"
        private const val KEY_ROLLUP_LAST_SUMMARY = "workspace_memory_rollup_last_summary_v1"
    }

    private val gson = Gson()
    private val mmkv: MMKV? = MMKV.defaultMMKV()
    private val httpClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    fun ensureInitialized() {
        workspaceManager.ensureRuntimeDirectories()
    }

    fun readSoul(): String {
        ensureInitialized()
        return workspaceManager.soulMarkdownFile().readText()
    }

    fun writeSoul(content: String) {
        ensureInitialized()
        workspaceManager.soulMarkdownFile().writeText(content.trimEnd() + "\n")
    }

    fun readLongTermMemory(): String {
        ensureInitialized()
        return workspaceManager.longTermMemoryMarkdownFile().readText()
    }

    fun writeLongTermMemory(content: String) {
        ensureInitialized()
        workspaceManager.longTermMemoryMarkdownFile().writeText(content.trimEnd() + "\n")
    }

    fun readDailyMemory(date: LocalDate = LocalDate.now()): String {
        ensureInitialized()
        val file = workspaceManager.dailyShortMemoryFile(date)
        if (!file.exists()) {
            return ""
        }
        return file.readText()
    }

    fun appendDailyMemory(
        text: String,
        date: LocalDate = LocalDate.now()
    ): File {
        ensureInitialized()
        val normalized = text.trim()
        require(normalized.isNotEmpty()) { "memory text is empty" }
        val file = workspaceManager.dailyShortMemoryFile(date)
        if (!file.exists()) {
            file.parentFile?.mkdirs()
            file.writeText(
                "# ${date.format(DateTimeFormatter.ISO_LOCAL_DATE)} Daily Memory\n\n"
            )
        }
        val timestamp = DateTimeFormatter.ofPattern("HH:mm:ss")
            .format(LocalDateTime.now())
        file.appendText("- [$timestamp] $normalized\n")
        return file
    }

    fun upsertLongTermMemory(text: String): Boolean {
        ensureInitialized()
        val normalized = text.trim()
        require(normalized.isNotEmpty()) { "memory text is empty" }
        val file = workspaceManager.longTermMemoryMarkdownFile()
        val current = file.readText()
        val existing = current.lineSequence()
            .map { it.trim() }
            .filter { it.startsWith("- ") }
            .map { it.removePrefix("- ").trim() }
            .map { normalizeText(it) }
            .toSet()
        if (existing.contains(normalizeText(normalized))) {
            return false
        }
        file.appendText("- $normalized\n")
        return true
    }

    fun buildPromptContext(
        maxLongChars: Int = 2400,
        maxDailyChars: Int = 1400
    ): WorkspaceMemoryPromptContext {
        ensureInitialized()
        val soul = readSoul().trim()
        val longMemory = truncateText(
            readLongTermMemory().trim(),
            maxLongChars
        )
        val todayDaily = truncateText(
            summarizeTodayShortMemory(),
            maxDailyChars
        )
        return WorkspaceMemoryPromptContext(
            soul = soul,
            longTermMemory = longMemory,
            todayShortMemory = todayDaily
        )
    }

    fun searchMemory(query: String, limit: Int = 8): WorkspaceMemorySearchResult {
        ensureInitialized()
        val normalizedQuery = query.trim()
        require(normalizedQuery.isNotEmpty()) { "query is empty" }
        val embeddingConfig = resolveEmbeddingConfig()
        val chunks = collectChunks()
        val index = refreshAndLoadIndex(chunks, embeddingConfig)
        val queryEmbedding = if (embeddingConfig.configured) {
            runCatching { requestEmbedding(embeddingConfig, normalizedQuery) }
                .onFailure {
                    OmniLog.w(TAG, "embedding query failed: ${it.message}")
                }
                .getOrNull()
        } else {
            null
        }
        val usedEmbedding = queryEmbedding != null

        val scored = index.map { entry ->
            val lexical = lexicalScore(normalizedQuery, entry.text)
            val semantic = if (queryEmbedding != null && entry.embedding.isNotEmpty()) {
                cosineSimilarity(queryEmbedding, entry.embedding)
            } else {
                0.0
            }
            val score = if (usedEmbedding) {
                semantic * 0.82 + lexical * 0.18
            } else {
                lexical
            }
            WorkspaceMemorySearchHit(
                id = entry.id,
                text = entry.text,
                source = entry.source,
                date = entry.date,
                score = score
            )
        }.sortedByDescending { it.score }
            .take(limit.coerceIn(1, 20))
            .filter { it.score > 0.01 }

        return WorkspaceMemorySearchResult(
            query = normalizedQuery,
            usedEmbedding = usedEmbedding,
            fallbackLexical = !usedEmbedding,
            hits = scored
        )
    }

    fun rollupDay(date: LocalDate = LocalDate.now()): Map<String, Any?> {
        ensureInitialized()
        val dailyFile = workspaceManager.dailyShortMemoryFile(date)
        if (!dailyFile.exists()) {
            saveRollupStatus("无当日短期记忆，跳过整理。")
            return mapOf(
                "success" to true,
                "date" to date.toString(),
                "summary" to "无当日短期记忆，跳过整理。",
                "longTermWrites" to 0
            )
        }
        val content = dailyFile.readText()
        val lines = content.lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .filterNot { it.startsWith("#") }
            .toList()

        if (lines.isEmpty()) {
            saveRollupStatus("当日短期记忆为空，跳过整理。")
            return mapOf(
                "success" to true,
                "date" to date.toString(),
                "summary" to "当日短期记忆为空，跳过整理。",
                "longTermWrites" to 0
            )
        }

        val longTermCandidates = lines.map { it.removePrefix("- ").trim() }
            .filter { it.isNotEmpty() }
            .filter { candidate ->
                val lower = candidate.lowercase(Locale.getDefault())
                lower.startsWith("长期:") ||
                    lower.startsWith("long-term:") ||
                    candidate.length >= 18
            }
            .take(8)

        var writes = 0
        longTermCandidates.forEach { item ->
            val normalized = item.removePrefix("长期:").removePrefix("long-term:").trim()
            if (normalized.isNotEmpty() && upsertLongTermMemory(normalized)) {
                writes += 1
            }
        }

        val rollupAt = Instant.now().toString()
        val rollupSummary = "已整理 ${lines.size} 条短期记忆，沉淀 $writes 条长期记忆。"
        dailyFile.appendText(
            "\n## Nightly Rollup @ $rollupAt\n- $rollupSummary\n"
        )
        refreshAndLoadIndex(collectChunks(), resolveEmbeddingConfig())
        saveRollupStatus(rollupSummary)
        return mapOf(
            "success" to true,
            "date" to date.toString(),
            "summary" to rollupSummary,
            "longTermWrites" to writes
        )
    }

    fun getEmbeddingConfigForUi(): WorkspaceMemoryEmbeddingConfig {
        ensureInitialized()
        return resolveEmbeddingConfig()
    }

    fun saveEmbeddingConfigForUi(
        enabled: Boolean,
        providerProfileId: String? = null,
        modelId: String? = null
    ): WorkspaceMemoryEmbeddingConfig {
        ensureInitialized()
        mmkv?.encode(KEY_EMBEDDING_ENABLED, enabled)
        val normalizedProfileId = providerProfileId?.trim().orEmpty()
        val normalizedModelId = modelId?.trim().orEmpty()
        if (normalizedProfileId.isNotEmpty() && normalizedModelId.isNotEmpty()) {
            SceneModelBindingStore.saveBinding(
                SCENE_MEMORY_EMBEDDING,
                normalizedProfileId,
                normalizedModelId
            )
        }
        return resolveEmbeddingConfig()
    }

    fun getRollupStatusForUi(): WorkspaceMemoryRollupStatus {
        val enabled = mmkv?.decodeBool(KEY_ROLLUP_ENABLED, true) ?: true
        val lastRunAt = mmkv?.decodeLong(KEY_ROLLUP_LAST_RUN_AT, 0L)?.takeIf { it > 0 }
        val lastSummary = mmkv?.decodeString(KEY_ROLLUP_LAST_SUMMARY)?.trim()?.ifEmpty { null }
        return WorkspaceMemoryRollupStatus(
            enabled = enabled,
            lastRunAtMillis = lastRunAt,
            lastRunSummary = lastSummary
        )
    }

    fun saveRollupEnabled(enabled: Boolean): WorkspaceMemoryRollupStatus {
        mmkv?.encode(KEY_ROLLUP_ENABLED, enabled)
        return getRollupStatusForUi()
    }

    fun isRollupEnabled(): Boolean {
        return mmkv?.decodeBool(KEY_ROLLUP_ENABLED, true) ?: true
    }

    private fun saveRollupStatus(summary: String) {
        mmkv?.encode(KEY_ROLLUP_LAST_RUN_AT, System.currentTimeMillis())
        mmkv?.encode(KEY_ROLLUP_LAST_SUMMARY, summary)
    }

    private fun summarizeTodayShortMemory(maxItems: Int = 30): String {
        val today = readDailyMemory(LocalDate.now())
        if (today.isBlank()) {
            return "（今日短期记忆为空）"
        }
        val lines = today.lineSequence()
            .map { it.trim() }
            .filter { it.startsWith("- ") }
            .take(maxItems)
            .toList()
        return if (lines.isEmpty()) "（今日短期记忆为空）" else lines.joinToString("\n")
    }

    private fun resolveEmbeddingConfig(): WorkspaceMemoryEmbeddingConfig {
        val enabled = mmkv?.decodeBool(KEY_EMBEDDING_ENABLED, true) ?: true
        val sceneProfile = ModelSceneRegistry.getRuntimeProfile(SCENE_MEMORY_EMBEDDING)
        val binding = SceneModelBindingStore.getBinding(SCENE_MEMORY_EMBEDDING)
        val profile = binding?.providerProfileId?.let { ModelProviderConfigStore.getProfile(it) }
            ?: ModelProviderConfigStore.getEditingProfile()
        val modelId = binding?.modelId?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: sceneProfile?.model?.trim()
                ?.takeIf { it.isNotEmpty() && !it.startsWith("scene.") }
        val apiBase = profile.baseUrl.trim().ifEmpty { null }
        val apiKey = profile.apiKey.trim()
        val configured = enabled &&
            !apiBase.isNullOrBlank() &&
            apiKey.isNotEmpty() &&
            !modelId.isNullOrBlank()
        return WorkspaceMemoryEmbeddingConfig(
            enabled = enabled,
            configured = configured,
            sceneId = SCENE_MEMORY_EMBEDDING,
            providerProfileId = profile.id,
            providerProfileName = profile.name,
            modelId = modelId,
            apiBase = apiBase,
            hasApiKey = apiKey.isNotEmpty()
        )
    }

    private fun collectChunks(): List<MemoryChunk> {
        val chunks = mutableListOf<MemoryChunk>()
        val longTermContent = readLongTermMemory()
        chunks += splitMarkdownToChunks(
            source = ".omnibot/memory/MEMORY.md",
            date = null,
            content = longTermContent
        )

        val shortDir = workspaceManager.shortMemoriesDirectory()
        shortDir.listFiles()
            ?.filter { it.isFile && it.name.endsWith(".md") }
            ?.sortedByDescending { it.name }
            ?.take(14)
            ?.forEach { file ->
                val date = file.nameWithoutExtension
                chunks += splitMarkdownToChunks(
                    source = ".omnibot/memory/short-memories/${file.name}",
                    date = date,
                    content = file.readText()
                )
            }
        return chunks
    }

    private fun splitMarkdownToChunks(
        source: String,
        date: String?,
        content: String
    ): List<MemoryChunk> {
        if (content.isBlank()) return emptyList()
        val lines = content.lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .filterNot { it.startsWith("#") }
            .map {
                if (it.startsWith("- ")) it.removePrefix("- ").trim() else it
            }
            .filter { it.isNotEmpty() }
            .toList()
        val merged = mutableListOf<String>()
        val buffer = StringBuilder()
        lines.forEach { line ->
            if (buffer.length + line.length + 1 > 260) {
                val value = buffer.toString().trim()
                if (value.isNotEmpty()) {
                    merged += value
                }
                buffer.clear()
            }
            if (buffer.isNotEmpty()) buffer.append('\n')
            buffer.append(line)
        }
        val tail = buffer.toString().trim()
        if (tail.isNotEmpty()) {
            merged += tail
        }
        return merged.map { text ->
            MemoryChunk(
                id = stableChunkId(source, date, text),
                source = source,
                date = date,
                text = text
            )
        }
    }

    private fun refreshAndLoadIndex(
        chunks: List<MemoryChunk>,
        config: WorkspaceMemoryEmbeddingConfig
    ): List<MemoryIndexEntry> {
        val indexFile = File(workspaceManager.memoryIndexDirectory(), "index.json")
        val existing = loadIndex(indexFile).associateBy { it.id }.toMutableMap()
        val next = mutableListOf<MemoryIndexEntry>()
        chunks.forEach { chunk ->
            val old = existing.remove(chunk.id)
            if (old != null && old.text == chunk.text) {
                next += old
                return@forEach
            }
            val embedding = if (config.configured) {
                runCatching { requestEmbedding(config, chunk.text) }
                    .onFailure { OmniLog.w(TAG, "embedding chunk failed: ${it.message}") }
                    .getOrElse { emptyList() }
            } else {
                emptyList()
            }
            next += MemoryIndexEntry(
                id = chunk.id,
                source = chunk.source,
                date = chunk.date,
                text = chunk.text,
                embedding = embedding
            )
        }
        saveIndex(indexFile, next)
        return next
    }

    private fun loadIndex(indexFile: File): List<MemoryIndexEntry> {
        if (!indexFile.exists()) return emptyList()
        val raw = runCatching { indexFile.readText() }.getOrDefault("")
        if (raw.isBlank()) return emptyList()
        return runCatching {
            val type = object : TypeToken<List<MemoryIndexEntry>>() {}.type
            gson.fromJson<List<MemoryIndexEntry>>(raw, type) ?: emptyList()
        }.getOrElse {
            OmniLog.w(TAG, "parse index failed: ${it.message}")
            emptyList()
        }
    }

    private fun saveIndex(indexFile: File, entries: List<MemoryIndexEntry>) {
        indexFile.parentFile?.mkdirs()
        indexFile.writeText(gson.toJson(entries))
    }

    private fun requestEmbedding(
        config: WorkspaceMemoryEmbeddingConfig,
        text: String
    ): List<Double> {
        check(config.configured) { "embedding config not ready" }
        val apiBase = config.apiBase!!.trim().trimEnd('/')
        val modelId = config.modelId!!.trim()
        val profile = config.providerProfileId?.let { ModelProviderConfigStore.getProfile(it) }
            ?: ModelProviderConfigStore.getEditingProfile()
        val apiKey = profile.apiKey.trim()
        val url = if (apiBase.endsWith("/v1", ignoreCase = true)) {
            "$apiBase/embeddings"
        } else {
            "$apiBase/v1/embeddings"
        }
        val requestJson = JSONObject().apply {
            put("model", modelId)
            put("input", JSONArray().put(text.take(8_000)))
        }
        val request = Request.Builder()
            .url(url)
            .addHeader("Content-Type", "application/json")
            .addHeader("Authorization", "Bearer $apiKey")
            .post(requestJson.toString().toRequestBody("application/json".toMediaType()))
            .build()
        httpClient.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                throw IllegalStateException(
                    "embedding request failed(${response.code}): ${body.take(320)}"
                )
            }
            val payload = JSONObject(body)
            val data = payload.optJSONArray("data") ?: JSONArray()
            if (data.length() == 0) return emptyList()
            val first = data.optJSONObject(0) ?: return emptyList()
            val embedding = first.optJSONArray("embedding") ?: JSONArray()
            return buildList {
                for (i in 0 until embedding.length()) {
                    add(embedding.optDouble(i))
                }
            }
        }
    }

    private fun lexicalScore(query: String, text: String): Double {
        val nq = normalizeText(query)
        val nt = normalizeText(text)
        if (nq.isEmpty() || nt.isEmpty()) return 0.0
        if (nt.contains(nq)) {
            return 1.0
        }
        val qTokens = tokenize(query)
        val tTokens = tokenize(text).toSet()
        if (qTokens.isEmpty() || tTokens.isEmpty()) return 0.0
        val hit = qTokens.count { tTokens.contains(it) }
        return hit.toDouble() / qTokens.size.toDouble()
    }

    private fun cosineSimilarity(a: List<Double>, b: List<Double>): Double {
        val size = minOf(a.size, b.size)
        if (size == 0) return 0.0
        var dot = 0.0
        var normA = 0.0
        var normB = 0.0
        for (i in 0 until size) {
            val av = a[i]
            val bv = b[i]
            dot += av * bv
            normA += av * av
            normB += bv * bv
        }
        if (normA <= 0 || normB <= 0) return 0.0
        return dot / (sqrt(normA) * sqrt(normB))
    }

    private fun tokenize(text: String): List<String> {
        return text.lowercase(Locale.getDefault())
            .split(Regex("[^\\p{L}\\p{N}]+"))
            .map { it.trim() }
            .filter { it.length >= 2 }
    }

    private fun truncateText(raw: String, maxChars: Int): String {
        if (raw.length <= maxChars) return raw
        return raw.take(maxChars) + "\n...(truncated)"
    }

    private fun normalizeText(text: String): String {
        return text.lowercase(Locale.getDefault())
            .replace(Regex("\\s+"), "")
            .trim()
    }

    private fun stableChunkId(source: String, date: String?, text: String): String {
        val raw = "$source|${date.orEmpty()}|${normalizeText(text)}"
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(raw.toByteArray(StandardCharsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }.take(24)
    }
}
