package cn.com.omnimind.bot.sync

import android.content.Context
import androidx.room.withTransaction
import cn.com.omnimind.baselib.database.AgentConversationEntry
import cn.com.omnimind.baselib.database.Conversation
import cn.com.omnimind.baselib.database.DatabaseHelper
import cn.com.omnimind.baselib.database.ExecutionRecord
import cn.com.omnimind.baselib.database.FavoriteRecord
import cn.com.omnimind.baselib.database.Message
import cn.com.omnimind.baselib.database.SyncCheckpoint
import cn.com.omnimind.baselib.database.SyncConflictRecord
import cn.com.omnimind.baselib.database.SyncFileIndex
import cn.com.omnimind.baselib.database.SyncOutbox
import cn.com.omnimind.baselib.database.StudyRecord
import cn.com.omnimind.baselib.database.TokenUsageRecord
import cn.com.omnimind.baselib.util.OmniLog
import com.google.gson.JsonParser
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class DataSyncManager private constructor(
    private val context: Context
) {
    companion object {
        @Volatile
        private var instance: DataSyncManager? = null

        fun get(context: Context): DataSyncManager {
            return instance ?: synchronized(this) {
                instance ?: DataSyncManager(context.applicationContext).also { instance = it }
            }
        }
    }

    private val database = DatabaseHelper.getDatabase()
    private val configStore = DataSyncConfigStore(context)
    private val statusStore = DataSyncStatusStore(context)
    private val apiClient = DataSyncApiClient()
    private val s3Client = DataSyncS3Client()
    private val settingsSnapshot = DataSyncSettingsSnapshot(context)
    private val fileScanner = DataSyncFileScanner(context)

    fun getConfig(): DataSyncConfig = configStore.getConfig()

    suspend fun saveConfig(rawConfig: DataSyncConfig): DataSyncConfig {
        val saved = configStore.saveConfig(rawConfig)
        DataSyncScheduler.ensureScheduledIfEnabled(context, saved)
        val currentStatus = buildStatus(
            base = statusStore.read(),
            config = saved
        ).copy(
            enabled = saved.enabled,
            configured = saved.isConfigured(),
            namespace = saved.namespace,
            deviceId = saved.deviceId,
            state = if (!saved.enabled) DataSyncState.DISABLED else statusStore.read().state,
            updatedAt = System.currentTimeMillis()
        )
        statusStore.write(currentStatus)
        return saved
    }

    suspend fun setEnabled(enabled: Boolean): DataSyncStatus {
        val config = configStore.updateEnabled(enabled)
        DataSyncScheduler.ensureScheduledIfEnabled(context, config)
        if (enabled && config.isConfigured()) {
            DataSyncScheduler.requestSyncNow(context, reason = "enable_sync", foreground = false)
        }
        val status = buildStatus(
            base = statusStore.read(),
            config = config
        ).copy(
            enabled = enabled,
            configured = config.isConfigured(),
            state = if (enabled) DataSyncState.IDLE else DataSyncState.DISABLED,
            lastMessage = if (enabled) "同步已启用" else "同步已停用",
            updatedAt = System.currentTimeMillis()
        )
        statusStore.write(status)
        return status
    }

    suspend fun requestSyncNow(reason: String = "manual"): DataSyncStatus {
        val config = configStore.getConfig()
        require(config.enabled && config.isConfigured()) { "Data sync is not enabled or not fully configured" }
        val status = buildStatus(
            base = statusStore.read(),
            config = config
        ).copy(
            state = DataSyncState.SYNCING,
            currentStep = "queued",
            lastMessage = "同步任务已加入队列",
            updatedAt = System.currentTimeMillis()
        )
        statusStore.write(status)
        DataSyncScheduler.requestSyncNow(context, reason = reason, foreground = true)
        return status
    }

    suspend fun getStatus(): DataSyncStatus {
        return buildStatus(
            base = statusStore.read(),
            config = configStore.getConfig()
        )
    }

    fun testConnection(candidate: DataSyncConfig? = null): Map<String, Any?> {
        val source = candidate ?: configStore.getConfig()
        val config = source.copy(
            deviceId = source.deviceId.ifBlank { configStore.getOrCreateDeviceId() }
        ).sanitized()
        require(config.isConfigured()) { "Please complete all sync fields before testing the connection" }
        val handshake = apiClient.handshake(config)
        s3Client.testConnection(config)
        return linkedMapOf(
            "success" to true,
            "namespace" to handshake.namespace,
            "registered" to handshake.registered,
            "remoteCursor" to handshake.remoteCursor,
            "message" to "Supabase 与 S3 连接成功"
        )
    }

    fun exportPairingPayload(passphrase: String): DataSyncPairingPayload {
        val config = configStore.getConfig()
        require(config.isConfigured()) { "Sync config is incomplete" }
        val exportMap = linkedMapOf(
            "supabaseUrl" to config.supabaseUrl,
            "anonKey" to config.anonKey,
            "namespace" to config.namespace,
            "syncSecret" to config.syncSecret,
            "s3Endpoint" to config.s3Endpoint,
            "region" to config.region,
            "bucket" to config.bucket,
            "accessKey" to config.accessKey,
            "secretKey" to config.secretKey,
            "sessionToken" to config.sessionToken,
            "forcePathStyle" to config.forcePathStyle
        )
        return DataSyncCrypto.encryptPairingPayload(
            json = dataSyncGson.toJson(exportMap),
            passphrase = passphrase,
            namespace = config.namespace
        )
    }

    suspend fun importPairingPayload(encodedPayload: String, passphrase: String): DataSyncStatus {
        val json = DataSyncCrypto.decryptPairingPayload(encodedPayload, passphrase)
        @Suppress("UNCHECKED_CAST")
        val payload = dataSyncGson.fromJson(json, dataSyncMapType) as Map<String, Any?>
        val current = configStore.getConfig()
        val imported = DataSyncConfig.fromMap(payload + mapOf(
            "enabled" to true,
            "deviceId" to current.deviceId
        ))
        saveConfig(imported.copy(enabled = true))
        val status = buildStatus(
            base = statusStore.read(),
            config = imported.copy(enabled = true)
        ).copy(
            state = DataSyncState.SYNCING,
            lastMessage = "配对导入成功，正在执行首次全量同步",
            currentStep = "pairing_import",
            updatedAt = System.currentTimeMillis()
        )
        statusStore.write(status)
        DataSyncScheduler.requestSyncNow(context, reason = "pairing_import", foreground = true)
        return buildStatus(status, imported.copy(enabled = true))
    }

    suspend fun listConflicts(): List<DataSyncConflictItem> = withContext(Dispatchers.IO) {
        database.syncConflictRecordDao().getAll().map {
            DataSyncConflictItem(
                id = it.id,
                relativePath = it.relativePath,
                localHash = it.localHash,
                remoteHash = it.remoteHash,
                remoteObjectKey = it.remoteObjectKey,
                conflictCopyPath = it.conflictCopyPath,
                status = it.status,
                createdAt = it.createdAt,
                updatedAt = it.updatedAt
            )
        }
    }

    suspend fun ackConflict(id: Long): Boolean = withContext(Dispatchers.IO) {
        val existing = database.syncConflictRecordDao().getById(id) ?: return@withContext false
        database.syncConflictRecordDao().update(
            existing.copy(status = "acknowledged", updatedAt = System.currentTimeMillis())
        )
        true
    }

    suspend fun reindexLocalSnapshot(): DataSyncStatus = withContext(Dispatchers.IO) {
        val config = configStore.getConfig()
        database.syncFileIndexDao().deleteAll()
        database.syncOutboxDao().deleteAll()
        val checkpoint = getCheckpoint().copy(
            lastMetadataSyncAt = 0,
            lastFileScanAt = 0,
            lastSettingsHash = "",
            updatedAt = System.currentTimeMillis()
        )
        database.syncCheckpointDao().upsert(checkpoint)
        collectLocalChanges(config = config, checkpoint = checkpoint, reason = "reindex")
        val status = buildStatus(
            base = statusStore.read().copy(
                state = if (config.enabled) DataSyncState.IDLE else DataSyncState.DISABLED,
                lastMessage = "本地快照索引已重建",
                updatedAt = System.currentTimeMillis()
            ),
            config = config
        )
        statusStore.write(status)
        status
    }

    suspend fun runSync(
        reason: String,
        foreground: Boolean,
        onProgress: suspend (DataSyncProgress) -> Unit = {}
    ): DataSyncStatus = withContext(Dispatchers.IO) {
        val config = configStore.getConfig().sanitized()
        try {
            require(config.enabled && config.isConfigured()) { "Data sync is disabled or incomplete" }
            DataSyncScheduler.ensureScheduledIfEnabled(context, config)

            updateStatus(
                config = config,
                state = DataSyncState.SYNCING,
                step = "handshake",
                message = "开始同步"
            )
            onProgress(progressFor("handshake", "正在建立安全连接…", 0, 100))
            val handshake = apiClient.handshake(config)
            val existingCheckpoint = getCheckpoint()
            val checkpoint = existingCheckpoint.copy(
                remoteCursor = maxOf(existingCheckpoint.remoteCursor, handshake.remoteCursor),
                updatedAt = System.currentTimeMillis()
            )
            database.syncCheckpointDao().upsert(checkpoint)

            val shouldPullFirst = reason == "pairing_import" || (!hasMaterialLocalState() && checkpoint.remoteCursor > 0)
            if (!shouldPullFirst) {
                collectLocalChanges(config = config, checkpoint = checkpoint, reason = reason, onProgress = onProgress)
                pushOutbox(config, onProgress)
            }
            pullRemoteChanges(config, onProgress)
            if (shouldPullFirst) {
                collectLocalChanges(config = config, checkpoint = getCheckpoint(), reason = reason, onProgress = onProgress)
                pushOutbox(config, onProgress)
                pullRemoteChanges(config, onProgress)
            }
            val finalCheckpoint = getCheckpoint().copy(
                lastSuccessfulSyncAt = System.currentTimeMillis(),
                updatedAt = System.currentTimeMillis()
            )
            database.syncCheckpointDao().upsert(finalCheckpoint)
            val status = buildStatus(
                base = statusStore.read().copy(
                    state = DataSyncState.SUCCESS,
                    lastSyncAt = System.currentTimeMillis(),
                    lastSuccessAt = finalCheckpoint.lastSuccessfulSyncAt,
                    lastError = "",
                    lastMessage = "同步完成",
                    currentStep = "done",
                    progress = progressFor("done", "同步完成", 100, 100),
                    updatedAt = System.currentTimeMillis()
                ),
                config = config
            )
            statusStore.write(status)
            if (foreground || reason == "pairing_import") {
                DataSyncNotifications.notifyResult(context, "Omnibot 数据同步完成", "数据已安全同步到当前设备。")
            }
            status
        } catch (error: Throwable) {
            val status = buildStatus(
                base = statusStore.read().copy(
                    state = DataSyncState.ERROR,
                    lastSyncAt = System.currentTimeMillis(),
                    lastError = error.message.orEmpty(),
                    lastMessage = "同步失败",
                    currentStep = "error",
                    progress = progressFor("error", error.message ?: "未知错误", 0, 100),
                    updatedAt = System.currentTimeMillis()
                ),
                config = config
            )
            statusStore.write(status)
            if (foreground || reason == "pairing_import") {
                DataSyncNotifications.notifyResult(
                    context,
                    "Omnibot 数据同步失败",
                    error.message ?: "请检查同步配置和网络连接。",
                    error = true
                )
            }
            throw error
        }
    }

    private suspend fun pullRemoteChanges(
        config: DataSyncConfig,
        onProgress: suspend (DataSyncProgress) -> Unit
    ) {
        var cursor = getCheckpoint().remoteCursor
        while (true) {
            val progress = progressFor("pull", "正在拉取远端变更…", 0, 100)
            updateStatus(config, DataSyncState.SYNCING, "pull", progress.detail, progress)
            onProgress(progress)
            val pulled = apiClient.pullChanges(config, cursor = cursor, limit = 200)
            if (pulled.changes.isEmpty()) {
                if (pulled.nextCursor > cursor) {
                    database.syncCheckpointDao().upsert(
                        getCheckpoint().copy(
                            remoteCursor = pulled.nextCursor,
                            updatedAt = System.currentTimeMillis()
                        )
                    )
                }
                return
            }
            applyRemoteChanges(config, pulled.changes)
            val metadataWatermark = currentMetadataWatermark()
            cursor = maxOf(cursor, pulled.nextCursor, pulled.changes.maxOfOrNull { it.cursor } ?: cursor)
            database.syncCheckpointDao().upsert(
                getCheckpoint().copy(
                    remoteCursor = cursor,
                    lastMetadataSyncAt = maxOf(getCheckpoint().lastMetadataSyncAt, metadataWatermark),
                    updatedAt = System.currentTimeMillis()
                )
            )
        }
    }

    private suspend fun pushOutbox(
        config: DataSyncConfig,
        onProgress: suspend (DataSyncProgress) -> Unit
    ) {
        while (true) {
            val ready = database.syncOutboxDao().listReady(System.currentTimeMillis(), 50)
            if (ready.isEmpty()) return
            val progress = progressFor("push", "正在上传本地变更…", 0, ready.size)
            updateStatus(config, DataSyncState.SYNCING, "push", progress.detail, progress)
            onProgress(progress)
            val operations = ready.map { entry ->
                val payload = JsonParser.parseString(entry.payloadJson)
                linkedMapOf(
                    "opId" to entry.opId,
                    "docType" to entry.docType,
                    "docSyncId" to entry.docSyncId,
                    "opType" to entry.opType,
                    "contentHash" to entry.contentHash,
                    "payload" to payload
                )
            }
            runCatching {
                apiClient.pushChanges(config, operations)
            }.onSuccess { response ->
                ready.forEach { entry ->
                    if (response.acknowledgedOpIds.contains(entry.opId)) {
                        database.syncOutboxDao().deleteById(entry.id)
                    }
                }
                if (response.cursor > 0) {
                    database.syncCheckpointDao().upsert(
                        getCheckpoint().copy(
                            remoteCursor = maxOf(getCheckpoint().remoteCursor, response.cursor),
                            updatedAt = System.currentTimeMillis()
                        )
                    )
                }
            }.onFailure { error ->
                ready.forEach { entry ->
                    database.syncOutboxDao().update(
                        entry.copy(
                            attempts = entry.attempts + 1,
                            nextRetryAt = System.currentTimeMillis() + retryDelayMillis(entry.attempts + 1),
                            lastError = error.message,
                            updatedAt = System.currentTimeMillis()
                        )
                    )
                }
                throw error
            }
        }
    }

    private suspend fun collectLocalChanges(
        config: DataSyncConfig,
        checkpoint: SyncCheckpoint,
        reason: String,
        onProgress: suspend (DataSyncProgress) -> Unit = {}
    ) {
        val progress = progressFor("snapshot", "正在分析本地快照差异…", 0, 100)
        updateStatus(config, DataSyncState.SYNCING, "snapshot", progress.detail, progress)
        onProgress(progress)
        collectDatabaseChanges(checkpoint.lastMetadataSyncAt)
        collectSettingsChange(checkpoint)
        collectFileChanges(config)
        val watermark = currentMetadataWatermark()
        val latestCheckpoint = getCheckpoint()
        database.syncCheckpointDao().upsert(
            latestCheckpoint.copy(
                lastMetadataSyncAt = maxOf(latestCheckpoint.lastMetadataSyncAt, watermark),
                lastFileScanAt = System.currentTimeMillis(),
                updatedAt = System.currentTimeMillis()
            )
        )
        OmniLog.d("DataSyncManager", "Collected local changes for reason=$reason")
    }

    private suspend fun collectDatabaseChanges(updatedAfter: Long) {
        database.conversationDao().getUpdatedAfter(updatedAfter).forEach { enqueueConversationUpsert(it) }
        database.messageDao().getUpdatedAfter(updatedAfter).forEach { enqueueChange(DataSyncDocType.MESSAGE, it.syncId, DataSyncOpType.UPSERT, messagePayload(it)) }
        database.favoriteRecordDao().getUpdatedAfter(updatedAfter).forEach { enqueueChange(DataSyncDocType.FAVORITE_RECORD, it.syncId, DataSyncOpType.UPSERT, favoritePayload(it)) }
        database.executionRecordDao().getUpdatedAfter(updatedAfter).forEach { enqueueChange(DataSyncDocType.EXECUTION_RECORD, it.syncId, DataSyncOpType.UPSERT, executionPayload(it)) }
        database.studyRecordDao().getUpdatedAfter(updatedAfter).forEach { enqueueChange(DataSyncDocType.STUDY_RECORD, it.syncId, DataSyncOpType.UPSERT, studyPayload(it)) }
        database.agentConversationEntryDao().getUpdatedAfter(updatedAfter).forEach { enqueueAgentEntryUpsert(it) }
        database.tokenUsageRecordDao().getCreatedAfter(updatedAfter).forEach { enqueueTokenUsageUpsert(it) }
    }

    private suspend fun collectSettingsChange(checkpoint: SyncCheckpoint) {
        val snapshot = settingsSnapshot.capture()
        val hash = settingsSnapshot.captureHash(snapshot)
        if (hash == checkpoint.lastSettingsHash) {
            return
        }
        enqueueChange(
            DataSyncDocType.SETTINGS_SNAPSHOT,
            "current",
            DataSyncOpType.UPSERT,
            snapshot
        )
        database.syncCheckpointDao().upsert(
            checkpoint.copy(
                lastSettingsHash = hash,
                updatedAt = System.currentTimeMillis()
            )
        )
    }

    private suspend fun collectFileChanges(config: DataSyncConfig) {
        val currentFiles = fileScanner.scanManagedFiles()
        val existing = database.syncFileIndexDao().getAll().associateBy { it.relativePath }
        currentFiles.forEach { file ->
            val current = existing[file.relativePath]
            if (current?.contentHash == file.contentHash && current.status != "deleted") {
                return@forEach
            }
            val objectKey = objectKeyForHash(config.namespace, file.contentHash)
            if (!s3Client.objectExists(config, objectKey)) {
                s3Client.uploadObject(config, objectKey, File(file.absolutePath), file.contentHash)
            }
            database.syncFileIndexDao().insert(
                SyncFileIndex(
                    id = current?.id ?: 0,
                    relativePath = file.relativePath,
                    contentHash = file.contentHash,
                    sizeBytes = file.sizeBytes,
                    lastModifiedAt = file.lastModifiedAt,
                    objectKey = objectKey,
                    status = "ready",
                    updatedAt = System.currentTimeMillis()
                )
            )
            enqueueChange(
                DataSyncDocType.FILE,
                file.relativePath,
                DataSyncOpType.UPSERT,
                linkedMapOf(
                    "relativePath" to file.relativePath,
                    "contentHash" to file.contentHash,
                    "sizeBytes" to file.sizeBytes,
                    "lastModifiedAt" to file.lastModifiedAt,
                    "objectKey" to objectKey,
                    "deleted" to false
                )
            )
        }
        val currentPaths = currentFiles.mapTo(mutableSetOf()) { it.relativePath }
        existing.values
            .filter { !currentPaths.contains(it.relativePath) && it.status != "deleted" }
            .forEach { previous ->
                database.syncFileIndexDao().insert(
                    previous.copy(status = "deleted", updatedAt = System.currentTimeMillis())
                )
                enqueueChange(
                    DataSyncDocType.FILE,
                    previous.relativePath,
                    DataSyncOpType.DELETE,
                    linkedMapOf(
                        "relativePath" to previous.relativePath,
                        "contentHash" to previous.contentHash,
                        "objectKey" to previous.objectKey,
                        "deleted" to true
                    )
                )
            }
    }

    private suspend fun applyRemoteChanges(
        config: DataSyncConfig,
        changes: List<DataSyncRemoteChange>
    ) {
        database.withTransaction {
            changes
                .filter { it.docType == DataSyncDocType.CONVERSATION }
                .forEach { applyRemoteConversation(it) }
            changes
                .filter {
                    it.docType == DataSyncDocType.MESSAGE ||
                        it.docType == DataSyncDocType.FAVORITE_RECORD ||
                        it.docType == DataSyncDocType.EXECUTION_RECORD ||
                        it.docType == DataSyncDocType.STUDY_RECORD
                }.forEach { applyRemoteSimpleDocument(it) }
            changes
                .filter { it.docType == DataSyncDocType.AGENT_CONVERSATION_ENTRY }
                .forEach { applyRemoteAgentEntry(it) }
            changes
                .filter { it.docType == DataSyncDocType.TOKEN_USAGE_RECORD }
                .forEach { applyRemoteTokenUsage(it) }
        }
        changes.filter { it.docType == DataSyncDocType.SETTINGS_SNAPSHOT }.forEach {
            if (it.opType == DataSyncOpType.UPSERT) {
                settingsSnapshot.apply(it.payload)
                val checkpoint = getCheckpoint()
                database.syncCheckpointDao().upsert(
                    checkpoint.copy(
                        lastSettingsHash = settingsSnapshot.captureHash(it.payload),
                        updatedAt = System.currentTimeMillis()
                    )
                )
            }
        }
        changes.filter { it.docType == DataSyncDocType.FILE }.forEach {
            applyRemoteFile(config, it)
        }
    }

    private suspend fun applyRemoteConversation(change: DataSyncRemoteChange) {
        if (change.opType == DataSyncOpType.DELETE) {
            val existing = database.conversationDao().getBySyncId(change.docSyncId) ?: return
            database.conversationDao().deleteBySyncId(change.docSyncId)
            database.agentConversationEntryDao().deleteConversationEntries(existing.id)
            return
        }
        val payload = change.payload
        val existing = database.conversationDao().getBySyncId(change.docSyncId)
        val cutoffSyncId = payload["contextSummaryCutoffEntrySyncId"]?.toString()
        val cutoffLocalId = cutoffSyncId
            ?.takeIf { it.isNotBlank() }
            ?.let { database.agentConversationEntryDao().getBySyncId(it)?.id }
        val entity = Conversation(
            id = existing?.id ?: 0,
            syncId = change.docSyncId,
            title = payload["title"]?.toString().orEmpty(),
            mode = payload["mode"]?.toString().orEmpty().ifBlank { "normal" },
            isArchived = payload["isArchived"] == true,
            summary = payload["summary"]?.toString(),
            contextSummary = payload["contextSummary"]?.toString(),
            contextSummaryCutoffEntryDbId = cutoffLocalId,
            contextSummaryUpdatedAt = payload["contextSummaryUpdatedAt"].toLongValue(),
            status = payload["status"].toIntValue(),
            lastMessage = payload["lastMessage"]?.toString(),
            messageCount = payload["messageCount"].toIntValue(),
            latestPromptTokens = payload["latestPromptTokens"].toIntValue(),
            promptTokenThreshold = payload["promptTokenThreshold"].toIntValue(128_000),
            latestPromptTokensUpdatedAt = payload["latestPromptTokensUpdatedAt"].toLongValue(),
            createdAt = payload["createdAt"].toLongValue(System.currentTimeMillis()),
            updatedAt = payload["updatedAt"].toLongValue(System.currentTimeMillis())
        )
        if (existing == null) {
            database.conversationDao().insert(entity)
        } else {
            database.conversationDao().update(entity)
        }
    }

    private suspend fun applyRemoteSimpleDocument(change: DataSyncRemoteChange) {
        when (change.docType) {
            DataSyncDocType.MESSAGE -> applyRemoteMessage(change)
            DataSyncDocType.FAVORITE_RECORD -> applyRemoteFavorite(change)
            DataSyncDocType.EXECUTION_RECORD -> applyRemoteExecution(change)
            DataSyncDocType.STUDY_RECORD -> applyRemoteStudy(change)
        }
    }

    private suspend fun applyRemoteMessage(change: DataSyncRemoteChange) {
        if (change.opType == DataSyncOpType.DELETE) {
            database.messageDao().deleteBySyncId(change.docSyncId)
            return
        }
        val payload = change.payload
        val existing = database.messageDao().getBySyncId(change.docSyncId)
        val entity = Message(
            id = existing?.id ?: 0,
            syncId = change.docSyncId,
            messageId = payload["messageId"]?.toString().orEmpty(),
            type = payload["type"].toIntValue(),
            user = payload["user"].toIntValue(),
            content = payload["content"]?.toString().orEmpty(),
            createdAt = payload["createdAt"].toLongValue(System.currentTimeMillis()),
            updatedAt = payload["updatedAt"].toLongValue(System.currentTimeMillis())
        )
        if (existing == null) database.messageDao().insert(entity) else database.messageDao().update(entity)
    }

    private suspend fun applyRemoteFavorite(change: DataSyncRemoteChange) {
        if (change.opType == DataSyncOpType.DELETE) {
            database.favoriteRecordDao().deleteBySyncId(change.docSyncId)
            return
        }
        val payload = change.payload
        val existing = database.favoriteRecordDao().getBySyncId(change.docSyncId)
        val entity = FavoriteRecord(
            id = existing?.id ?: 0,
            syncId = change.docSyncId,
            title = payload["title"]?.toString().orEmpty(),
            desc = payload["desc"]?.toString().orEmpty(),
            type = payload["type"]?.toString().orEmpty(),
            imagePath = payload["imagePath"]?.toString().orEmpty(),
            packageName = payload["packageName"]?.toString().orEmpty(),
            status = payload["status"].toIntValue(),
            createdAt = payload["createdAt"].toLongValue(System.currentTimeMillis()),
            updatedAt = payload["updatedAt"].toLongValue(System.currentTimeMillis())
        )
        if (existing == null) database.favoriteRecordDao().insert(entity) else database.favoriteRecordDao().update(entity)
    }

    private suspend fun applyRemoteExecution(change: DataSyncRemoteChange) {
        if (change.opType == DataSyncOpType.DELETE) {
            database.executionRecordDao().deleteBySyncId(change.docSyncId)
            return
        }
        val payload = change.payload
        val existing = database.executionRecordDao().getBySyncId(change.docSyncId)
        val entity = ExecutionRecord(
            id = existing?.id ?: 0,
            syncId = change.docSyncId,
            title = payload["title"]?.toString().orEmpty(),
            appName = payload["appName"]?.toString().orEmpty(),
            packageName = payload["packageName"]?.toString().orEmpty(),
            nodeId = payload["nodeId"]?.toString().orEmpty(),
            suggestionId = payload["suggestionId"]?.toString().orEmpty(),
            iconUrl = payload["iconUrl"]?.toString(),
            type = payload["type"]?.toString().orEmpty().ifBlank { "unknown" },
            content = payload["content"]?.toString(),
            status = payload["status"]?.toString().orEmpty().ifBlank { "running" },
            createdAt = payload["createdAt"].toLongValue(System.currentTimeMillis()),
            updatedAt = payload["updatedAt"].toLongValue(System.currentTimeMillis())
        )
        if (existing == null) database.executionRecordDao().insert(entity) else database.executionRecordDao().update(entity)
    }

    private suspend fun applyRemoteStudy(change: DataSyncRemoteChange) {
        if (change.opType == DataSyncOpType.DELETE) {
            database.studyRecordDao().deleteBySyncId(change.docSyncId)
            return
        }
        val payload = change.payload
        val existing = database.studyRecordDao().getBySyncId(change.docSyncId)
        val entity = StudyRecord(
            id = existing?.id ?: 0,
            syncId = change.docSyncId,
            title = payload["title"]?.toString().orEmpty(),
            suggestionId = payload["suggestionId"]?.toString().orEmpty(),
            appName = payload["appName"]?.toString().orEmpty(),
            packageName = payload["packageName"]?.toString().orEmpty(),
            createdAt = payload["createdAt"].toLongValue(System.currentTimeMillis()),
            updatedAt = payload["updatedAt"].toLongValue(System.currentTimeMillis()),
            isFavorite = payload["isFavorite"] == true
        )
        if (existing == null) database.studyRecordDao().insert(entity) else database.studyRecordDao().update(entity)
    }

    private suspend fun applyRemoteAgentEntry(change: DataSyncRemoteChange) {
        if (change.opType == DataSyncOpType.DELETE) {
            database.agentConversationEntryDao().deleteBySyncId(change.docSyncId)
            return
        }
        val payload = change.payload
        val conversationSyncId = payload["conversationSyncId"]?.toString().orEmpty()
        val conversation = database.conversationDao().getBySyncId(conversationSyncId) ?: return
        val existing = database.agentConversationEntryDao().getBySyncId(change.docSyncId)
        val entity = AgentConversationEntry(
            id = existing?.id ?: 0,
            syncId = change.docSyncId,
            conversationId = conversation.id,
            conversationMode = payload["conversationMode"]?.toString().orEmpty(),
            entryId = payload["entryId"]?.toString().orEmpty(),
            entryType = payload["entryType"]?.toString().orEmpty(),
            status = payload["status"]?.toString().orEmpty(),
            summary = payload["summary"]?.toString().orEmpty(),
            payloadJson = payload["payloadJson"]?.toString().orEmpty(),
            createdAt = payload["createdAt"].toLongValue(System.currentTimeMillis()),
            updatedAt = payload["updatedAt"].toLongValue(System.currentTimeMillis())
        )
        database.agentConversationEntryDao().upsert(entity)
    }

    private suspend fun applyRemoteTokenUsage(change: DataSyncRemoteChange) {
        if (change.opType == DataSyncOpType.DELETE) {
            database.tokenUsageRecordDao().deleteBySyncId(change.docSyncId)
            return
        }
        val payload = change.payload
        val conversationSyncId = payload["conversationSyncId"]?.toString().orEmpty()
        val conversation = database.conversationDao().getBySyncId(conversationSyncId) ?: return
        val existing = database.tokenUsageRecordDao().getBySyncId(change.docSyncId)
        if (existing != null) {
            return
        }
        database.tokenUsageRecordDao().insert(
            TokenUsageRecord(
                id = 0,
                syncId = change.docSyncId,
                conversationId = conversation.id,
                isLocal = payload["isLocal"] == true,
                model = payload["model"]?.toString().orEmpty(),
                promptTokens = payload["promptTokens"].toIntValue(),
                completionTokens = payload["completionTokens"].toIntValue(),
                reasoningTokens = payload["reasoningTokens"].toIntValue(),
                textTokens = payload["textTokens"].toIntValue(),
                createdAt = payload["createdAt"].toLongValue(System.currentTimeMillis())
            )
        )
    }

    private suspend fun applyRemoteFile(config: DataSyncConfig, change: DataSyncRemoteChange) {
        val relativePath = change.payload["relativePath"]?.toString().orEmpty().ifBlank { change.docSyncId }
        val target = fileScanner.resolveManagedFile(relativePath)
        val parent = target.parentFile
        parent?.mkdirs()
        if (change.opType == DataSyncOpType.DELETE || change.payload["deleted"] == true) {
            if (target.exists()) {
                target.delete()
            }
            val existingIndex = database.syncFileIndexDao().getByRelativePath(relativePath)
            if (existingIndex != null) {
                database.syncFileIndexDao().insert(
                    existingIndex.copy(status = "deleted", updatedAt = System.currentTimeMillis())
                )
            }
            return
        }
        val remoteHash = change.payload["contentHash"]?.toString().orEmpty()
        val objectKey = change.payload["objectKey"]?.toString().orEmpty()
            .ifBlank { objectKeyForHash(config.namespace, remoteHash) }
        val localHash = if (target.exists()) DataSyncCrypto.sha256Hex(target) else ""
        if (target.exists() && localHash.isNotBlank() && remoteHash.isNotBlank() && localHash != remoteHash) {
            val conflictCopy = fileScanner.buildConflictCopy(target, change.deviceId)
            target.copyTo(conflictCopy, overwrite = true)
            database.syncConflictRecordDao().insert(
                SyncConflictRecord(
                    relativePath = relativePath,
                    localHash = localHash,
                    remoteHash = remoteHash,
                    remoteObjectKey = objectKey,
                    conflictCopyPath = conflictCopy.absolutePath,
                    status = "open",
                    createdAt = System.currentTimeMillis(),
                    updatedAt = System.currentTimeMillis()
                )
            )
        }
        val tempFile = File(target.absolutePath + ".download.${UUID.randomUUID()}.tmp")
        s3Client.downloadObject(config, objectKey, tempFile)
        val downloadedHash = DataSyncCrypto.sha256Hex(tempFile)
        require(downloadedHash == remoteHash) {
            "Downloaded file hash mismatch for $relativePath"
        }
        if (target.exists()) {
            target.delete()
        }
        tempFile.renameTo(target)
        val existingIndex = database.syncFileIndexDao().getByRelativePath(relativePath)
        database.syncFileIndexDao().insert(
            SyncFileIndex(
                id = existingIndex?.id ?: 0,
                relativePath = relativePath,
                contentHash = remoteHash,
                sizeBytes = target.length(),
                lastModifiedAt = target.lastModified(),
                objectKey = objectKey,
                status = "ready",
                updatedAt = System.currentTimeMillis()
            )
        )
    }

    private suspend fun enqueueConversationUpsert(conversation: Conversation) {
        val cutoffEntrySyncId = conversation.contextSummaryCutoffEntryDbId?.let { localId ->
            database.agentConversationEntryDao().getById(localId)?.syncId
        }
        enqueueChange(
            DataSyncDocType.CONVERSATION,
            conversation.syncId,
            DataSyncOpType.UPSERT,
            linkedMapOf(
                "syncId" to conversation.syncId,
                "title" to conversation.title,
                "mode" to conversation.mode,
                "isArchived" to conversation.isArchived,
                "summary" to conversation.summary,
                "contextSummary" to conversation.contextSummary,
                "contextSummaryCutoffEntrySyncId" to cutoffEntrySyncId,
                "contextSummaryUpdatedAt" to conversation.contextSummaryUpdatedAt,
                "status" to conversation.status,
                "lastMessage" to conversation.lastMessage,
                "messageCount" to conversation.messageCount,
                "latestPromptTokens" to conversation.latestPromptTokens,
                "promptTokenThreshold" to conversation.promptTokenThreshold,
                "latestPromptTokensUpdatedAt" to conversation.latestPromptTokensUpdatedAt,
                "createdAt" to conversation.createdAt,
                "updatedAt" to conversation.updatedAt
            )
        )
    }

    private suspend fun enqueueAgentEntryUpsert(entry: AgentConversationEntry) {
        val conversationSyncId = database.conversationDao().getById(entry.conversationId)?.syncId ?: return
        enqueueChange(
            DataSyncDocType.AGENT_CONVERSATION_ENTRY,
            entry.syncId,
            DataSyncOpType.UPSERT,
            linkedMapOf(
                "syncId" to entry.syncId,
                "conversationSyncId" to conversationSyncId,
                "conversationMode" to entry.conversationMode,
                "entryId" to entry.entryId,
                "entryType" to entry.entryType,
                "status" to entry.status,
                "summary" to entry.summary,
                "payloadJson" to entry.payloadJson,
                "createdAt" to entry.createdAt,
                "updatedAt" to entry.updatedAt
            )
        )
    }

    private suspend fun enqueueTokenUsageUpsert(record: TokenUsageRecord) {
        val conversationSyncId = database.conversationDao().getById(record.conversationId)?.syncId ?: return
        enqueueChange(
            DataSyncDocType.TOKEN_USAGE_RECORD,
            record.syncId,
            DataSyncOpType.UPSERT,
            linkedMapOf(
                "syncId" to record.syncId,
                "conversationSyncId" to conversationSyncId,
                "isLocal" to record.isLocal,
                "model" to record.model,
                "promptTokens" to record.promptTokens,
                "completionTokens" to record.completionTokens,
                "reasoningTokens" to record.reasoningTokens,
                "textTokens" to record.textTokens,
                "createdAt" to record.createdAt
            )
        )
    }

    private suspend fun enqueueChange(
        docType: String,
        docSyncId: String,
        opType: String,
        payload: Map<String, Any?>
    ) {
        val payloadJson = dataSyncGson.toJson(payload)
        database.syncOutboxDao().deleteByDocument(docType, docSyncId)
        database.syncOutboxDao().insert(
            SyncOutbox(
                docType = docType,
                docSyncId = docSyncId,
                opType = opType,
                payloadJson = payloadJson,
                contentHash = DataSyncCrypto.sha256Hex(payloadJson),
                createdAt = System.currentTimeMillis(),
                updatedAt = System.currentTimeMillis()
            )
        )
    }

    private fun messagePayload(message: Message): Map<String, Any?> = linkedMapOf(
        "syncId" to message.syncId,
        "messageId" to message.messageId,
        "type" to message.type,
        "user" to message.user,
        "content" to message.content,
        "createdAt" to message.createdAt,
        "updatedAt" to message.updatedAt
    )

    private fun favoritePayload(record: FavoriteRecord): Map<String, Any?> = linkedMapOf(
        "syncId" to record.syncId,
        "title" to record.title,
        "desc" to record.desc,
        "type" to record.type,
        "imagePath" to record.imagePath,
        "packageName" to record.packageName,
        "status" to record.status,
        "createdAt" to record.createdAt,
        "updatedAt" to record.updatedAt
    )

    private fun executionPayload(record: ExecutionRecord): Map<String, Any?> = linkedMapOf(
        "syncId" to record.syncId,
        "title" to record.title,
        "appName" to record.appName,
        "packageName" to record.packageName,
        "nodeId" to record.nodeId,
        "suggestionId" to record.suggestionId,
        "iconUrl" to record.iconUrl,
        "type" to record.type,
        "content" to record.content,
        "status" to record.status,
        "createdAt" to record.createdAt,
        "updatedAt" to record.updatedAt
    )

    private fun studyPayload(record: StudyRecord): Map<String, Any?> = linkedMapOf(
        "syncId" to record.syncId,
        "title" to record.title,
        "suggestionId" to record.suggestionId,
        "appName" to record.appName,
        "packageName" to record.packageName,
        "createdAt" to record.createdAt,
        "updatedAt" to record.updatedAt,
        "isFavorite" to record.isFavorite
    )

    private suspend fun currentMetadataWatermark(): Long {
        return listOfNotNull(
            database.conversationDao().getMaxUpdatedAt(),
            database.messageDao().getMaxUpdatedAt(),
            database.favoriteRecordDao().getMaxUpdatedAt(),
            database.executionRecordDao().getMaxUpdatedAt(),
            database.studyRecordDao().getMaxUpdatedAt(),
            database.agentConversationEntryDao().getMaxUpdatedAt(),
            database.tokenUsageRecordDao().getMaxCreatedAt()
        ).maxOrNull() ?: 0L
    }

    private suspend fun getCheckpoint(): SyncCheckpoint {
        return database.syncCheckpointDao().getByKey(DataSyncCheckpointKey.DEFAULT)
            ?: SyncCheckpoint(checkpointKey = DataSyncCheckpointKey.DEFAULT)
    }

    private suspend fun hasMaterialLocalState(): Boolean {
        if (database.conversationDao().getConversationCount() > 0) return true
        if (database.messageDao().getMessageCount() > 0) return true
        if (database.favoriteRecordDao().getAll().isNotEmpty()) return true
        if (database.executionRecordDao().getAll().isNotEmpty()) return true
        if (database.studyRecordDao().getAll().isNotEmpty()) return true
        return fileScanner.scanManagedFiles()
            .map { it.relativePath }
            .any {
                it !in setOf(
                    ".omnibot/agent/SOUL.md",
                    ".omnibot/agent/CHAT.md",
                    ".omnibot/memory/MEMORY.md"
                )
            }
    }

    private suspend fun buildStatus(base: DataSyncStatus, config: DataSyncConfig): DataSyncStatus {
        val checkpoint = getCheckpoint()
        return base.copy(
            enabled = config.enabled,
            configured = config.isConfigured(),
            namespace = config.namespace,
            deviceId = config.deviceId,
            remoteCursor = checkpoint.remoteCursor,
            pendingOutboxCount = database.syncOutboxDao().countAll(),
            openConflictCount = database.syncConflictRecordDao().countByStatus("open")
        )
    }

    private suspend fun updateStatus(
        config: DataSyncConfig,
        state: String,
        step: String,
        message: String,
        progress: DataSyncProgress = progressFor(step, message, 0, 100)
    ) {
        val status = buildStatus(statusStore.read(), config).copy(
            state = state,
            currentStep = step,
            lastSyncAt = System.currentTimeMillis(),
            lastMessage = message,
            progress = progress,
            updatedAt = System.currentTimeMillis()
        )
        statusStore.write(status)
    }

    private fun progressFor(stage: String, detail: String, completed: Int, total: Int): DataSyncProgress {
        val safeTotal = if (total <= 0) 100 else total
        val percent = ((completed.toDouble() / safeTotal.toDouble()) * 100.0).toInt()
            .coerceIn(0, 100)
        return DataSyncProgress(
            stage = stage,
            detail = detail,
            completed = completed,
            total = total,
            percent = percent,
            updatedAt = System.currentTimeMillis()
        )
    }

    private fun retryDelayMillis(attempts: Int): Long {
        val base = 15_000L
        val factor = 1L shl (attempts.coerceAtMost(6) - 1).coerceAtLeast(0)
        return (base * factor).coerceAtMost(60 * 60 * 1000L)
    }
}
