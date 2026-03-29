package cn.com.omnimind.bot.agent

import android.content.Context
import android.net.Uri
import java.io.File
import java.nio.charset.Charset
import java.security.MessageDigest
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.UUID

class AgentWorkspaceManager(
    private val context: Context
) {
    companion object {
        const val SHELL_ROOT_PATH = "/workspace"
        const val URI_SCHEME = "omnibot"

        const val LEGACY_EXTERNAL_ROOT_PATH = "/storage/emulated/0/workspace"

        private const val ROOT_DIR_NAME = "workspace"
        private const val INTERNAL_DIR = ".omnibot"
        private const val WORKSPACE_MIGRATION_MARKER = ".workspace_migrated_v1"
        private const val DIR_ATTACHMENTS = "attachments"
        private const val DIR_WORKSPACE = "workspace"
        private const val DIR_SHARED = "shared"
        private const val DIR_OFFLOADS = "offloads"
        private const val DIR_BROWSER = "browser"
        private const val DIR_SKILLS = "skills"
        private const val DIR_MEMORY = "memory"
        private const val DIR_AGENT = "agent"
        private const val FILE_AI_CONFIG = "config.json"
        private const val FILE_SOUL = "SOUL.md"
        private const val FILE_MEMORY = "MEMORY.md"
        private const val DIR_SHORT_MEMORIES = "short-memories"
        private const val DIR_MEMORY_INDEX = "index"

        fun rootDirectory(context: Context): File {
            return File(context.applicationInfo.dataDir, ROOT_DIR_NAME)
        }

        fun internalRootDirectory(context: Context): File {
            return File(rootDirectory(context), INTERNAL_DIR)
        }

        fun androidRootPath(context: Context): String {
            return rootDirectory(context).absolutePath
        }

        fun internalRootPath(context: Context): String {
            return internalRootDirectory(context).absolutePath
        }

        fun workspacePathSnapshot(context: Context): Map<String, String> {
            return linkedMapOf(
                "rootPath" to androidRootPath(context),
                "shellRootPath" to SHELL_ROOT_PATH,
                "internalRootPath" to internalRootPath(context)
            )
        }
    }

    private val rootDir = rootDirectory(context)
    private val legacyInternalRootDir = File(context.applicationContext.filesDir, ROOT_DIR_NAME)
    private val internalDir = File(rootDir, INTERNAL_DIR)
    private val attachmentsDir = File(internalDir, DIR_ATTACHMENTS)
    private val sharedDir = File(internalDir, DIR_SHARED)
    private val offloadsDir = File(internalDir, DIR_OFFLOADS)
    private val browserDir = File(internalDir, DIR_BROWSER)
    private val skillsDir = File(internalDir, DIR_SKILLS)
    private val memoryDir = File(internalDir, DIR_MEMORY)
    private val agentDir = File(internalDir, DIR_AGENT)
    private val soulFile = File(agentDir, FILE_SOUL)
    private val longMemoryFile = File(memoryDir, FILE_MEMORY)
    private val shortMemoriesDir = File(memoryDir, DIR_SHORT_MEMORIES)
    private val memoryIndexDir = File(memoryDir, DIR_MEMORY_INDEX)
    private val migrationMarker = File(internalDir, WORKSPACE_MIGRATION_MARKER)
    private val legacyRootDir = File(LEGACY_EXTERNAL_ROOT_PATH)

    fun ensureRuntimeDirectories() {
        migrateLegacyWorkspaceIfNeeded()
        listOf(
            rootDir,
            internalDir,
            attachmentsDir,
            sharedDir,
            offloadsDir,
            browserDir,
            skillsDir,
            memoryDir,
            agentDir,
            shortMemoriesDir,
            memoryIndexDir
        ).forEach { directory ->
            if (!directory.exists()) {
                directory.mkdirs()
            }
        }
        ensureDefaultWorkspaceDocs()
    }

    private fun ensureDefaultWorkspaceDocs() {
        if (!soulFile.exists()) {
            soulFile.parentFile?.mkdirs()
            soulFile.writeText(defaultSoulTemplate())
        }
        if (!longMemoryFile.exists()) {
            longMemoryFile.parentFile?.mkdirs()
            longMemoryFile.writeText(defaultLongMemoryTemplate())
        }
    }

    private fun defaultSoulTemplate(): String {
        return """
            # SOUL

            你是 Omnibot 的 Agent 灵魂设定文件。系统会把本文件注入到 system prompt 中。
            你可以根据用户明确授权更新本文件，以持续优化行为。

            ## 身份
            - 你是值得信赖的智能助手，优先帮助用户把事情做完。
            - 你会基于事实与工具结果回答，不编造不可验证信息。

            ## 语气
            - 简洁、温和、可执行。
            - 优先给出结论，再补充必要细节。

            ## 行为边界
            - 涉及隐私、删除、支付、外发信息时先确认。
            - 不擅自泄露密钥、个人信息或工作区敏感文件。
            - 不使用破坏性命令，除非用户明确授权。

            ## 记忆协作
            - 长期稳定偏好写入 `.omnibot/memory/MEMORY.md`。
            - 当日过程性信息写入 `.omnibot/memory/short-memories/YY-MM-DD.md`。
            - 每晚整理后再决定是否沉淀为长期记忆。

            ## 自我更新规则
            - 只有在用户明确同意“更新灵魂/SOUL”时，才能改写本文件。
            - 更新时保留“身份、语气、边界”三部分结构，避免漂移。
            - 每次更新应可解释：为什么改、改了什么、预期影响。
        """.trimIndent() + "\n"
    }

    private fun defaultLongMemoryTemplate(): String {
        return """
            # MEMORY

            这是长期静态记忆区，用于存储跨会话稳定偏好与长期约束。

            ## 使用约定
            - 仅记录长期稳定且对后续任务有价值的信息。
            - 避免记录一次性临时细节。
            - 每条尽量一句话，必要时加日期来源。

            ## 长期记忆
            - （暂无）
        """.trimIndent() + "\n"
    }

    private fun migrateLegacyWorkspaceIfNeeded() {
        if (migrationMarker.exists()) {
            return
        }
        runCatching {
            rootDir.mkdirs()
            val migrationSources = buildList {
                val internalLegacy = legacyInternalRootDir
                if (
                    internalLegacy.exists() &&
                    internalLegacy.canonicalPath != rootDir.canonicalPath
                ) {
                    add(internalLegacy)
                }
                val externalLegacy = legacyRootDir
                if (externalLegacy.exists()) {
                    add(externalLegacy)
                }
            }
            migrationSources.forEach { source ->
                source.listFiles()?.forEach { child ->
                    val target = File(rootDir, child.name)
                    if (!target.exists()) {
                        child.copyRecursively(target, overwrite = false)
                    }
                }
            }
            markMigrationCompleted()
        }
    }

    private fun markMigrationCompleted() {
        if (!internalDir.exists()) {
            internalDir.mkdirs()
        }
        runCatching {
            migrationMarker.writeText("migrated=true\n")
        }
    }

    fun skillsRoot(): File {
        ensureRuntimeDirectories()
        return skillsDir
    }

    fun buildWorkspaceDescriptor(
        conversationId: Long?,
        agentRunId: String
    ): AgentWorkspaceDescriptor {
        ensureRuntimeDirectories()
        val conversationKey = conversationKey(conversationId)
        val workspaceRoot = rootDir.canonicalFile
        val uriRoot = uriForFile(workspaceRoot) ?: buildRootUri("workspace")
        return AgentWorkspaceDescriptor(
            id = conversationKey,
            rootPath = SHELL_ROOT_PATH,
            androidRootPath = workspaceRoot.absolutePath,
            uriRoot = uriRoot,
            currentCwd = SHELL_ROOT_PATH,
            androidCurrentCwd = workspaceRoot.absolutePath,
            shellRootPath = SHELL_ROOT_PATH,
            retentionPolicy = "shared_root"
        )
    }

    fun offloadsDirectory(agentRunId: String): File {
        ensureRuntimeDirectories()
        return File(offloadsDir, sanitizeSegment(agentRunId)).apply { mkdirs() }
    }

    fun browserDirectory(agentRunId: String): File {
        ensureRuntimeDirectories()
        return File(browserDir, sanitizeSegment(agentRunId)).apply { mkdirs() }
    }

    fun newOffloadFile(
        agentRunId: String,
        prefix: String,
        extension: String
    ): File {
        return newManagedFile(
            parent = offloadsDirectory(agentRunId),
            prefix = prefix,
            extension = extension
        )
    }

    fun newBrowserFile(
        agentRunId: String,
        prefix: String,
        extension: String
    ): File {
        return newManagedFile(
            parent = browserDirectory(agentRunId),
            prefix = prefix,
            extension = extension
        )
    }

    fun attachmentsDirectory(): File {
        ensureRuntimeDirectories()
        return attachmentsDir
    }

    fun sharedDirectory(): File {
        ensureRuntimeDirectories()
        return sharedDir
    }

    fun agentDirectory(): File {
        ensureRuntimeDirectories()
        return agentDir
    }

    fun soulMarkdownFile(): File {
        ensureRuntimeDirectories()
        return soulFile
    }

    fun agentConfigFile(): File {
        ensureRuntimeDirectories()
        return File(agentDir, FILE_AI_CONFIG)
    }

    fun longTermMemoryMarkdownFile(): File {
        ensureRuntimeDirectories()
        return longMemoryFile
    }

    fun shortMemoriesDirectory(): File {
        ensureRuntimeDirectories()
        return shortMemoriesDir
    }

    fun memoryIndexDirectory(): File {
        ensureRuntimeDirectories()
        return memoryIndexDir
    }

    fun dailyShortMemoryFile(date: LocalDate): File {
        ensureRuntimeDirectories()
        val fileName = date.format(DateTimeFormatter.ofPattern("yy-MM-dd")) + ".md"
        return File(shortMemoriesDir, fileName)
    }

    fun writeOffload(
        agentRunId: String,
        extension: String,
        content: String
    ): ArtifactRef {
        val target = newOffloadFile(
            agentRunId = agentRunId,
            prefix = "offload",
            extension = extension
        )
        target.writeText(content)
        return buildArtifactForFile(
            file = target,
            sourceTool = "offload",
            title = target.name
        )
    }

    fun buildArtifactForFile(
        file: File,
        sourceTool: String,
        title: String = file.name,
        actions: List<ArtifactAction> = defaultActionsForFile(file)
    ): ArtifactRef {
        ensureRuntimeDirectories()
        val canonical = file.canonicalFile
        require(isWithinRoot(canonical)) { "File must stay inside omnibot root" }
        if (canonical.parentFile?.exists() != true) {
            canonical.parentFile?.mkdirs()
        }
        val uri = uriForFile(canonical)
            ?: throw IllegalArgumentException("Unsupported artifact location: ${canonical.absolutePath}")
        return ArtifactRef(
            id = stableIdForPath(canonical.absolutePath),
            uri = uri,
            title = title,
            mimeType = guessMimeType(canonical),
            size = canonical.length(),
            sourceTool = sourceTool,
            workspacePath = shellPathForAndroid(canonical) ?: canonical.absolutePath,
            androidPath = canonical.absolutePath,
            previewKind = previewKindForMime(guessMimeType(canonical)),
            actions = actions
        )
    }

    fun resolvePath(
        inputPath: String,
        workspace: AgentWorkspaceDescriptor,
        allowRootDirectories: Boolean = false
    ): File {
        ensureRuntimeDirectories()
        val trimmed = inputPath.trim()
        require(trimmed.isNotEmpty()) { "path 不能为空" }

        val resolved = when {
            trimmed.startsWith("$URI_SCHEME://") -> resolveUri(trimmed)
            trimmed.startsWith("$SHELL_ROOT_PATH/") || trimmed == SHELL_ROOT_PATH -> {
                androidPathForShell(trimmed)
                    ?: throw IllegalArgumentException("无法解析 shell 路径：$inputPath")
            }
            trimmed.startsWith("/") -> File(trimmed)
            else -> File(workspace.androidCurrentCwd, trimmed)
        }.canonicalFile

        val allowed = if (allowRootDirectories) {
            isWithinRoot(resolved)
        } else {
            isWithinWritableRoots(resolved, workspace)
        }
        require(allowed) { "路径超出允许范围：$inputPath" }
        return resolved
    }

    fun shellPathForAndroid(file: File): String? {
        val canonical = file.canonicalFile
        if (!isWithinRoot(canonical)) return null
        val relative = canonical.absolutePath.removePrefix(rootDir.canonicalPath).trimStart('/')
        return if (relative.isBlank()) {
            SHELL_ROOT_PATH
        } else {
            "$SHELL_ROOT_PATH/$relative"
        }
    }

    fun androidPathForShell(shellPath: String): File? {
        val trimmed = shellPath.trim()
        if (!(trimmed == SHELL_ROOT_PATH || trimmed.startsWith("$SHELL_ROOT_PATH/"))) {
            return null
        }
        val relative = trimmed.removePrefix(SHELL_ROOT_PATH).trimStart('/')
        return if (relative.isBlank()) {
            rootDir
        } else {
            File(rootDir, relative)
        }
    }

    fun resolveShellPath(
        inputPath: String,
        workspace: AgentWorkspaceDescriptor,
        allowRootDirectories: Boolean = false
    ): String {
        val trimmed = inputPath.trim()
        require(trimmed.isNotEmpty()) { "path 不能为空" }
        val androidFile = resolvePath(trimmed, workspace, allowRootDirectories)
        return shellPathForAndroid(androidFile)
            ?: throw IllegalArgumentException("无法映射 shell 路径：$inputPath")
    }

    private fun resolveUri(uriText: String): File {
        val uri = Uri.parse(uriText)
        require(uri.scheme == URI_SCHEME) { "Unsupported uri scheme: ${uri.scheme}" }
        val authority = uri.authority.orEmpty()
        val base = when (authority) {
            DIR_ATTACHMENTS -> attachmentsDir
            DIR_WORKSPACE -> rootDir
            DIR_SHARED -> sharedDir
            DIR_OFFLOADS -> offloadsDir
            DIR_BROWSER -> browserDir
            DIR_SKILLS -> skillsDir
            DIR_MEMORY -> memoryDir
            else -> throw IllegalArgumentException("未知 omnibot uri：$uriText")
        }
        var target = base
        uri.pathSegments.forEach { segment ->
            if (segment.isNotBlank()) {
                target = File(target, segment)
            }
        }
        return target
    }

    private fun isWithinWritableRoots(
        file: File,
        workspace: AgentWorkspaceDescriptor
    ): Boolean {
        val workspaceRoot = File(workspace.androidRootPath).canonicalFile
        return isWithin(workspaceRoot, file) ||
            isWithin(attachmentsDir.canonicalFile, file) ||
            isWithin(sharedDir.canonicalFile, file) ||
            isWithin(offloadsDir.canonicalFile, file) ||
            isWithin(browserDir.canonicalFile, file) ||
            isWithin(skillsDir.canonicalFile, file) ||
            isWithin(memoryDir.canonicalFile, file)
    }

    private fun isWithinRoot(file: File): Boolean {
        return isWithin(rootDir.canonicalFile, file)
    }

    private fun isWithin(parent: File, file: File): Boolean {
        val parentPath = parent.canonicalPath
        val targetPath = file.canonicalPath
        return targetPath == parentPath || targetPath.startsWith("$parentPath/")
    }

    private fun relativePathFrom(base: File, file: File): String {
        return file.canonicalPath.removePrefix(base.canonicalPath).trimStart('/')
    }

    private fun buildUriForBase(authority: String, base: File, file: File): String {
        val relative = relativePathFrom(base, file)
        val builder = Uri.Builder().scheme(URI_SCHEME).authority(authority)
        if (relative.isNotBlank()) {
            relative.split('/').filter { it.isNotBlank() }.forEach { segment ->
                builder.appendPath(segment)
            }
        }
        return builder.build().toString()
    }

    private fun buildRootUri(authority: String, vararg segments: String): String {
        val builder = Uri.Builder().scheme(URI_SCHEME).authority(authority)
        segments.filter { it.isNotBlank() }.forEach { builder.appendPath(it) }
        return builder.build().toString()
    }

    private fun conversationKey(conversationId: Long?): String {
        return if (conversationId == null) "conversation_default" else "conversation_$conversationId"
    }

    private fun sanitizeSegment(value: String): String {
        return value.trim().replace(Regex("[^A-Za-z0-9._-]"), "_")
    }

    private fun newManagedFile(
        parent: File,
        prefix: String,
        extension: String
    ): File {
        val normalizedPrefix = sanitizeSegment(prefix).ifBlank { "artifact" }
        val normalizedExt = extension.trim().removePrefix(".").ifBlank { "txt" }
        val fileName =
            "${normalizedPrefix}_${System.currentTimeMillis()}_${UUID.randomUUID().toString().take(8)}.$normalizedExt"
        return File(parent, fileName)
    }

    private fun stableIdForPath(path: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(path.toByteArray(Charset.forName("UTF-8")))
        return digest.joinToString("") { byte -> "%02x".format(byte) }.take(16)
    }

    private fun defaultActionsForFile(file: File): List<ArtifactAction> {
        val uri = uriForFile(file).orEmpty()
        val path = file.absolutePath
        val shellPath = shellPathForAndroid(file).orEmpty()
        return listOf(
            ArtifactAction(
                type = "preview",
                label = "预览",
                target = uri,
                payload = mapOf("path" to path, "shellPath" to shellPath)
            ),
            ArtifactAction(
                type = "save",
                label = "保存到本地",
                target = uri,
                payload = mapOf("path" to path, "shellPath" to shellPath)
            )
        )
    }

    fun guessMimeType(file: File): String {
        return when (file.extension.lowercase()) {
            "md" -> "text/markdown"
            "txt", "log", "json", "jsonl", "csv", "xml", "yaml", "yml", "kt", "java", "py", "js", "ts", "html", "htm", "css", "sh" -> {
                when (file.extension.lowercase()) {
                    "md" -> "text/markdown"
                    "json" -> "application/json"
                    "jsonl" -> "application/x-ndjson"
                    "csv" -> "text/csv"
                    "xml" -> "application/xml"
                    "yaml", "yml" -> "application/yaml"
                    "html", "htm" -> "text/html"
                    else -> "text/plain"
                }
            }
            "png" -> "image/png"
            "jpg", "jpeg" -> "image/jpeg"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "pdf" -> "application/pdf"
            "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            "docm" -> "application/vnd.ms-word.document.macroEnabled.12"
            "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            "xlsm" -> "application/vnd.ms-excel.sheet.macroEnabled.12"
            "pptx" -> "application/vnd.openxmlformats-officedocument.presentationml.presentation"
            "pptm" -> "application/vnd.ms-powerpoint.presentation.macroEnabled.12"
            "mp3" -> "audio/mpeg"
            "m4a" -> "audio/mp4"
            "wav" -> "audio/wav"
            "mp4" -> "video/mp4"
            "mov" -> "video/quicktime"
            else -> "application/octet-stream"
        }
    }

    fun previewKindForMime(mimeType: String): String {
        return when {
            mimeType.startsWith("image/") -> "image"
            mimeType.startsWith("text/") -> "text"
            mimeType == "application/json" ||
                mimeType == "application/xml" ||
                mimeType == "application/yaml" ||
                mimeType == "application/x-ndjson" -> "code"
            mimeType == "text/html" -> "html"
            mimeType == "application/pdf" -> "pdf"
            mimeType == "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ||
                mimeType == "application/vnd.ms-word.document.macroEnabled.12" -> "office_word"
            mimeType == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ||
                mimeType == "application/vnd.ms-excel.sheet.macroEnabled.12" -> "office_sheet"
            mimeType == "application/vnd.openxmlformats-officedocument.presentationml.presentation" ||
                mimeType == "application/vnd.ms-powerpoint.presentation.macroEnabled.12" -> "office_slide"
            mimeType.startsWith("audio/") -> "audio"
            mimeType.startsWith("video/") -> "video"
            else -> "file"
        }
    }

    fun uriForFile(file: File): String? {
        val canonical = file.canonicalFile
        if (!isWithinRoot(canonical)) return null
        return when {
            isWithin(attachmentsDir.canonicalFile, canonical) -> buildUriForBase(DIR_ATTACHMENTS, attachmentsDir, canonical)
            isWithin(sharedDir.canonicalFile, canonical) -> buildUriForBase(DIR_SHARED, sharedDir, canonical)
            isWithin(offloadsDir.canonicalFile, canonical) -> buildUriForBase(DIR_OFFLOADS, offloadsDir, canonical)
            isWithin(browserDir.canonicalFile, canonical) -> buildUriForBase(DIR_BROWSER, browserDir, canonical)
            isWithin(skillsDir.canonicalFile, canonical) -> buildUriForBase(DIR_SKILLS, skillsDir, canonical)
            isWithin(memoryDir.canonicalFile, canonical) -> buildUriForBase(DIR_MEMORY, memoryDir, canonical)
            isWithin(internalDir.canonicalFile, canonical) -> null
            else -> buildUriForBase(DIR_WORKSPACE, rootDir, canonical)
        }
    }
}
