package cn.com.omnimind.bot.sync

import android.os.Build
import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import java.io.IOException
import java.util.UUID
import java.util.concurrent.TimeUnit
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

class DataSyncApiClient {
    companion object {
        private const val EDGE_BASE_PATH = "/functions/v1"
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    }

    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    internal fun handshake(config: DataSyncConfig): DataSyncHandshakeResponse {
        val response = postSignedFunction(
            config = config,
            functionName = "sync-handshake",
            body = linkedMapOf(
                "namespace" to config.namespace,
                "deviceId" to config.deviceId,
                "deviceName" to Build.MODEL.orEmpty(),
                "platform" to "android",
                "syncSecret" to config.syncSecret
            )
        )
        return DataSyncHandshakeResponse(
            namespace = response.get("namespace")?.asString ?: config.namespace,
            registered = response.get("registered")?.asBoolean == true,
            remoteCursor = response.get("remoteCursor")?.asLong ?: 0L
        )
    }

    internal fun pushChanges(
        config: DataSyncConfig,
        operations: List<Map<String, Any?>>
    ): DataSyncPushResponse {
        val response = postSignedFunction(
            config = config,
            functionName = "sync-push",
            body = linkedMapOf(
                "namespace" to config.namespace,
                "deviceId" to config.deviceId,
                "operations" to operations
            )
        )
        val acknowledged = response.getAsJsonArray("acknowledgedOpIds")
            ?.mapNotNull { it?.asString }
            .orEmpty()
        return DataSyncPushResponse(
            acknowledgedOpIds = acknowledged,
            cursor = response.get("cursor")?.asLong ?: 0L
        )
    }

    internal fun pullChanges(
        config: DataSyncConfig,
        cursor: Long,
        limit: Int
    ): DataSyncPullResponse {
        val response = postSignedFunction(
            config = config,
            functionName = "sync-pull",
            body = linkedMapOf(
                "namespace" to config.namespace,
                "deviceId" to config.deviceId,
                "cursor" to cursor,
                "limit" to limit
            )
        )
        val changes = response.getAsJsonArray("changes")
            ?.let(::parseChanges)
            .orEmpty()
        return DataSyncPullResponse(
            nextCursor = response.get("nextCursor")?.asLong ?: cursor,
            changes = changes
        )
    }

    private fun parseChanges(array: JsonArray): List<DataSyncRemoteChange> {
        return array.mapNotNull { element ->
            val obj = element?.asJsonObject ?: return@mapNotNull null
            val payload = obj.get("payload")
            val payloadMap = if (payload != null && payload.isJsonObject) {
                @Suppress("UNCHECKED_CAST")
                dataSyncGson.fromJson(payload, dataSyncMapType) as Map<String, Any?>
            } else {
                emptyMap()
            }
            DataSyncRemoteChange(
                cursor = obj.get("cursor")?.asLong ?: 0L,
                docType = obj.get("docType")?.asString.orEmpty(),
                docSyncId = obj.get("docSyncId")?.asString.orEmpty(),
                opId = obj.get("opId")?.asString.orEmpty(),
                opType = obj.get("opType")?.asString.orEmpty(),
                contentHash = obj.get("contentHash")?.asString.orEmpty(),
                deviceId = obj.get("deviceId")?.asString.orEmpty(),
                payload = payloadMap
            )
        }
    }

    private fun postSignedFunction(
        config: DataSyncConfig,
        functionName: String,
        body: Map<String, Any?>
    ): JsonObject {
        val bodyJson = dataSyncGson.toJson(body)
        val url = "${config.supabaseUrl}$EDGE_BASE_PATH/$functionName"
        val uri = java.net.URI(url)
        val bodyHash = DataSyncCrypto.sha256Hex(bodyJson)
        val timestamp = System.currentTimeMillis().toString()
        val nonce = UUID.randomUUID().toString()
        val signature = DataSyncCrypto.signRequest(
            secret = config.syncSecret,
            method = "POST",
            path = uri.rawPath,
            timestamp = timestamp,
            nonce = nonce,
            bodyHash = bodyHash
        )
        val request = Request.Builder()
            .url(url)
            .post(bodyJson.toRequestBody(JSON_MEDIA_TYPE))
            .addHeader("Content-Type", JSON_MEDIA_TYPE.toString())
            .addHeader("Authorization", "Bearer ${config.anonKey}")
            .addHeader("apikey", config.anonKey)
            .addHeader("x-sync-namespace", config.namespace)
            .addHeader("x-sync-device-id", config.deviceId)
            .addHeader("x-sync-timestamp", timestamp)
            .addHeader("x-sync-nonce", nonce)
            .addHeader("x-sync-body-hash", bodyHash)
            .addHeader("x-sync-signature", signature)
            .build()
        client.newCall(request).execute().use { response ->
            val responseBody = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                throw IOException("Sync function $functionName failed (${response.code}): $responseBody")
            }
            return JsonParser.parseString(responseBody).asJsonObject
        }
    }
}
