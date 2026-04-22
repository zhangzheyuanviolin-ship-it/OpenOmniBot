package cn.com.omnimind.bot.utg

import android.content.Context
import cn.com.omnimind.baselib.util.OmniLog
import cn.com.omnimind.bot.terminal.EmbeddedTerminalRuntime
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * 管理 OmniFlow Python 包的安装和更新。
 *
 * 支持两种模式：
 * 1. 外部目录模式（开发）：从 /data/local/tmp/omnibot/packages/ 读取 adb push 的 wheel
 * 2. GitHub 下载模式（发布）：从 GitHub Releases 下载最新 wheel
 */
object OmniFlowPackageManager {
    private const val TAG = "OmniFlowPackageManager"

    // 外部目录（adb push 目标）
    private const val EXTERNAL_PACKAGE_DIR = "/data/local/tmp/omnibot/packages"
    private const val WHEEL_HASH_FILE = ".wheel_hash"

    // GitHub Release 下载（公开仓库，代码私有）
    private const val GITHUB_RELEASE_URL =
        "https://github.com/omnimind-ai/omniflow-release/releases/latest/download/omniflow-latest-py3-none-any.whl"

    // SharedPreferences
    private const val PREFS_NAME = "omniflow_package"
    private const val KEY_INSTALLED_HASH = "installed_hash"
    private const val KEY_INSTALL_SOURCE = "install_source"

    data class InstallResult(
        val success: Boolean,
        val alreadyInstalled: Boolean,
        val message: String,
        val source: String?,
        val hash: String?
    )

    enum class InstallSource {
        EXTERNAL,   // adb push 到外部目录
        GITHUB,     // GitHub 下载
        NONE        // 未安装
    }

    /**
     * 检查是否有可用的 wheel（外部目录或已安装）。
     */
    fun isAvailable(context: Context): Boolean {
        return findExternalWheel() != null || isInstalled(context)
    }

    /**
     * 检查 OmniFlow 是否已安装。
     */
    fun isInstalled(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_INSTALLED_HASH, null) != null
    }

    /**
     * 获取当前安装来源。
     */
    fun getInstallSource(context: Context): InstallSource {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return when (prefs.getString(KEY_INSTALL_SOURCE, null)) {
            "external" -> InstallSource.EXTERNAL
            "github" -> InstallSource.GITHUB
            else -> InstallSource.NONE
        }
    }

    /**
     * 安装或更新 OmniFlow 包。
     *
     * 优先级：
     * 1. 外部目录（adb push）- 如果存在且比已安装版本新
     * 2. GitHub 下载 - 如果外部目录不存在
     *
     * @param force 强制重新安装
     * @param preferGitHub 优先从 GitHub 下载（忽略外部目录）
     */
    suspend fun ensureInstalled(
        context: Context,
        force: Boolean = false,
        preferGitHub: Boolean = false
    ): InstallResult = withContext(Dispatchers.IO) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val installedHash = prefs.getString(KEY_INSTALLED_HASH, null)

        // 1. 优先检查外部目录（开发模式）
        if (!preferGitHub) {
            val externalWheel = findExternalWheel()
            if (externalWheel != null) {
                val externalHash = readExternalHash()

                // 检查是否需要更新
                if (!force && installedHash == externalHash && externalHash != null) {
                    OmniLog.d(TAG, "External wheel already installed (hash: ${externalHash.take(8)})")
                    return@withContext InstallResult(
                        success = true,
                        alreadyInstalled = true,
                        message = "OmniFlow 已安装（外部目录）",
                        source = "external",
                        hash = externalHash
                    )
                }

                OmniLog.i(TAG, "Installing from external directory: ${externalWheel.absolutePath}")
                return@withContext installFromFile(context, externalWheel, "external", externalHash)
            }
        }

        // 2. 从 GitHub 下载
        OmniLog.i(TAG, "No external wheel found, attempting GitHub download")
        return@withContext installFromGitHub(context, force)
    }

    /**
     * 从外部目录查找 wheel 文件。
     */
    private fun findExternalWheel(): File? {
        val dir = File(EXTERNAL_PACKAGE_DIR)
        if (!dir.exists() || !dir.isDirectory) {
            return null
        }
        return dir.listFiles()
            ?.filter { it.name.startsWith("omniflow-") && it.name.endsWith(".whl") }
            ?.maxByOrNull { it.lastModified() }
    }

    /**
     * 读取外部目录的 hash 标记。
     */
    private fun readExternalHash(): String? {
        val hashFile = File(EXTERNAL_PACKAGE_DIR, WHEEL_HASH_FILE)
        return if (hashFile.exists()) {
            hashFile.readText().trim().takeIf { it.isNotEmpty() }
        } else {
            null
        }
    }

    /**
     * 从文件安装 wheel。
     */
    private suspend fun installFromFile(
        context: Context,
        wheelFile: File,
        source: String,
        hash: String?
    ): InstallResult {
        // 使用 uv 安装（比 pip 快 10-100x）
        val command = """
            uv pip install --upgrade --force-reinstall "${wheelFile.absolutePath}" 2>&1
        """.trimIndent()

        val result = EmbeddedTerminalRuntime.executeCommand(
            context = context,
            command = command,
            workingDirectory = null,
            timeoutSeconds = 600  // 10 分钟超时（包含依赖安装）
        )

        return if (result.success) {
            // 记录安装信息
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .putString(KEY_INSTALLED_HASH, hash ?: wheelFile.name)
                .putString(KEY_INSTALL_SOURCE, source)
                .apply()

            OmniLog.i(TAG, "OmniFlow installed successfully from $source")
            InstallResult(
                success = true,
                alreadyInstalled = false,
                message = "OmniFlow 安装成功",
                source = source,
                hash = hash
            )
        } else {
            OmniLog.e(TAG, "OmniFlow install failed: ${result.errorMessage ?: result.output}")
            InstallResult(
                success = false,
                alreadyInstalled = false,
                message = result.errorMessage ?: "安装失败",
                source = null,
                hash = null
            )
        }
    }

    /**
     * 从 GitHub 下载并安装。
     */
    private suspend fun installFromGitHub(
        context: Context,
        force: Boolean
    ): InstallResult = withContext(Dispatchers.IO) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val installedHash = prefs.getString(KEY_INSTALLED_HASH, null)
        val installedSource = prefs.getString(KEY_INSTALL_SOURCE, null)

        // 如果已从 GitHub 安装且不强制，跳过
        if (!force && installedSource == "github" && installedHash != null) {
            return@withContext InstallResult(
                success = true,
                alreadyInstalled = true,
                message = "OmniFlow 已安装（GitHub）",
                source = "github",
                hash = installedHash
            )
        }

        OmniLog.i(TAG, "Downloading wheel from GitHub: $GITHUB_RELEASE_URL")

        val downloadDir = File(context.cacheDir, "omniflow-download")
        downloadDir.mkdirs()
        val targetFile = File(downloadDir, "omniflow-latest.whl")

        try {
            val client = OkHttpClient.Builder()
                .connectTimeout(30, TimeUnit.SECONDS)
                .readTimeout(300, TimeUnit.SECONDS)
                .followRedirects(true)
                .build()

            val request = Request.Builder()
                .url(GITHUB_RELEASE_URL)
                .build()

            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    return@withContext InstallResult(
                        success = false,
                        alreadyInstalled = false,
                        message = "GitHub 下载失败: HTTP ${response.code}",
                        source = null,
                        hash = null
                    )
                }

                response.body?.byteStream()?.use { input ->
                    targetFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
            }

            // 计算 hash
            val hash = targetFile.inputStream().use { input ->
                val digest = java.security.MessageDigest.getInstance("MD5")
                val buffer = ByteArray(8192)
                var read: Int
                while (input.read(buffer).also { read = it } != -1) {
                    digest.update(buffer, 0, read)
                }
                digest.digest().joinToString("") { "%02x".format(it) }
            }

            return@withContext installFromFile(context, targetFile, "github", hash)
        } catch (e: Exception) {
            OmniLog.e(TAG, "GitHub download failed", e)
            return@withContext InstallResult(
                success = false,
                alreadyInstalled = false,
                message = "GitHub 下载失败: ${e.message}",
                source = null,
                hash = null
            )
        } finally {
            // 清理下载文件
            runCatching { targetFile.delete() }
        }
    }

    /**
     * 检查 OmniFlow Provider 是否正在运行。
     */
    suspend fun isProviderRunning(context: Context): Boolean {
        val result = EmbeddedTerminalRuntime.executeCommand(
            context = context,
            command = "pgrep -f 'omniflow-provider\\|utg_api' || true",
            workingDirectory = null,
            timeoutSeconds = 10
        )
        return result.success && result.output.trim().isNotEmpty()
    }

    /**
     * 启动 OmniFlow Provider。
     */
    suspend fun startProvider(
        context: Context,
        port: Int = 19070
    ): EmbeddedTerminalRuntime.BackgroundServiceLaunchResult {
        val sessionId = "omniflow_provider"
        val command = "omniflow-provider --port $port"

        return EmbeddedTerminalRuntime.launchBackgroundServiceSession(
            context = context,
            sessionId = sessionId,
            command = command,
            workingDirectory = null
        )
    }

    /**
     * 停止 OmniFlow Provider。
     */
    suspend fun stopProvider(context: Context): Boolean {
        val sessionId = "omniflow_provider"
        return EmbeddedTerminalRuntime.stopSession(context, sessionId)
    }

    /**
     * 获取安装状态摘要。
     */
    fun getStatusSummary(context: Context): Map<String, Any?> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val externalWheel = findExternalWheel()
        return mapOf(
            "installed" to isInstalled(context),
            "installedHash" to prefs.getString(KEY_INSTALLED_HASH, null)?.take(8),
            "installSource" to prefs.getString(KEY_INSTALL_SOURCE, null),
            "externalWheelAvailable" to (externalWheel != null),
            "externalWheelPath" to externalWheel?.absolutePath,
            "externalHash" to readExternalHash()?.take(8),
            "githubUrl" to GITHUB_RELEASE_URL
        )
    }
}
