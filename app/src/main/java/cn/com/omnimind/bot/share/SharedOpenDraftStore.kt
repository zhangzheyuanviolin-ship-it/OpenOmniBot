package cn.com.omnimind.bot.share

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import cn.com.omnimind.baselib.util.OmniLog
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

data class SharedOpenDraftAttachment(
    val id: String,
    val name: String,
    val path: String,
    val size: Long?,
    val mimeType: String?,
    val isImage: Boolean,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "name" to name,
        "path" to path,
        "size" to size,
        "mimeType" to mimeType,
        "isImage" to isImage,
    )

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("name", name)
        put("path", path)
        put("size", size)
        put("mimeType", mimeType)
        put("isImage", isImage)
    }
}

data class SharedOpenDraft(
    val requestKey: String,
    val text: String?,
    val attachments: List<SharedOpenDraftAttachment>,
    val createdAt: Long,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "requestKey" to requestKey,
        "text" to text,
        "createdAt" to createdAt,
        "attachments" to attachments.map { it.toMap() },
    )

    fun toJson(): JSONObject = JSONObject().apply {
        put("requestKey", requestKey)
        put("text", text)
        put("createdAt", createdAt)
        put(
            "attachments",
            JSONArray().apply {
                attachments.forEach { put(it.toJson()) }
            },
        )
    }
}

object SharedOpenDraftStore {
    private const val TAG = "[SharedOpenDraftStore]"
    private const val PREFS_NAME = "shared_open_draft"
    private const val KEY_PENDING_DRAFT = "pending_draft"
    private const val DIR_NAME = "shared_open_drafts"
    private const val FILE_RETENTION_MS = 3L * 24L * 60L * 60L * 1000L

    fun store(
        context: Context,
        text: String?,
        imageUris: List<Uri>,
        mimeTypeHint: String? = null,
    ): SharedOpenDraft? {
        cleanupStaleFiles(context)
        val now = System.currentTimeMillis()
        val normalizedText = text?.trim()?.ifEmpty { null }
        val attachments = imageUris.mapNotNull { uri ->
            copyImageToLocalDraft(context, uri, mimeTypeHint)
        }
        if (normalizedText == null && attachments.isEmpty()) {
            return null
        }

        val draft = SharedOpenDraft(
            requestKey = now.toString(),
            text = normalizedText,
            attachments = attachments,
            createdAt = now,
        )

        prefs(context)
            .edit()
            .putString(KEY_PENDING_DRAFT, draft.toJson().toString())
            .apply()
        return draft
    }

    fun consume(context: Context): Map<String, Any?>? {
        val raw = prefs(context).getString(KEY_PENDING_DRAFT, null) ?: return null
        prefs(context).edit().remove(KEY_PENDING_DRAFT).apply()
        return runCatching {
            fromJson(JSONObject(raw)).toMap()
        }.onFailure { error ->
            OmniLog.e(TAG, "Failed to consume shared draft", error)
        }.getOrNull()
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun copyImageToLocalDraft(
        context: Context,
        uri: Uri,
        mimeTypeHint: String?,
    ): SharedOpenDraftAttachment? {
        val resolver = context.contentResolver
        val meta = queryMeta(context, uri)
        val mimeType = resolver.getType(uri) ?: mimeTypeHint
        val baseName = meta.displayName ?: "shared_image_${System.currentTimeMillis()}"
        val fileName = ensureExtension(sanitizeFileName(baseName), mimeType)
        val dir = File(context.filesDir, DIR_NAME)
        if (!dir.exists() && !dir.mkdirs()) {
            OmniLog.e(TAG, "Failed to create shared draft dir: ${dir.absolutePath}")
            return null
        }

        val localId = UUID.randomUUID().toString()
        val target = File(dir, "${localId}_$fileName")
        val size = try {
            val input = resolver.openInputStream(uri) ?: return null
            input.use { source ->
                target.outputStream().use { sink ->
                    source.copyTo(sink)
                }
            }
            target.length()
        } catch (error: Exception) {
            OmniLog.e(TAG, "Failed to copy shared image uri=$uri", error)
            runCatching { target.delete() }
            return null
        }

        return SharedOpenDraftAttachment(
            id = localId,
            name = fileName,
            path = target.absolutePath,
            size = if (size > 0) size else meta.size,
            mimeType = mimeType,
            isImage = true,
        )
    }

    private fun cleanupStaleFiles(context: Context) {
        val dir = File(context.filesDir, DIR_NAME)
        val files = dir.listFiles() ?: return
        val now = System.currentTimeMillis()
        files.forEach { file ->
            if (now - file.lastModified() > FILE_RETENTION_MS) {
                runCatching { file.delete() }
            }
        }
    }

    private fun queryMeta(context: Context, uri: Uri): DraftFileMeta {
        var displayName: String? = null
        var size: Long? = null
        val cursor = context.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null,
        )
        cursor?.use {
            if (it.moveToFirst()) {
                val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = it.getColumnIndex(OpenableColumns.SIZE)
                if (nameIndex >= 0) {
                    displayName = it.getString(nameIndex)
                }
                if (sizeIndex >= 0) {
                    size = it.getLong(sizeIndex)
                }
            }
        }
        return DraftFileMeta(displayName = displayName, size = size)
    }

    private fun sanitizeFileName(name: String): String {
        val trimmed = name.trim().ifEmpty { "shared_image" }
        return trimmed.replace(Regex("[\\\\/:*?\"<>|]"), "_")
    }

    private fun ensureExtension(name: String, mimeType: String?): String {
        if (name.contains('.')) return name
        if (mimeType.isNullOrBlank()) return name
        val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
        return if (extension.isNullOrBlank()) name else "$name.$extension"
    }

    private fun fromJson(json: JSONObject): SharedOpenDraft {
        val attachmentsJson = json.optJSONArray("attachments") ?: JSONArray()
        val attachments = buildList {
            for (index in 0 until attachmentsJson.length()) {
                val item = attachmentsJson.optJSONObject(index) ?: continue
                add(
                    SharedOpenDraftAttachment(
                        id = item.optString("id"),
                        name = item.optString("name"),
                        path = item.optString("path"),
                        size = item.takeIf { !it.isNull("size") }?.optLong("size"),
                        mimeType = item.optString("mimeType").ifBlank { null },
                        isImage = item.optBoolean("isImage", false),
                    ),
                )
            }
        }
        return SharedOpenDraft(
            requestKey = json.optString("requestKey"),
            text = json.optString("text").ifBlank { null },
            attachments = attachments,
            createdAt = json.optLong("createdAt"),
        )
    }

    private data class DraftFileMeta(
        val displayName: String?,
        val size: Long?,
    )
}
