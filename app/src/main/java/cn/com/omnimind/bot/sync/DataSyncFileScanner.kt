package cn.com.omnimind.bot.sync

import android.content.Context
import cn.com.omnimind.bot.agent.AgentWorkspaceManager
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class DataSyncFileScanner(
    context: Context
) {
    companion object {
        private val DATE_FORMAT = SimpleDateFormat("yyyyMMddHHmmss", Locale.US)
        private val EXCLUDED_PATH_PREFIXES = listOf(
            ".omnibot/models/",
            ".omnibot/cache/",
            ".omnibot/logs/",
            ".omnibot/downloads/",
            ".omnibot/tmp/",
            ".omnibot/temp/"
        )
        private val EXCLUDED_SEGMENTS = setOf("cache", "caches", "logs", "tmp", "temp", "downloads")
        private val IGNORED_FILES = setOf(".workspace_migrated_v1")
    }

    private val workspaceManager = AgentWorkspaceManager(context.applicationContext)
    private val rootDir = AgentWorkspaceManager.rootDirectory(context.applicationContext)

    fun rootDirectory(): File {
        workspaceManager.ensureRuntimeDirectories()
        return rootDir
    }

    internal fun scanManagedFiles(): List<DataSyncManagedFile> {
        val root = rootDirectory().canonicalFile
        if (!root.exists()) {
            return emptyList()
        }
        return root.walkTopDown()
            .filter { it.isFile }
            .filterNot { shouldExclude(it, root) }
            .map { file ->
                val canonical = file.canonicalFile
                DataSyncManagedFile(
                    relativePath = canonical.relativeTo(root).invariantSeparatorsPath,
                    absolutePath = canonical.absolutePath,
                    contentHash = DataSyncCrypto.sha256Hex(canonical),
                    sizeBytes = canonical.length(),
                    lastModifiedAt = canonical.lastModified()
                )
            }
            .sortedBy { it.relativePath }
            .toList()
    }

    fun resolveManagedFile(relativePath: String): File {
        val normalized = relativePath.trim().removePrefix("/")
        require(normalized.isNotBlank()) { "relativePath is blank" }
        val target = File(rootDirectory(), normalized).canonicalFile
        require(target.absolutePath.startsWith(rootDirectory().canonicalPath)) {
            "Managed path escapes workspace root: $relativePath"
        }
        return target
    }

    fun buildConflictCopy(file: File, deviceId: String, timestamp: Long = System.currentTimeMillis()): File {
        val safeDeviceId = deviceId.trim().ifBlank { "remote" }
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .take(24)
        val suffix = ".conflict.$safeDeviceId.${DATE_FORMAT.format(Date(timestamp))}"
        return File(file.parentFile, file.name + suffix)
    }

    private fun shouldExclude(file: File, root: File): Boolean {
        val relativePath = file.relativeTo(root).invariantSeparatorsPath
        if (relativePath.isBlank()) return true
        if (IGNORED_FILES.contains(relativePath.substringAfterLast('/'))) return true
        if (EXCLUDED_PATH_PREFIXES.any { relativePath.startsWith(it) }) return true
        return relativePath.split('/').any { segment -> EXCLUDED_SEGMENTS.contains(segment.lowercase(Locale.US)) }
    }
}
