package cn.com.omnimind.bot.utg

import android.content.Context
import cn.com.omnimind.baselib.util.OmniLog
import cn.com.omnimind.bot.terminal.EmbeddedTerminalRuntime
import com.tencent.mmkv.MMKV
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * OmniFlow Embedded Provider 管理器
 * 负责下载、安装、启动和管理嵌入式 Provider
 */
object EmbeddedProviderManager {
    private const val TAG = "EmbeddedProviderManager"

    private const val MMKV_KEY_INSTALLED_VERSION = "embedded_provider_version"
    private const val MMKV_KEY_BINARY_PATH = "embedded_provider_path"

    private const val PROVIDER_FILENAME = "omniflow_provider"
    private const val DEFAULT_PORT = 19070

    // 二进制下载地址 (需要替换为实际 CDN 地址)
    private const val DOWNLOAD_URL_ARM64 = "https://your-cdn.com/omniflow_provider_arm64"
    private const val LATEST_VERSION = "0.1.0"

    private var providerSessionId: String? = null

    data class ProviderStatus(
        val installed: Boolean,
        val installedVersion: String?,
        val running: Boolean,
        val port: Int,
        val binaryPath: String?,
        val latestVersion: String = LATEST_VERSION,
        val needsUpdate: Boolean = false
    )

    data class InstallProgress(
        val stage: Stage,
        val progress: Float, // 0.0 - 1.0
        val message: String
    ) {
        enum class Stage {
            DOWNLOADING,
            INSTALLING,
            VERIFYING,
            COMPLETE,
            ERROR
        }
    }

    data class InstallResult(
        val success: Boolean,
        val version: String?,
        val binaryPath: String?,
        val error: String?
    )

    /**
     * 获取 Provider 状态
     */
    suspend fun getStatus(context: Context): ProviderStatus {
        val mmkv = MMKV.defaultMMKV() ?: return ProviderStatus(
            installed = false,
            installedVersion = null,
            running = false,
            port = DEFAULT_PORT,
            binaryPath = null
        )

        val installedVersion = mmkv.decodeString(MMKV_KEY_INSTALLED_VERSION)
        val binaryPath = mmkv.decodeString(MMKV_KEY_BINARY_PATH)
        val installed = !installedVersion.isNullOrEmpty() &&
                       !binaryPath.isNullOrEmpty() &&
                       File(binaryPath).exists()

        val running = isProviderRunning()

        return ProviderStatus(
            installed = installed,
            installedVersion = installedVersion,
            running = running,
            port = DEFAULT_PORT,
            binaryPath = binaryPath,
            latestVersion = LATEST_VERSION,
            needsUpdate = installed && installedVersion != LATEST_VERSION
        )
    }

    /**
     * 一键部署 Provider
     */
    suspend fun install(
        context: Context,
        downloadUrl: String? = null,
        onProgress: (InstallProgress) -> Unit = {}
    ): InstallResult = withContext(Dispatchers.IO) {
        try {
            onProgress(InstallProgress(
                InstallProgress.Stage.DOWNLOADING,
                0f,
                "正在下载 OmniFlow Provider..."
            ))

            // 准备安装目录
            val installDir = File(context.filesDir, "omniflow")
            installDir.mkdirs()
            val binaryFile = File(installDir, PROVIDER_FILENAME)

            // 下载二进制文件
            val url = downloadUrl ?: DOWNLOAD_URL_ARM64
            downloadFile(url, binaryFile) { progress ->
                onProgress(InstallProgress(
                    InstallProgress.Stage.DOWNLOADING,
                    progress,
                    "正在下载 OmniFlow Provider... ${(progress * 100).toInt()}%"
                ))
            }

            onProgress(InstallProgress(
                InstallProgress.Stage.INSTALLING,
                0.9f,
                "正在安装..."
            ))

            // 设置执行权限
            binaryFile.setExecutable(true, false)

            onProgress(InstallProgress(
                InstallProgress.Stage.VERIFYING,
                0.95f,
                "正在验证..."
            ))

            // 验证二进制
            if (!binaryFile.exists() || !binaryFile.canExecute()) {
                throw Exception("安装验证失败")
            }

            // 保存安装信息
            val mmkv = MMKV.defaultMMKV()
            mmkv?.encode(MMKV_KEY_INSTALLED_VERSION, LATEST_VERSION)
            mmkv?.encode(MMKV_KEY_BINARY_PATH, binaryFile.absolutePath)

            onProgress(InstallProgress(
                InstallProgress.Stage.COMPLETE,
                1f,
                "安装完成"
            ))

            OmniLog.i(TAG, "Embedded provider installed: ${binaryFile.absolutePath}")

            InstallResult(
                success = true,
                version = LATEST_VERSION,
                binaryPath = binaryFile.absolutePath,
                error = null
            )
        } catch (e: Exception) {
            OmniLog.e(TAG, "Install failed", e)
            onProgress(InstallProgress(
                InstallProgress.Stage.ERROR,
                0f,
                "安装失败: ${e.message}"
            ))
            InstallResult(
                success = false,
                version = null,
                binaryPath = null,
                error = e.message
            )
        }
    }

    /**
     * 启动 Provider
     */
    suspend fun start(context: Context, port: Int = DEFAULT_PORT): Boolean {
        val status = getStatus(context)
        if (!status.installed || status.binaryPath == null) {
            OmniLog.e(TAG, "Provider not installed")
            return false
        }

        if (status.running) {
            OmniLog.i(TAG, "Provider already running")
            return true
        }

        return try {
            // 在终端中启动 Provider
            val command = "${status.binaryPath} --port $port --host 127.0.0.1"
            val result = EmbeddedTerminalRuntime.launchBackgroundService(
                context = context,
                serviceKey = "omniflow_provider",
                launchCommand = command,
                healthCheckUrl = "http://127.0.0.1:$port/health",
                timeoutSeconds = 30
            )

            if (result.started || result.alreadyRunning) {
                providerSessionId = result.sessionId
                OmniLog.i(TAG, "Provider started on port $port")
                true
            } else {
                OmniLog.e(TAG, "Failed to start provider")
                false
            }
        } catch (e: Exception) {
            OmniLog.e(TAG, "Start failed", e)
            false
        }
    }

    /**
     * 停止 Provider
     */
    suspend fun stop(): Boolean {
        return try {
            providerSessionId?.let { sessionId ->
                EmbeddedTerminalRuntime.stopBackgroundService(sessionId)
            }
            providerSessionId = null
            OmniLog.i(TAG, "Provider stopped")
            true
        } catch (e: Exception) {
            OmniLog.e(TAG, "Stop failed", e)
            false
        }
    }

    /**
     * 检查 Provider 是否运行中
     */
    private suspend fun isProviderRunning(): Boolean {
        return try {
            withContext(Dispatchers.IO) {
                val url = URL("http://127.0.0.1:$DEFAULT_PORT/health")
                val conn = url.openConnection() as HttpURLConnection
                conn.connectTimeout = 2000
                conn.readTimeout = 2000
                conn.requestMethod = "GET"
                val code = conn.responseCode
                conn.disconnect()
                code == 200
            }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * 下载文件
     */
    private suspend fun downloadFile(
        urlStr: String,
        destFile: File,
        onProgress: (Float) -> Unit
    ) = withContext(Dispatchers.IO) {
        val url = URL(urlStr)
        val conn = url.openConnection() as HttpURLConnection
        conn.connectTimeout = 30000
        conn.readTimeout = 60000

        val totalSize = conn.contentLength
        var downloadedSize = 0

        conn.inputStream.use { input ->
            destFile.outputStream().use { output ->
                val buffer = ByteArray(8192)
                var bytesRead: Int
                while (input.read(buffer).also { bytesRead = it } != -1) {
                    output.write(buffer, 0, bytesRead)
                    downloadedSize += bytesRead
                    if (totalSize > 0) {
                        onProgress(downloadedSize.toFloat() / totalSize)
                    }
                }
            }
        }

        conn.disconnect()
    }

    /**
     * 卸载 Provider
     */
    suspend fun uninstall(context: Context): Boolean {
        return try {
            stop()

            val mmkv = MMKV.defaultMMKV()
            val binaryPath = mmkv?.decodeString(MMKV_KEY_BINARY_PATH)

            binaryPath?.let { path ->
                File(path).delete()
            }

            mmkv?.remove(MMKV_KEY_INSTALLED_VERSION)
            mmkv?.remove(MMKV_KEY_BINARY_PATH)

            OmniLog.i(TAG, "Provider uninstalled")
            true
        } catch (e: Exception) {
            OmniLog.e(TAG, "Uninstall failed", e)
            false
        }
    }
}
