package cn.com.omnimind.bot.openclaw

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import cn.com.omnimind.bot.termux.TermuxCommandRunner
import cn.com.omnimind.bot.termux.TermuxCommandSpec
import com.ai.assistance.operit.terminal.provider.filesystem.PRootMountMapping
import com.rk.libcommons.localBinDir
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.Socket
import java.net.URL
import java.nio.file.Files
import java.nio.charset.StandardCharsets

object OpenClawRuntimeSupport {
    const val TAG = "OpenClawRuntimeSupport"
    const val GATEWAY_PORT = 18789
    const val LOOPBACK_BASE_URL = "http://127.0.0.1:$GATEWAY_PORT"
    const val OPENCLAW_DIR_PATH = "/root/.openclaw"
    const val OPENCLAW_WORKSPACE_PATH = "/root/.openclaw/workspace"
    const val OPENCLAW_CONFIG_PATH = "/root/.openclaw/openclaw.json"
    const val OPENCLAW_LOG_PATH = "/root/openclaw.log"
    const val OPENCLAW_BYPASS_PATH = "/root/.openclaw/bionic-bypass.js"
    const val OPENCLAW_NODE_WRAPPER_PATH = "/root/.openclaw/node-wrapper.js"
    const val OPENCLAW_PROOT_COMPAT_PATH = "/root/.openclaw/proot-compat.js"
    const val OPENCLAW_CWD_FIX_PATH = "/root/.openclaw/cwd-fix.js"
    const val PROVIDER_API_KEY_ENV = "OMNIBOT_OPENCLAW_PROVIDER_API_KEY"
    const val GATEWAY_TOKEN_ENV_REF = "\${OPENCLAW_GATEWAY_TOKEN}"
    const val TARGET_NODE_VERSION = "22.13.1"
    const val TARGET_NODE_MAJOR = 22

    private const val GATEWAY_PREFS_NAME = "openclaw_gateway_prefs"
    private const val FALLBACK_SECURE_PREFS_NAME = "openclaw_gateway_secure_fallback"
    private const val ENCRYPTED_SECURE_PREFS_NAME = "openclaw_gateway_secure"
    private const val KEY_AUTO_START = "gateway_auto_start"
    private const val KEY_LAST_ERROR = "gateway_last_error"
    private const val KEY_PROVIDER_API_KEY = "provider_api_key"
    private const val KEY_LAST_TOKEN = "last_gateway_token"
    private const val LOG_MAX_FILE_SIZE_BYTES = 512 * 1024L
    private const val LOG_TRIM_TARGET_SIZE_BYTES = 256 * 1024L

    data class GatewayConfigSnapshot(
        val exists: Boolean,
        val authMode: String,
        val token: String?,
        val rawConfig: JSONObject?
    )

    fun gatewayPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(GATEWAY_PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun setGatewayAutoStartEnabled(context: Context, enabled: Boolean) {
        gatewayPrefs(context).edit().putBoolean(KEY_AUTO_START, enabled).apply()
    }

    fun isGatewayAutoStartEnabled(context: Context): Boolean {
        return gatewayPrefs(context).getBoolean(KEY_AUTO_START, false)
    }

    fun persistGatewayToken(context: Context, token: String?) {
        gatewayPrefs(context).edit().putString(KEY_LAST_TOKEN, token?.trim()).apply()
    }

    fun readPersistedGatewayToken(context: Context): String? {
        return gatewayPrefs(context).getString(KEY_LAST_TOKEN, null)?.trim()?.takeIf { it.isNotEmpty() }
    }

    fun setLastGatewayError(context: Context, message: String?) {
        gatewayPrefs(context).edit().putString(KEY_LAST_ERROR, message?.trim()).apply()
    }

    fun readLastGatewayError(context: Context): String? {
        return gatewayPrefs(context).getString(KEY_LAST_ERROR, null)?.trim()?.takeIf { it.isNotEmpty() }
    }

    fun clearLastGatewayError(context: Context) {
        gatewayPrefs(context).edit().remove(KEY_LAST_ERROR).apply()
    }

    fun saveProviderApiKey(context: Context, apiKey: String) {
        securePrefs(context).edit().putString(KEY_PROVIDER_API_KEY, apiKey.trim()).apply()
    }

    fun readProviderApiKey(context: Context): String? {
        return securePrefs(context).getString(KEY_PROVIDER_API_KEY, null)?.trim()?.takeIf { it.isNotEmpty() }
    }

    fun embeddedRootfsDir(context: Context): File {
        return File(context.filesDir.parentFile, "local/alpine")
    }

    @Deprecated("Use embeddedRootfsDir() instead.")
    fun ubuntuRootfsDir(context: Context): File {
        return embeddedRootfsDir(context)
    }

    fun mapLinuxPathToHostFile(context: Context, linuxPath: String): File {
        val rootfsRoot = embeddedRootfsDir(context)
        val hostPath = PRootMountMapping.mapLinuxPathToHostPath(
            linuxPath = linuxPath,
            rootfsRoot = rootfsRoot,
            homeDir = context.filesDir.absolutePath,
            workspaceDir = File(context.applicationInfo.dataDir, "workspace").absolutePath,
            appDataDir = context.applicationInfo.dataDir,
            packageName = context.packageName,
            chrootEnabled = false
        )
        return File(hostPath)
    }

    fun openClawConfigHostFile(context: Context): File = mapLinuxPathToHostFile(context, OPENCLAW_CONFIG_PATH)

    fun openClawLogHostFile(context: Context): File = mapLinuxPathToHostFile(context, OPENCLAW_LOG_PATH)

    fun openClawWorkspaceHostDir(context: Context): File = mapLinuxPathToHostFile(context, OPENCLAW_WORKSPACE_PATH)

    fun openClawCompatHostDir(context: Context): File = mapLinuxPathToHostFile(context, OPENCLAW_DIR_PATH)

    fun openClawPackageJsonHostFile(context: Context): File {
        return File(embeddedRootfsDir(context), "usr/local/lib/node_modules/openclaw/package.json")
    }

    fun npmCliHostFile(context: Context): File {
        return File(embeddedRootfsDir(context), "usr/local/lib/node_modules/npm/bin/npm-cli.js")
    }

    fun nodeModulesHostPath(context: Context): File {
        return File(embeddedRootfsDir(context), "usr/local/lib/node_modules")
    }

    fun nodeLayoutNeedsRepair(context: Context): Boolean {
        val nodeModulesPath = nodeModulesHostPath(context)
        val npmCliPath = npmCliHostFile(context)
        val isNodeModulesSymlink = runCatching {
            Files.isSymbolicLink(nodeModulesPath.toPath())
        }.getOrDefault(false)
        return isNodeModulesSymlink || !npmCliPath.exists()
    }

    fun openClawWrapperHostFile(context: Context): File {
        return File(embeddedRootfsDir(context), "usr/local/bin/openclaw")
    }

    fun nodeTarballGuestPath(): String {
        return "/tmp/node-v$TARGET_NODE_VERSION-linux-arm64.tar.xz"
    }

    fun nodeTarballHostFile(context: Context): File {
        return mapLinuxPathToHostFile(context, nodeTarballGuestPath())
    }

    fun nodeTarballUrl(): String {
        return "https://nodejs.org/dist/v$TARGET_NODE_VERSION/node-v$TARGET_NODE_VERSION-linux-arm64.tar.xz"
    }

    fun dashboardUrlForToken(token: String?): String? {
        val normalized = token?.trim().orEmpty()
        if (normalized.isEmpty() || isGatewayTokenPlaceholder(normalized)) {
            return null
        }
        return "$LOOPBACK_BASE_URL/#token=$normalized"
    }

    fun ensureRuntimeFiles(context: Context) {
        val rootfsDir = embeddedRootfsDir(context)
        if (!rootfsDir.exists()) {
            return
        }

        ensureInstallScaffolding(context)
        openClawCompatHostDir(context).mkdirs()
        openClawWorkspaceHostDir(context).mkdirs()
        openClawConfigHostFile(context).parentFile?.mkdirs()
        openClawLogHostFile(context).parentFile?.mkdirs()
        ensureResolvConf(context)
        writeCompatScripts(context)
        ensureGitConfig(context)
        ensureBashrcExport(context)
        ensureGatewayLogFile(context)
        ensureEmbeddedShellScripts(context)
    }

    fun ensureResolvConf(context: Context) {
        val rootfsResolv = File(embeddedRootfsDir(context), "etc/resolv.conf")
        if (rootfsResolv.exists() && rootfsResolv.length() > 0L) {
            return
        }
        rootfsResolv.parentFile?.mkdirs()
        rootfsResolv.writeText(defaultDnsContent(), StandardCharsets.UTF_8)
    }

    fun defaultDnsForShell(): String = defaultDnsContent().trimEnd()

    fun writeNormalizedConfigFallback(
        context: Context,
        originalConfigJson: String,
        gatewayToken: String
    ): String {
        ensureRuntimeFiles(context)
        val normalized = normalizeConfigJson(originalConfigJson, gatewayToken)
        openClawConfigHostFile(context).writeText(normalized, StandardCharsets.UTF_8)
        persistGatewayToken(context, gatewayToken)
        return normalized
    }

    fun normalizeConfigJson(configJson: String, gatewayToken: String): String {
        val root = JSONObject(configJson)
        val gateway = root.optJSONObject("gateway") ?: JSONObject().also { root.put("gateway", it) }
        val auth = gateway.optJSONObject("auth") ?: JSONObject().also { gateway.put("auth", it) }
        auth.put("mode", "token")
        auth.put("token", gatewayToken)
        return root.toString(2)
    }

    fun inspectGatewayConfig(context: Context): GatewayConfigSnapshot {
        val configFile = openClawConfigHostFile(context)
        if (!configFile.exists()) {
            return GatewayConfigSnapshot(
                exists = false,
                authMode = "",
                token = null,
                rawConfig = null
            )
        }
        return try {
            val rawConfig = JSONObject(configFile.readText(StandardCharsets.UTF_8))
            val gateway = rawConfig.optJSONObject("gateway")
            val auth = gateway?.optJSONObject("auth")
            GatewayConfigSnapshot(
                exists = true,
                authMode = auth?.optString("mode")?.trim().orEmpty(),
                token = auth?.optString("token")?.trim()?.takeIf { it.isNotEmpty() },
                rawConfig = rawConfig
            )
        } catch (error: Exception) {
            Log.w(TAG, "Failed to parse OpenClaw config", error)
            GatewayConfigSnapshot(
                exists = true,
                authMode = "",
                token = null,
                rawConfig = null
            )
        }
    }

    fun readGatewayToken(context: Context): String? {
        val token = inspectGatewayConfig(context).token?.trim()
        if (token.isNullOrEmpty()) {
            return readPersistedGatewayToken(context)
        }
        return token
    }

    fun isGatewayConfigured(context: Context): Boolean {
        val snapshot = inspectGatewayConfig(context)
        return snapshot.exists && snapshot.authMode == "token"
    }

    fun isGatewayTokenPlaceholder(token: String?): Boolean {
        val normalized = token?.trim().orEmpty()
        return normalized.isEmpty() || normalized == GATEWAY_TOKEN_ENV_REF
    }

    fun legacyConfigNeedsRedeploy(context: Context): Boolean {
        val snapshot = inspectGatewayConfig(context)
        if (!snapshot.exists || snapshot.authMode != "token") {
            return false
        }
        if (isGatewayTokenPlaceholder(snapshot.token)) {
            return true
        }
        return readProviderApiKey(context).isNullOrBlank()
    }

    fun legacyRedeployMessage(context: Context): String? {
        if (!legacyConfigNeedsRedeploy(context)) {
            return null
        }
        return "检测到旧版 OpenClaw 配置，需重新保存或重新部署一次，才能启用自动守护。"
    }

    fun isOpenClawInstalled(context: Context): Boolean {
        return openClawPackageJsonHostFile(context).exists()
    }

    fun ensureOpenClawWrapper(context: Context): Boolean {
        val wrapperFile = openClawWrapperHostFile(context)
        if (wrapperFile.exists() && wrapperFile.canExecute()) {
            return true
        }
        val packageJsonFile = openClawPackageJsonHostFile(context)
        if (!packageJsonFile.exists()) {
            return false
        }
        return runCatching {
            val packageJson = JSONObject(packageJsonFile.readText(StandardCharsets.UTF_8))
            val binField = packageJson.opt("bin")
            val entries = linkedMapOf<String, String>()
            when (binField) {
                is JSONObject -> {
                    val keys = binField.keys()
                    while (keys.hasNext()) {
                        val key = keys.next()
                        val relativePath = binField.optString(key).trim()
                        if (relativePath.isNotEmpty()) {
                            entries[key] = relativePath
                        }
                    }
                }

                is String -> {
                    val value = binField.trim()
                    if (value.isNotEmpty()) {
                        entries["openclaw"] = value
                    }
                }
            }

            if (entries.isEmpty()) {
                val fallbackCandidates = listOf("bin/openclaw.js", "bin/openclaw", "cli.js", "index.js")
                fallbackCandidates.firstOrNull { File(packageJsonFile.parentFile, it).exists() }?.let {
                    entries["openclaw"] = it
                }
            }

            val relativePath = entries["openclaw"] ?: return false
            wrapperFile.parentFile?.mkdirs()
            wrapperFile.writeText(
                "#!/bin/sh\nexec node \"/usr/local/lib/node_modules/openclaw/$relativePath\" \"\$@\"\n",
                StandardCharsets.UTF_8
            )
            wrapperFile.setReadable(true, false)
            wrapperFile.setExecutable(true, false)
            true
        }.getOrDefault(false)
    }

    fun resolveHostBashPath(context: Context): String {
        val binDir = File(context.filesDir, "usr/bin")
        val copiedBash = File(binDir, "bash")
        if (copiedBash.exists() && copiedBash.canExecute()) {
            return copiedBash.absolutePath
        }

        val nativeBash = File(context.applicationInfo.nativeLibraryDir, "libbash.so")
        if (nativeBash.exists()) {
            nativeBash.setExecutable(true, false)
            return nativeBash.absolutePath
        }

        return copiedBash.absolutePath
    }

    fun buildHostEnvironment(context: Context): MutableMap<String, String> {
        val filesDir = context.filesDir
        val usrDir = File(filesDir, "usr")
        val binDir = File(usrDir, "bin")
        val nativeLibDir = context.applicationInfo.nativeLibraryDir
        return mutableMapOf(
            "PATH" to "${binDir.absolutePath}:$nativeLibDir:${System.getenv("PATH")}",
            "HOME" to filesDir.absolutePath,
            "PREFIX" to usrDir.absolutePath,
            "TERMUX_PREFIX" to usrDir.absolutePath,
            "LD_LIBRARY_PATH" to "$nativeLibDir:${binDir.absolutePath}",
            "PROOT_LOADER" to File(binDir, "loader").absolutePath,
            "TMPDIR" to File(filesDir, "tmp").absolutePath,
            "PROOT_TMP_DIR" to File(filesDir, "tmp").absolutePath,
            "TERM" to "xterm-256color",
            "LANG" to "en_US.UTF-8",
            "SHELL" to resolveHostBashPath(context)
        )
    }

    fun buildGatewayProcessBuilder(context: Context, providerApiKey: String): ProcessBuilder {
        val initHost = ensureEmbeddedShellScripts(context)
        val gatewayCommand = listOf(
            "export NODE_OPTIONS=\"--require /root/.openclaw/bionic-bypass.js\"",
            "export $PROVIDER_API_KEY_ENV=${quoteShell(providerApiKey)}",
            "mkdir -p /root/.openclaw /root/.openclaw/workspace",
            "touch /root/openclaw.log",
            "exec openclaw gateway run --port $GATEWAY_PORT"
        ).joinToString("\n")
        val builder = ProcessBuilder(
            "/system/bin/sh",
            initHost.absolutePath,
            "/bin/sh",
            "-lc",
            gatewayCommand
        )
        builder.directory(context.filesDir)
        builder.redirectErrorStream(false)
        val environment = builder.environment()
        environment.clear()
        environment.putAll(buildHostEnvironment(context))
        return builder
    }

    fun gatewayCleanupCommand(): String {
        return """
            set -euo pipefail
            if command -v pkill >/dev/null 2>&1; then
              pkill -f "openclaw gateway" || true
            fi
            if command -v fuser >/dev/null 2>&1; then
              fuser -k $GATEWAY_PORT/tcp >/dev/null 2>&1 || true
            fi
        """.trimIndent()
    }

    suspend fun executeGatewayCleanup(context: Context) {
        runCatching {
            TermuxCommandRunner.execute(
                context = context,
                spec = TermuxCommandSpec(
                    command = gatewayCleanupCommand(),
                    executionMode = TermuxCommandSpec.EXECUTION_MODE_PROOT,
                    workingDirectory = "/root",
                    timeoutSeconds = 30
                )
            )
        }
    }

    fun downloadNodeTarball(context: Context, onProgress: (Long, Long) -> Unit = { _, _ -> }): File {
        val targetFile = nodeTarballHostFile(context)
        targetFile.parentFile?.mkdirs()
        if (targetFile.exists() && targetFile.length() > 0L) {
            return targetFile
        }
        val tempFile = File(targetFile.parentFile, "${targetFile.name}.part")
        if (tempFile.exists()) {
            tempFile.delete()
        }
        val url = URL(nodeTarballUrl())
        val connection = (url.openConnection() as HttpURLConnection).apply {
            connectTimeout = 15000
            readTimeout = 30000
            requestMethod = "GET"
        }
        connection.connect()
        if (connection.responseCode !in 200..299) {
            connection.inputStream.closeQuietly()
            throw IllegalStateException("下载 Node.js 失败，HTTP ${connection.responseCode}")
        }
        val totalBytes = connection.contentLengthLong.coerceAtLeast(-1L)
        connection.inputStream.use { input ->
            tempFile.outputStream().use { output ->
                copyWithProgress(input, output, totalBytes, onProgress)
            }
        }
        if (targetFile.exists()) {
            targetFile.delete()
        }
        val renamed = tempFile.renameTo(targetFile)
        if (!renamed) {
            tempFile.copyTo(targetFile, overwrite = true)
            tempFile.delete()
        }
        if (!targetFile.exists() || targetFile.length() <= 0L) {
            throw IllegalStateException("Node.js tarball 下载完成但文件不可用：${targetFile.absolutePath}")
        }
        return targetFile
    }

    fun isGatewayHealthy(connectTimeoutMs: Int = 1500, readTimeoutMs: Int = 1500): Boolean {
        return try {
            val connection = URL(LOOPBACK_BASE_URL).openConnection() as HttpURLConnection
            connection.connectTimeout = connectTimeoutMs
            connection.readTimeout = readTimeoutMs
            connection.requestMethod = "HEAD"
            connection.instanceFollowRedirects = false
            connection.connect()
            val status = connection.responseCode
            connection.disconnect()
            status in 200..499
        } catch (_: Exception) {
            try {
                Socket("127.0.0.1", GATEWAY_PORT).use { socket ->
                    socket.soTimeout = readTimeoutMs
                    true
                }
            } catch (_: Exception) {
                false
            }
        }
    }

    fun ensureGatewayLogFile(context: Context) {
        val logFile = openClawLogHostFile(context)
        logFile.parentFile?.mkdirs()
        if (!logFile.exists()) {
            logFile.createNewFile()
        }
    }

    fun appendGatewayLogLine(context: Context, line: String) {
        ensureGatewayLogFile(context)
        val logFile = openClawLogHostFile(context)
        if (logFile.exists() && logFile.length() > LOG_MAX_FILE_SIZE_BYTES) {
            val text = runCatching { logFile.readText(StandardCharsets.UTF_8) }.getOrDefault("")
            val tail = if (text.length > LOG_TRIM_TARGET_SIZE_BYTES) {
                text.takeLast(LOG_TRIM_TARGET_SIZE_BYTES.toInt())
            } else {
                text
            }
            logFile.writeText(tail, StandardCharsets.UTF_8)
        }
        logFile.appendText("${line.trimEnd()}\n", StandardCharsets.UTF_8)
    }

    private fun securePrefs(context: Context): SharedPreferences {
        return runCatching {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            EncryptedSharedPreferences.create(
                context,
                ENCRYPTED_SECURE_PREFS_NAME,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
        }.getOrElse {
            Log.w(TAG, "Falling back to plain SharedPreferences for provider API key", it)
            context.getSharedPreferences(FALLBACK_SECURE_PREFS_NAME, Context.MODE_PRIVATE)
        }
    }

    private fun ensureInstallScaffolding(context: Context) {
        val rootfsDir = embeddedRootfsDir(context)
        val paths = listOf(
            "/etc/ssl/certs",
            "/var/cache/apk",
            "/tmp",
            "/tmp/npm-cache/_cacache/tmp",
            "/tmp/npm-cache/_cacache/content-v2",
            "/tmp/npm-cache/_cacache/index-v5",
            "/tmp/npm-cache/_logs",
            "/usr/local/lib/node_modules",
            "/usr/local/bin",
            "/root/.npm",
            "/root/.config",
            "/root/.config/openclaw",
            "/root/.cache",
            "/root/.cache/openclaw",
            "/root/.cache/node",
            "/root/.local/share",
            "/root/.openclaw",
            "/root/.openclaw/workspace",
            "/root/.openclaw/data",
            "/root/.openclaw/memory",
            "/root/.openclaw/skills",
            "/root/.openclaw/config",
            "/root/.openclaw/extensions",
            "/root/.openclaw/logs",
            "/var/tmp",
            "/run",
            "/run/lock",
            "/dev/shm"
        )
        paths.forEach { linuxPath ->
            runCatching { mapLinuxPathToHostFile(context, linuxPath).mkdirs() }
        }

        val machineId = mapLinuxPathToHostFile(context, "/etc/machine-id")
        if (!machineId.exists()) {
            machineId.parentFile?.mkdirs()
            machineId.writeText("10000000000000000000000000000000\n", StandardCharsets.UTF_8)
        }

        val fakeProcDir = File(rootfsDir, "proc")
        fakeProcDir.mkdirs()
        val fakeSysEmptyDir = File(rootfsDir, "sys/.empty")
        fakeSysEmptyDir.mkdirs()
        val fipsEnabledFile = File(fakeProcDir, ".sysctl_crypto_fips_enabled")
        if (!fipsEnabledFile.exists()) {
            fipsEnabledFile.writeText("0\n", StandardCharsets.UTF_8)
        }
    }

    private fun ensureEmbeddedShellScripts(context: Context): File {
        val initHost = localBinDir().resolve("init-host")
        initHost.parentFile?.mkdirs()
        context.assets.open("init-host.sh").use { input ->
            initHost.outputStream().use { output -> input.copyTo(output) }
        }
        initHost.setExecutable(true, false)

        val init = localBinDir().resolve("init")
        context.assets.open("init.sh").use { input ->
            init.outputStream().use { output -> input.copyTo(output) }
        }
        init.setExecutable(true, false)

        return initHost
    }

    private fun writeCompatScripts(context: Context) {
        val compatDir = openClawCompatHostDir(context)
        compatDir.mkdirs()
        writeTextIfDifferent(File(compatDir, "cwd-fix.js"), cwdFixScript)
        writeTextIfDifferent(File(compatDir, "node-wrapper.js"), nodeWrapperScript)
        writeTextIfDifferent(File(compatDir, "proot-compat.js"), prootCompatScript)
        writeTextIfDifferent(File(compatDir, "bionic-bypass.js"), bypassScript)
    }

    private fun ensureGitConfig(context: Context) {
        val gitConfigFile = mapLinuxPathToHostFile(context, "/root/.gitconfig")
        writeTextIfDifferent(
            gitConfigFile,
            """
            [url "https://github.com/"]
            	insteadOf = ssh://git@github.com/
            	insteadOf = git@github.com:
            [advice]
            	detachedHead = false
            """.trimIndent() + "\n"
        )
    }

    private fun ensureBashrcExport(context: Context) {
        val bashrcFile = mapLinuxPathToHostFile(context, "/root/.bashrc")
        val exportLine = "export NODE_OPTIONS=\"--require /root/.openclaw/bionic-bypass.js\""
        val existing = if (bashrcFile.exists()) bashrcFile.readText(StandardCharsets.UTF_8) else ""
        if (existing.contains(exportLine)) {
            return
        }
        bashrcFile.parentFile?.mkdirs()
        val updated = buildString {
            append(existing)
            if (existing.isNotEmpty() && !existing.endsWith("\n")) {
                append('\n')
            }
            append("# OpenClaw Android compatibility\n")
            append(exportLine)
            append('\n')
        }
        bashrcFile.writeText(updated, StandardCharsets.UTF_8)
    }

    private fun writeTextIfDifferent(target: File, content: String) {
        target.parentFile?.mkdirs()
        if (target.exists() && target.readText(StandardCharsets.UTF_8) == content) {
            return
        }
        target.writeText(content, StandardCharsets.UTF_8)
    }

    private fun quoteShell(value: String): String {
        return "'" + value.replace("'", "'\"'\"'") + "'"
    }

    private fun defaultDnsContent(): String {
        return """
            nameserver 8.8.8.8
            nameserver 1.1.1.1
            nameserver 223.5.5.5
            nameserver 223.6.6.6
            nameserver 119.29.29.29
        """.trimIndent() + "\n"
    }

    private fun copyWithProgress(
        input: InputStream,
        output: java.io.OutputStream,
        totalBytes: Long,
        onProgress: (Long, Long) -> Unit
    ) {
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var copied = 0L
        while (true) {
            val count = input.read(buffer)
            if (count < 0) {
                break
            }
            output.write(buffer, 0, count)
            copied += count
            onProgress(copied, totalBytes)
        }
    }

    private fun InputStream.closeQuietly() {
        runCatching { close() }
    }

    private val cwdFixScript = """
        // OpenClaw CWD Fix - Auto-generated
        // proot on Android 10+ returns ENOSYS for getcwd() syscall.
        // Patch process.cwd to return /root on failure.
        const _origCwd = process.cwd;
        process.cwd = function() {
          try { return _origCwd.call(process); }
          catch(e) { return process.env.HOME || '/root'; }
        };
    """.trimIndent()

    private val nodeWrapperScript = """
        // OpenClaw Node Wrapper - Auto-generated
        // Patches broken proot syscalls, then loads the target script.
        // Used for bootstrap-time npm operations.

        // --- Load shared proot compatibility patches ---
        require('/root/.openclaw/proot-compat.js');

        // Load target script
        const script = process.argv[2];
        if (script) {
          process.argv = [process.argv[0], script, ...process.argv.slice(3)];
          require(script);
        } else {
          console.log('Usage: node node-wrapper.js <script> [args...]');
          process.exit(1);
        }
    """.trimIndent()

    private val prootCompatScript = """
        // OpenClaw Proot Compatibility Layer - Auto-generated
        // Patches all known broken syscalls in proot on Android 10+.
        // This file is require()'d by both node-wrapper.js and bionic-bypass.js.

        'use strict';

        // ====================================================================
        // 1. process.cwd() — getcwd() returns ENOSYS in proot
        // ====================================================================
        const _origCwd = process.cwd;
        process.cwd = function() {
          try { return _origCwd.call(process); }
          catch(e) { return process.env.HOME || '/root'; }
        };

        // ====================================================================
        // 2. os module patches — various /proc reads fail in proot
        // ====================================================================
        const _os = require('os');

        // os.hostname() — may fail reading /proc/sys/kernel/hostname
        const _origHostname = _os.hostname;
        _os.hostname = function() {
          try { return _origHostname.call(_os); }
          catch(e) { return 'localhost'; }
        };

        // os.tmpdir() — ensure it returns /tmp
        const _origTmpdir = _os.tmpdir;
        _os.tmpdir = function() {
          try {
            const t = _origTmpdir.call(_os);
            return t || '/tmp';
          } catch(e) { return '/tmp'; }
        };

        // os.homedir() — may fail with ENOSYS
        const _origHomedir = _os.homedir;
        _os.homedir = function() {
          try { return _origHomedir.call(_os); }
          catch(e) { return process.env.HOME || '/root'; }
        };

        // os.userInfo() — getpwuid may fail in proot
        const _origUserInfo = _os.userInfo;
        _os.userInfo = function(opts) {
          try { return _origUserInfo.call(_os, opts); }
          catch(e) {
            return {
              uid: 0, gid: 0,
              username: 'root',
              homedir: process.env.HOME || '/root',
              shell: '/bin/bash'
            };
          }
        };

        // os.cpus() — reading /proc/cpuinfo may fail
        const _origCpus = _os.cpus;
        _os.cpus = function() {
          try {
            const cpus = _origCpus.call(_os);
            if (cpus && cpus.length > 0) return cpus;
          } catch(e) {}
          return [{ model: 'ARM', speed: 2000, times: { user: 0, nice: 0, sys: 0, idle: 0, irq: 0 } }];
        };

        // os.totalmem() / os.freemem() — reading /proc/meminfo may fail
        const _origTotalmem = _os.totalmem;
        _os.totalmem = function() {
          try { return _origTotalmem.call(_os); }
          catch(e) { return 4 * 1024 * 1024 * 1024; }
        };
        const _origFreemem = _os.freemem;
        _os.freemem = function() {
          try { return _origFreemem.call(_os); }
          catch(e) { return 2 * 1024 * 1024 * 1024; }
        };

        // os.networkInterfaces() — Android blocks getifaddrs()
        const _origNetIf = _os.networkInterfaces;
        _os.networkInterfaces = function() {
          try {
            const ifaces = _origNetIf.call(_os);
            if (ifaces && Object.keys(ifaces).length > 0) return ifaces;
          } catch(e) {}
          return {
            lo: [{
              address: '127.0.0.1', netmask: '255.0.0.0', family: 'IPv4',
              mac: '00:00:00:00:00:00', internal: true, cidr: '127.0.0.1/8'
            }]
          };
        };

        // ====================================================================
        // 3. fs.mkdir — mkdirat() returns ENOSYS in proot
        // ====================================================================
        const _fs = require('fs');
        const _path = require('path');
        const _origMkdirSync = _fs.mkdirSync;
        _fs.mkdirSync = function(p, options) {
          try {
            return _origMkdirSync.call(_fs, p, options);
          } catch(e) {
            if (e.code === 'ENOSYS' || (e.code === 'ENOENT' && options && options.recursive)) {
              const parts = _path.resolve(String(p)).split(_path.sep).filter(Boolean);
              let current = '';
              for (const part of parts) {
                current += _path.sep + part;
                try { _origMkdirSync.call(_fs, current); }
                catch(e2) { if (e2.code !== 'EEXIST' && e2.code !== 'EISDIR') { } }
              }
              return undefined;
            }
            throw e;
          }
        };
        const _origMkdir = _fs.mkdir;
        _fs.mkdir = function(p, options, cb) {
          if (typeof options === 'function') { cb = options; options = undefined; }
          try { _fs.mkdirSync(p, options); if (cb) cb(null); }
          catch(e) { if (cb) cb(e); else throw e; }
        };
        const _fsp = _fs.promises;
        if (_fsp) {
          const _origMkdirP = _fsp.mkdir;
          _fsp.mkdir = async function(p, options) {
            try { return await _origMkdirP.call(_fsp, p, options); }
            catch(e) {
              if (e.code === 'ENOSYS' || (e.code === 'ENOENT' && options && options.recursive)) {
                _fs.mkdirSync(p, options); return undefined;
              }
              throw e;
            }
          };
        }

        // ====================================================================
        // 4. fs.rename — renameat2() may ENOSYS in proot; fallback to copy+unlink
        // ====================================================================
        const _origRenameSync = _fs.renameSync;
        _fs.renameSync = function(oldPath, newPath) {
          try { return _origRenameSync.call(_fs, oldPath, newPath); }
          catch(e) {
            if (e.code === 'ENOSYS' || e.code === 'EXDEV') {
              _fs.copyFileSync(oldPath, newPath);
              try { _fs.unlinkSync(oldPath); } catch(_) {}
              return;
            }
            throw e;
          }
        };
        const _origRename = _fs.rename;
        _fs.rename = function(oldPath, newPath, cb) {
          _origRename.call(_fs, oldPath, newPath, function(err) {
            if (err && (err.code === 'ENOSYS' || err.code === 'EXDEV')) {
              try {
                _fs.copyFileSync(oldPath, newPath);
                try { _fs.unlinkSync(oldPath); } catch(_) {}
                if (cb) cb(null);
              } catch(e2) { if (cb) cb(e2); }
            } else { if (cb) cb(err); }
          });
        };
        if (_fsp) {
          const _origRenameP = _fsp.rename;
          _fsp.rename = async function(oldPath, newPath) {
            try { return await _origRenameP.call(_fsp, oldPath, newPath); }
            catch(e) {
              if (e.code === 'ENOSYS' || e.code === 'EXDEV') {
                await _fsp.copyFile(oldPath, newPath);
                try { await _fsp.unlink(oldPath); } catch(_) {}
                return;
              }
              throw e;
            }
          };
        }

        // ====================================================================
        // 5. fs.chmod/chown — fchmodat/fchownat may fail; tolerate ENOSYS
        // ====================================================================
        for (const fn of ['chmod', 'chown', 'lchown']) {
          const origSync = _fs[fn + 'Sync'];
          if (origSync) {
            _fs[fn + 'Sync'] = function() {
              try { return origSync.apply(_fs, arguments); }
              catch(e) { if (e.code === 'ENOSYS') return; throw e; }
            };
          }
          const origAsync = _fs[fn];
          if (origAsync) {
            _fs[fn] = function() {
              const args = Array.from(arguments);
              const cb = typeof args[args.length - 1] === 'function' ? args.pop() : null;
              try { origSync.apply(_fs, args); if (cb) cb(null); }
              catch(e) { if (e.code === 'ENOSYS') { if (cb) cb(null); } else { if (cb) cb(e); else throw e; } }
            };
          }
        }

        // ====================================================================
        // 6. fs.watch — inotify may fail; provide silent no-op fallback
        // ====================================================================
        const _origWatch = _fs.watch;
        _fs.watch = function(filename, options, listener) {
          try { return _origWatch.call(_fs, filename, options, listener); }
          catch(e) {
            if (e.code === 'ENOSYS' || e.code === 'ENOSPC' || e.code === 'ENOENT') {
              const EventEmitter = require('events');
              const fake = new EventEmitter();
              fake.close = function() {};
              fake.ref = function() { return this; };
              fake.unref = function() { return this; };
              return fake;
            }
            throw e;
          }
        };

        // ====================================================================
        // 7. child_process.spawn — handle ENOSYS (proot) and ENOENT (missing binary).
        // ====================================================================
        const _cp = require('child_process');
        const _EventEmitter = require('events');

        function _isSideEffectCmd(cmd) {
          const base = String(cmd).split('/').pop();
          return base === 'git' || base === 'cmake';
        }

        function _shouldMock(errCode, cmd) {
          if (errCode === 'ENOSYS') return true;
          if (errCode === 'ENOENT' && _isSideEffectCmd(cmd)) return true;
          return false;
        }

        function _makeFakeChild(exitCode) {
          const fake = new _EventEmitter();
          fake.stdout = new (require('stream').Readable)({ read() { this.push(null); } });
          fake.stderr = new (require('stream').Readable)({ read() { this.push(null); } });
          fake.stdin = new (require('stream').Writable)({ write(c,e,cb) { cb(); } });
          fake.pid = 0;
          fake.exitCode = null;
          fake.kill = function() { return false; };
          fake.ref = function() { return this; };
          fake.unref = function() { return this; };
          fake.connected = false;
          fake.disconnect = function() {};
          process.nextTick(() => {
            fake.exitCode = exitCode;
            fake.emit('close', exitCode, null);
          });
          return fake;
        }

        function _makeFakeSyncResult(code) {
          return { status: code, signal: null, stdout: Buffer.alloc(0),
                   stderr: Buffer.alloc(0),
                   pid: 0, output: [null, Buffer.alloc(0), Buffer.alloc(0)],
                   error: null };
        }

        const _origSpawn = _cp.spawn;
        _cp.spawn = function(cmd, args, options) {
          try {
            const child = _origSpawn.call(_cp, cmd, args, options);
            child.on('error', (err) => {
              if (_shouldMock(err.code, cmd)) {
                const code = _isSideEffectCmd(cmd) ? 128 : 0;
                child.emit('close', code, null);
              }
            });
            return child;
          } catch(e) {
            if (_shouldMock(e.code, cmd)) {
              return _makeFakeChild(_isSideEffectCmd(cmd) ? 128 : 0);
            }
            throw e;
          }
        };
        const _origSpawnSync = _cp.spawnSync;
        _cp.spawnSync = function(cmd, args, options) {
          try {
            const r = _origSpawnSync.call(_cp, cmd, args, options);
            if (r.error && _shouldMock(r.error.code, cmd)) {
              return _makeFakeSyncResult(_isSideEffectCmd(cmd) ? 128 : 0);
            }
            return r;
          } catch(e) {
            if (_shouldMock(e.code, cmd)) {
              return _makeFakeSyncResult(_isSideEffectCmd(cmd) ? 128 : 0);
            }
            throw e;
          }
        };
        const _origExecFile = _cp.execFile;
        _cp.execFile = function(file, args, options, cb) {
          if (typeof args === 'function') { cb = args; args = []; options = {}; }
          if (typeof options === 'function') { cb = options; options = {}; }
          try { return _origExecFile.call(_cp, file, args, options, cb); }
          catch(e) {
            if (_shouldMock(e.code, file)) {
              const code = _isSideEffectCmd(file) ? 128 : 0;
              if (cb) cb(code ? Object.assign(new Error('spawn failed'), {code:e.code}) : null, '', '');
              return;
            }
            throw e;
          }
        };
        const _origExecFileSync = _cp.execFileSync;
        _cp.execFileSync = function(file, args, options) {
          try { return _origExecFileSync.call(_cp, file, args, options); }
          catch(e) {
            if (_shouldMock(e.code, file)) {
              if (_isSideEffectCmd(file)) throw e;
              return Buffer.alloc(0);
            }
            throw e;
          }
        };
    """.trimIndent()

    private val bypassScript = """
        // OpenClaw Bionic Bypass - Auto-generated
        // Comprehensive runtime compatibility layer for proot on Android 10+.
        // Loaded via NODE_OPTIONS before any application code runs.

        // Load all proot compatibility patches (shared with node-wrapper.js)
        require('/root/.openclaw/proot-compat.js');
    """.trimIndent()
}
