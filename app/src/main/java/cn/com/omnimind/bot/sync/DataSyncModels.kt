package cn.com.omnimind.bot.sync

import com.google.gson.Gson
import com.google.gson.reflect.TypeToken

object DataSyncDocType {
    const val CONVERSATION = "conversation"
    const val MESSAGE = "message"
    const val FAVORITE_RECORD = "favorite_record"
    const val EXECUTION_RECORD = "execution_record"
    const val STUDY_RECORD = "study_record"
    const val TOKEN_USAGE_RECORD = "token_usage_record"
    const val AGENT_CONVERSATION_ENTRY = "agent_conversation_entry"
    const val SETTINGS_SNAPSHOT = "settings_snapshot"
    const val FILE = "file"
}

object DataSyncOpType {
    const val UPSERT = "upsert"
    const val DELETE = "delete"
}

object DataSyncCheckpointKey {
    const val DEFAULT = "default"
}

object DataSyncState {
    const val DISABLED = "disabled"
    const val IDLE = "idle"
    const val SYNCING = "syncing"
    const val SUCCESS = "success"
    const val ERROR = "error"
}

data class DataSyncConfig(
    val enabled: Boolean = false,
    val supabaseUrl: String = "",
    val anonKey: String = "",
    val namespace: String = "",
    val syncSecret: String = "",
    val s3Endpoint: String = "",
    val region: String = "",
    val bucket: String = "",
    val accessKey: String = "",
    val secretKey: String = "",
    val sessionToken: String = "",
    val forcePathStyle: Boolean = true,
    val deviceId: String = "",
    val updatedAt: Long = System.currentTimeMillis()
) {
    fun isConfigured(): Boolean {
        return supabaseUrl.isNotBlank() &&
            anonKey.isNotBlank() &&
            namespace.isNotBlank() &&
            syncSecret.isNotBlank() &&
            s3Endpoint.isNotBlank() &&
            region.isNotBlank() &&
            bucket.isNotBlank() &&
            accessKey.isNotBlank() &&
            secretKey.isNotBlank() &&
            deviceId.isNotBlank()
    }

    fun sanitized(): DataSyncConfig {
        return copy(
            supabaseUrl = supabaseUrl.trim().trimEnd('/'),
            anonKey = anonKey.trim(),
            namespace = namespace.trim(),
            syncSecret = syncSecret.trim(),
            s3Endpoint = s3Endpoint.trim().trimEnd('/'),
            region = region.trim(),
            bucket = bucket.trim(),
            accessKey = accessKey.trim(),
            secretKey = secretKey.trim(),
            sessionToken = sessionToken.trim(),
            deviceId = deviceId.trim(),
            updatedAt = System.currentTimeMillis()
        )
    }

    fun withoutSecrets(): DataSyncConfig {
        return copy(
            anonKey = maskSecret(anonKey),
            syncSecret = maskSecret(syncSecret),
            accessKey = maskSecret(accessKey),
            secretKey = maskSecret(secretKey),
            sessionToken = maskSecret(sessionToken)
        )
    }

    fun toMap(includeSecrets: Boolean = true): Map<String, Any?> {
        val view = if (includeSecrets) this else withoutSecrets()
        return linkedMapOf(
            "enabled" to view.enabled,
            "configured" to isConfigured(),
            "supabaseUrl" to view.supabaseUrl,
            "anonKey" to view.anonKey,
            "namespace" to view.namespace,
            "syncSecret" to view.syncSecret,
            "s3Endpoint" to view.s3Endpoint,
            "region" to view.region,
            "bucket" to view.bucket,
            "accessKey" to view.accessKey,
            "secretKey" to view.secretKey,
            "sessionToken" to view.sessionToken,
            "forcePathStyle" to view.forcePathStyle,
            "deviceId" to view.deviceId,
            "updatedAt" to view.updatedAt
        )
    }

    companion object {
        fun fromMap(raw: Map<String, Any?>): DataSyncConfig {
            return DataSyncConfig(
                enabled = raw["enabled"] == true,
                supabaseUrl = raw["supabaseUrl"]?.toString().orEmpty(),
                anonKey = raw["anonKey"]?.toString().orEmpty(),
                namespace = raw["namespace"]?.toString().orEmpty(),
                syncSecret = raw["syncSecret"]?.toString().orEmpty(),
                s3Endpoint = raw["s3Endpoint"]?.toString().orEmpty(),
                region = raw["region"]?.toString().orEmpty(),
                bucket = raw["bucket"]?.toString().orEmpty(),
                accessKey = raw["accessKey"]?.toString().orEmpty(),
                secretKey = raw["secretKey"]?.toString().orEmpty(),
                sessionToken = raw["sessionToken"]?.toString().orEmpty(),
                forcePathStyle = raw["forcePathStyle"] != false,
                deviceId = raw["deviceId"]?.toString().orEmpty(),
                updatedAt = raw["updatedAt"].toLongValue(System.currentTimeMillis())
            ).sanitized()
        }
    }
}

data class DataSyncProgress(
    val stage: String = "",
    val detail: String = "",
    val completed: Int = 0,
    val total: Int = 0,
    val percent: Int = 0,
    val updatedAt: Long = System.currentTimeMillis()
) {
    fun toMap(): Map<String, Any?> = linkedMapOf(
        "stage" to stage,
        "detail" to detail,
        "completed" to completed,
        "total" to total,
        "percent" to percent,
        "updatedAt" to updatedAt
    )

    companion object {
        fun fromMap(raw: Map<String, Any?>): DataSyncProgress {
            return DataSyncProgress(
                stage = raw["stage"]?.toString().orEmpty(),
                detail = raw["detail"]?.toString().orEmpty(),
                completed = raw["completed"].toIntValue(),
                total = raw["total"].toIntValue(),
                percent = raw["percent"].toIntValue(),
                updatedAt = raw["updatedAt"].toLongValue(System.currentTimeMillis())
            )
        }
    }
}

data class DataSyncStatus(
    val enabled: Boolean = false,
    val configured: Boolean = false,
    val state: String = DataSyncState.DISABLED,
    val namespace: String = "",
    val deviceId: String = "",
    val lastSyncAt: Long = 0,
    val lastSuccessAt: Long = 0,
    val remoteCursor: Long = 0,
    val pendingOutboxCount: Int = 0,
    val openConflictCount: Int = 0,
    val lastError: String = "",
    val lastMessage: String = "",
    val currentStep: String = "",
    val progress: DataSyncProgress = DataSyncProgress(),
    val updatedAt: Long = System.currentTimeMillis()
) {
    fun toMap(): Map<String, Any?> = linkedMapOf(
        "enabled" to enabled,
        "configured" to configured,
        "state" to state,
        "namespace" to namespace,
        "deviceId" to deviceId,
        "lastSyncAt" to lastSyncAt,
        "lastSuccessAt" to lastSuccessAt,
        "remoteCursor" to remoteCursor,
        "pendingOutboxCount" to pendingOutboxCount,
        "openConflictCount" to openConflictCount,
        "lastError" to lastError,
        "lastMessage" to lastMessage,
        "currentStep" to currentStep,
        "progress" to progress.toMap(),
        "updatedAt" to updatedAt
    )

    companion object {
        fun fromMap(raw: Map<String, Any?>): DataSyncStatus {
            val progressMap = raw["progress"] as? Map<*, *>
            return DataSyncStatus(
                enabled = raw["enabled"] == true,
                configured = raw["configured"] == true,
                state = raw["state"]?.toString() ?: DataSyncState.DISABLED,
                namespace = raw["namespace"]?.toString().orEmpty(),
                deviceId = raw["deviceId"]?.toString().orEmpty(),
                lastSyncAt = raw["lastSyncAt"].toLongValue(),
                lastSuccessAt = raw["lastSuccessAt"].toLongValue(),
                remoteCursor = raw["remoteCursor"].toLongValue(),
                pendingOutboxCount = raw["pendingOutboxCount"].toIntValue(),
                openConflictCount = raw["openConflictCount"].toIntValue(),
                lastError = raw["lastError"]?.toString().orEmpty(),
                lastMessage = raw["lastMessage"]?.toString().orEmpty(),
                currentStep = raw["currentStep"]?.toString().orEmpty(),
                progress = if (progressMap != null) {
                    @Suppress("UNCHECKED_CAST")
                    DataSyncProgress.fromMap(progressMap as Map<String, Any?>)
                } else {
                    DataSyncProgress()
                },
                updatedAt = raw["updatedAt"].toLongValue(System.currentTimeMillis())
            )
        }
    }
}

data class DataSyncConflictItem(
    val id: Long,
    val relativePath: String,
    val localHash: String,
    val remoteHash: String,
    val remoteObjectKey: String,
    val conflictCopyPath: String,
    val status: String,
    val createdAt: Long,
    val updatedAt: Long
) {
    fun toMap(): Map<String, Any?> = linkedMapOf(
        "id" to id,
        "relativePath" to relativePath,
        "localHash" to localHash,
        "remoteHash" to remoteHash,
        "remoteObjectKey" to remoteObjectKey,
        "conflictCopyPath" to conflictCopyPath,
        "status" to status,
        "createdAt" to createdAt,
        "updatedAt" to updatedAt
    )
}

data class DataSyncPairingPayload(
    val encodedPayload: String,
    val namespace: String,
    val createdAt: Long = System.currentTimeMillis()
) {
    fun toMap(): Map<String, Any?> = linkedMapOf(
        "encodedPayload" to encodedPayload,
        "namespace" to namespace,
        "createdAt" to createdAt
    )
}

internal data class DataSyncManagedFile(
    val relativePath: String,
    val absolutePath: String,
    val contentHash: String,
    val sizeBytes: Long,
    val lastModifiedAt: Long
)

internal data class DataSyncOutboxDocument(
    val docType: String,
    val docSyncId: String,
    val opType: String,
    val payload: Map<String, Any?>,
    val contentHash: String
)

internal data class DataSyncRemoteChange(
    val cursor: Long,
    val docType: String,
    val docSyncId: String,
    val opId: String,
    val opType: String,
    val contentHash: String,
    val deviceId: String,
    val payload: Map<String, Any?>
)

internal data class DataSyncPullResponse(
    val nextCursor: Long,
    val changes: List<DataSyncRemoteChange>
)

internal data class DataSyncPushResponse(
    val acknowledgedOpIds: List<String>,
    val cursor: Long
)

internal data class DataSyncHandshakeResponse(
    val namespace: String,
    val registered: Boolean,
    val remoteCursor: Long
)

internal fun objectKeyForHash(namespace: String, hash: String): String {
    return "namespaces/${namespace.trim()}/objects/${hash.trim()}"
}

internal fun maskSecret(raw: String): String {
    if (raw.isBlank()) return ""
    return if (raw.length <= 8) {
        "••••"
    } else {
        raw.take(4) + "••••" + raw.takeLast(4)
    }
}

internal fun Any?.toLongValue(defaultValue: Long = 0L): Long {
    return when (this) {
        is Long -> this
        is Int -> this.toLong()
        is Double -> this.toLong()
        is Float -> this.toLong()
        is Number -> this.toLong()
        is String -> this.toLongOrNull() ?: defaultValue
        else -> defaultValue
    }
}

internal fun Any?.toIntValue(defaultValue: Int = 0): Int {
    return when (this) {
        is Int -> this
        is Long -> this.toInt()
        is Double -> this.toInt()
        is Float -> this.toInt()
        is Number -> this.toInt()
        is String -> this.toIntOrNull() ?: defaultValue
        else -> defaultValue
    }
}

internal val dataSyncMapType = object : TypeToken<Map<String, Any?>>() {}.type
internal val dataSyncListType = object : TypeToken<List<Map<String, Any?>>>() {}.type
internal val dataSyncGson: Gson = Gson()
