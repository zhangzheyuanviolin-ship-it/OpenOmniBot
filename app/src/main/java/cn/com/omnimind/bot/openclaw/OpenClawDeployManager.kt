package cn.com.omnimind.bot.openclaw

import android.content.Context
import cn.com.omnimind.baselib.util.OmniLog
import cn.com.omnimind.bot.terminal.EmbeddedTerminalRuntime
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.security.SecureRandom

class OpenClawDeployManager(
    private val context: Context
) {
    data class DeployRequest(
        val providerBaseUrl: String,
        val providerApiKey: String,
        val modelId: String,
        val configJson: String
    )

    data class DeployStartResult(
        val accepted: Boolean,
        val alreadyRunning: Boolean,
        val message: String
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "accepted" to accepted,
            "alreadyRunning" to alreadyRunning,
            "message" to message
        )
    }

    data class DeploySnapshot(
        val running: Boolean = false,
        val completed: Boolean = false,
        val success: Boolean? = null,
        val progress: Double = 0.0,
        val stage: String = "",
        val logLines: List<String> = emptyList(),
        val gatewayBaseUrl: String? = null,
        val gatewayToken: String? = null,
        val errorMessage: String? = null
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "running" to running,
            "completed" to completed,
            "success" to success,
            "progress" to progress,
            "stage" to stage,
            "logLines" to logLines,
            "gatewayBaseUrl" to gatewayBaseUrl,
            "gatewayToken" to gatewayToken,
            "errorMessage" to errorMessage
        )
    }

    private data class DeployState(
        val running: Boolean = false,
        val completed: Boolean = false,
        val success: Boolean? = null,
        val progress: Double = 0.0,
        val stage: String = "",
        val logLines: List<String> = emptyList(),
        val gatewayBaseUrl: String? = null,
        val gatewayToken: String? = null,
        val errorMessage: String? = null
    )

    private companion object {
        private const val TAG = "OpenClawDeployManager"
        private const val MAX_LOG_LINES = 200
        private const val DEFAULT_COMMAND_TIMEOUT_SECONDS = 15 * 60
        private const val HEALTH_TIMEOUT_MS = 75_000L
        private val secureRandom = SecureRandom()
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val installRunner = OpenClawInstallCommandRunner(context)
    private val lock = Any()
    private var state = DeployState()

    fun getSnapshot(): DeploySnapshot {
        val current = synchronized(lock) { state }
        return DeploySnapshot(
            running = current.running,
            completed = current.completed,
            success = current.success,
            progress = current.progress,
            stage = current.stage,
            logLines = current.logLines,
            gatewayBaseUrl = current.gatewayBaseUrl,
            gatewayToken = current.gatewayToken,
            errorMessage = current.errorMessage
        )
    }

    fun startDeploy(request: DeployRequest): DeployStartResult {
        val baseUrl = request.providerBaseUrl.trim()
        val apiKey = request.providerApiKey.trim()
        val modelId = request.modelId.trim()
        val configJson = request.configJson.trim()
        require(baseUrl.isNotEmpty()) { "providerBaseUrl 不能为空" }
        require(apiKey.isNotEmpty()) { "providerApiKey 不能为空" }
        require(modelId.isNotEmpty()) { "modelId 不能为空" }
        require(configJson.isNotEmpty()) { "configJson 不能为空" }
        validateGatewayConfig(configJson)

        synchronized(lock) {
            if (state.running) {
                return DeployStartResult(
                    accepted = false,
                    alreadyRunning = true,
                    message = "OpenClaw 正在部署中，请稍候。"
                )
            }
            state = DeployState(
                running = true,
                completed = false,
                success = null,
                progress = 0.02,
                stage = "准备开始",
                logLines = listOf("[系统] 正在准备 OpenClaw 一键部署..."),
                gatewayBaseUrl = null,
                gatewayToken = null,
                errorMessage = null
            )
        }

        scope.launch {
            runDeploy(
                request = DeployRequest(
                    providerBaseUrl = baseUrl,
                    providerApiKey = apiKey,
                    modelId = modelId,
                    configJson = configJson
                )
            )
        }
        return DeployStartResult(
            accepted = true,
            alreadyRunning = false,
            message = "OpenClaw 部署已开始。"
        )
    }

    private suspend fun runDeploy(request: DeployRequest) {
        try {
            val readiness = EmbeddedTerminalRuntime.inspectRuntimeReadiness(context)
            if (!readiness.supported || !readiness.runtimeReady) {
                fail(
                    "内嵌 Ubuntu 运行时尚未完成初始化，请先打开终端环境配置完成初始化后再试。",
                    stage = "运行时未就绪",
                    progress = 0.05
                )
                return
            }

            val gatewayToken = generateGatewayToken()
            val normalizedConfigJson = OpenClawRuntimeSupport.normalizeConfigJson(
                request.configJson,
                gatewayToken
            )

            updateState(
                progress = 0.06,
                stage = "预检运行环境",
                appendLines = listOf(
                    "[系统] 将使用模型 ${request.modelId}",
                    "[系统] Provider: ${request.providerBaseUrl}"
                )
            )

            updateState(
                progress = 0.12,
                stage = "写入兼容补丁",
                appendLines = listOf("[阶段] 写入 Android / proot 兼容脚本")
            )
            OpenClawRuntimeSupport.ensureRuntimeFiles(context)
            OpenClawRuntimeSupport.saveProviderApiKey(context, request.providerApiKey)
            OpenClawRuntimeSupport.persistGatewayToken(context, gatewayToken)
            updateState(appendLines = listOf("[完成] 兼容脚本与安全存储已就绪"))

            val currentNodeMajor = probeNodeMajorVersion()
            val nodeLayoutNeedsRepair = OpenClawRuntimeSupport.nodeLayoutNeedsRepair(context)
            var nodeTarballPath = ""
            if (currentNodeMajor < OpenClawRuntimeSupport.TARGET_NODE_MAJOR || nodeLayoutNeedsRepair) {
                updateState(
                    progress = 0.18,
                    stage = "下载 Node.js",
                    appendLines = listOf(
                        if (nodeLayoutNeedsRepair) {
                            "[阶段] 检测到 Node.js 安装布局异常，准备下载官方 arm64 tarball 进行修复"
                        } else {
                            "[阶段] Node.js 版本过低，准备下载官方 arm64 tarball"
                        }
                    )
                )
                val tarball = OpenClawRuntimeSupport.downloadNodeTarball(context)
                nodeTarballPath = OpenClawRuntimeSupport.nodeTarballGuestPath()
                updateState(
                    appendLines = listOf(
                        "[完成] Node.js tarball 已就绪：${tarball.name}",
                        "[系统] tarball guest 路径：$nodeTarballPath"
                    )
                )
            } else {
                updateState(
                    appendLines = listOf("[系统] 已检测到 Node.js $currentNodeMajor，跳过下载")
                )
            }

            executeStep(
                stage = "安装或修复 Node.js",
                progress = 0.32,
                command = buildNodeSetupCommand(nodeTarballPath),
                timeoutSeconds = DEFAULT_COMMAND_TIMEOUT_SECONDS
            )

            executeStep(
                stage = "安装 OpenClaw CLI",
                progress = 0.50,
                command = buildInstallOpenClawCommand(),
                timeoutSeconds = DEFAULT_COMMAND_TIMEOUT_SECONDS
            )

            if (!OpenClawRuntimeSupport.ensureOpenClawWrapper(context)) {
                throw IllegalStateException("OpenClaw CLI 安装完成后未能修复 /usr/local/bin/openclaw")
            }
            updateState(
                progress = 0.56,
                stage = "修复 CLI 入口",
                appendLines = listOf("[完成] /usr/local/bin/openclaw 已校验")
            )

            writeConfigWithFallback(normalizedConfigJson)

            executeStep(
                stage = "校验 OpenClaw 配置",
                progress = 0.74,
                command = buildValidateConfigCommand(request.providerApiKey),
                timeoutSeconds = DEFAULT_COMMAND_TIMEOUT_SECONDS
            )

            updateState(
                progress = 0.84,
                stage = "启动 Gateway",
                appendLines = listOf("[阶段] 正在交给原生 GatewayService 接管运行")
            )
            OpenClawGatewayManager.startGateway(context, forceRestart = true)
            val healthy = OpenClawGatewayManager.awaitHealthy(context, HEALTH_TIMEOUT_MS)
            if (!healthy) {
                val gatewayStatus = OpenClawGatewayManager.getGatewayStatus(context)
                throw IllegalStateException(gatewayStatus.lastError ?: "Gateway 健康检查超时")
            }

            synchronized(lock) {
                state = state.copy(
                    running = false,
                    completed = true,
                    success = true,
                    progress = 1.0,
                    stage = "部署完成",
                    logLines = appendLinesLocked(
                        state.logLines,
                        listOf("[成功] OpenClaw 已部署完成，Gateway 运行正常。")
                    ),
                    gatewayBaseUrl = OpenClawRuntimeSupport.LOOPBACK_BASE_URL,
                    gatewayToken = gatewayToken,
                    errorMessage = null
                )
            }
        } catch (e: Exception) {
            OmniLog.e(TAG, "openclaw deploy failed", e)
            fail(
                message = e.message ?: "OpenClaw 部署失败",
                stage = "部署失败",
                progress = synchronized(lock) { state.progress.coerceAtLeast(0.1) }
            )
        }
    }

    private suspend fun executeStep(
        stage: String,
        progress: Double,
        command: String,
        timeoutSeconds: Int
    ) {
        updateState(
            progress = progress,
            stage = stage,
            appendLines = listOf("[阶段] $stage")
        )
        val result = executeCommand(command, timeoutSeconds)
        if (!result.success) {
            val output = result.output.ifBlank { result.errorMessage.orEmpty() }.trim()
            val errorText = if (output.isNotBlank()) {
                output
            } else {
                "执行失败，exit=${result.exitCode ?: -1}"
            }
            throw IllegalStateException(errorText)
        }
        updateState(appendLines = listOf("[完成] $stage"))
    }

    private suspend fun executeCommand(
        command: String,
        timeoutSeconds: Int
    ): OpenClawInstallCommandRunner.Result {
        return installRunner.execute(
            command = command,
            timeoutSeconds = timeoutSeconds,
            onOutputChunk = ::appendLogChunk
        )
    }

    private suspend fun writeConfigWithFallback(normalizedConfigJson: String) {
        updateState(
            progress = 0.62,
            stage = "写入 OpenClaw 配置",
            appendLines = listOf("[阶段] 正在写入 openclaw.json")
        )
        val result = executeCommand(
            buildWriteConfigCommand(normalizedConfigJson),
            timeoutSeconds = 120
        )
        if (result.success) {
            updateState(appendLines = listOf("[完成] OpenClaw 配置已通过 Ubuntu 内写入"))
            return
        }
        val fallbackFile = OpenClawRuntimeSupport.openClawConfigHostFile(context)
        fallbackFile.parentFile?.mkdirs()
        fallbackFile.writeText(normalizedConfigJson)
        updateState(
            appendLines = listOf(
                "[系统] Ubuntu 内写入失败，已自动切换为 rootfs 直写兜底。",
                "[完成] openclaw.json 已写入 ${fallbackFile.absolutePath}"
            )
        )
    }

    private suspend fun probeNodeMajorVersion(): Int {
        val result = executeCommand(
            """
            if command -v node >/dev/null 2>&1; then
              node -p "parseInt(process.versions.node.split('.')[0], 10)" 2>/dev/null || echo 0
            else
              echo 0
            fi
            """.trimIndent(),
            timeoutSeconds = 20
        )
        if (!result.success) {
            return 0
        }
        return result.output
            .lineSequence()
            .map { it.trim() }
            .firstOrNull { it.matches(Regex("""\d+""")) }
            ?.toIntOrNull()
            ?: 0
    }

    private fun buildNodeSetupCommand(nodeTarballPath: String): String {
        val quotedTarballPath = quoteShell(nodeTarballPath)
        return """
            set -euo pipefail
            export DEBIAN_FRONTEND=noninteractive
            apt-get update
            apt-get install -y ca-certificates curl procps psmisc xz-utils

            NODE_MAJOR=0
            if command -v node >/dev/null 2>&1; then
              NODE_MAJOR=$(node -p "parseInt(process.versions.node.split('.')[0], 10)" 2>/dev/null || echo 0)
            fi
            NODE_LAYOUT_OK=1
            if [ -L /usr/local/lib/node_modules ] || [ ! -f /usr/local/lib/node_modules/npm/bin/npm-cli.js ]; then
              NODE_LAYOUT_OK=0
            fi

            if [ "${'$'}NODE_MAJOR" -lt ${OpenClawRuntimeSupport.TARGET_NODE_MAJOR} ] || [ "${'$'}NODE_LAYOUT_OK" -ne 1 ]; then
              NODE_TARBALL=$quotedTarballPath
              if [ ! -f "${'$'}NODE_TARBALL" ]; then
                echo "Node.js tarball missing: ${'$'}NODE_TARBALL" >&2
                exit 1
              fi
              if [ -L /usr/local/lib/node_modules ]; then
                rm -f /usr/local/lib/node_modules
              fi
              rm -f /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack
              TMP_NODE_DIR=$(mktemp -d)
              tar -xJf "${'$'}NODE_TARBALL" -C "${'$'}TMP_NODE_DIR"
              NODE_EXTRACTED_DIR="${'$'}TMP_NODE_DIR/node-v${OpenClawRuntimeSupport.TARGET_NODE_VERSION}-linux-arm64"
              if [ ! -d "${'$'}NODE_EXTRACTED_DIR" ]; then
                echo "Node.js extraction layout unexpected: ${'$'}NODE_EXTRACTED_DIR" >&2
                rm -rf "${'$'}TMP_NODE_DIR"
                exit 1
              fi
              mkdir -p /usr/local
              cp -a "${'$'}NODE_EXTRACTED_DIR"/. /usr/local/
              rm -rf "${'$'}TMP_NODE_DIR"
            fi

            NPM_CLI=""
            for candidate in \
              /usr/local/lib/node_modules/npm/bin/npm-cli.js \
              /usr/share/nodejs/npm/bin/npm-cli.js; do
              if [ -f "${'$'}candidate" ]; then
                NPM_CLI="${'$'}candidate"
                break
              fi
            done

            node --version
            if [ -n "${'$'}NPM_CLI" ]; then
              node /root/.openclaw/node-wrapper.js "${'$'}NPM_CLI" --version
            else
              npm --version
            fi
        """.trimIndent()
    }

    private fun buildInstallOpenClawCommand(): String {
        return """
            set -euo pipefail
            mkdir -p /root/.openclaw /root/.openclaw/workspace
            mkdir -p /root/.npm /root/.config /root/.cache /root/.local/share
            mkdir -p /tmp/npm-cache/_cacache/tmp /tmp/npm-cache/_cacache/content-v2 /tmp/npm-cache/_cacache/index-v5 /tmp/npm-cache/_logs
            mkdir -p /usr/local/lib/node_modules /usr/local/bin
            if command -v openclaw >/dev/null 2>&1 && [ -f /usr/local/lib/node_modules/openclaw/package.json ]; then
              echo "openclaw already installed: $(command -v openclaw)"
              openclaw --version || true
              exit 0
            fi

            reset_npm_cache() {
              rm -rf /tmp/npm-cache /root/.npm/_cacache
              mkdir -p /tmp/npm-cache/_cacache/tmp /tmp/npm-cache/_cacache/content-v2 /tmp/npm-cache/_cacache/index-v5 /tmp/npm-cache/_logs
              mkdir -p /root/.npm /root/.config /root/.cache /root/.local/share
            }

            rm -rf /usr/local/lib/node_modules/openclaw /usr/local/bin/openclaw /usr/local/bin/openclaw.cmd || true
            reset_npm_cache

            export npm_config_cache=/tmp/npm-cache
            export npm_config_prefix=/usr/local
            export npm_config_update_notifier=false
            export npm_config_fund=false
            export npm_config_audit=false

            NPM_CLI=""
            for candidate in \
              /usr/local/lib/node_modules/npm/bin/npm-cli.js \
              /usr/share/nodejs/npm/bin/npm-cli.js; do
              if [ -f "${'$'}candidate" ]; then
                NPM_CLI="${'$'}candidate"
                break
              fi
            done

            if [ -z "${'$'}NPM_CLI" ]; then
              echo "Unable to locate npm-cli.js after Node.js setup; refusing to run bare npm inside proot." >&2
              exit 1
            fi

            echo "Using npm CLI: ${'$'}NPM_CLI"
            install_openclaw() {
              node /root/.openclaw/node-wrapper.js "${'$'}NPM_CLI" install -g --unsafe-perm \
                --no-audit --no-fund \
                --fetch-retries=5 --fetch-retry-factor=2 \
                --fetch-retry-mintimeout=1000 --fetch-retry-maxtimeout=20000 \
                openclaw
            }

            if ! install_openclaw; then
              echo "openclaw install attempt #1 failed; clearing caches and retrying once..." >&2
              rm -rf /usr/local/lib/node_modules/openclaw /usr/local/bin/openclaw /usr/local/bin/openclaw.cmd || true
              reset_npm_cache
              install_openclaw
            fi

            echo "openclaw installed"
            openclaw --version || true
        """.trimIndent()
    }

    private fun buildWriteConfigCommand(normalizedConfigJson: String): String {
        return listOf(
            "set -euo pipefail",
            "mkdir -p /root/.openclaw",
            "mkdir -p /root/.openclaw/workspace",
            "cat > ${OpenClawRuntimeSupport.OPENCLAW_CONFIG_PATH} <<'EOF'",
            normalizedConfigJson,
            "EOF",
            "test -s ${OpenClawRuntimeSupport.OPENCLAW_CONFIG_PATH}",
            "echo \"openclaw config written\""
        ).joinToString("\n")
    }

    private fun buildValidateConfigCommand(providerApiKey: String): String {
        val quotedApiKey = quoteShell(providerApiKey)
        return """
            set -euo pipefail
            export NODE_OPTIONS="--require /root/.openclaw/bionic-bypass.js"
            export ${OpenClawRuntimeSupport.PROVIDER_API_KEY_ENV}=$quotedApiKey
            openclaw config validate
            echo "openclaw config validated"
        """.trimIndent()
    }

    private fun updateState(
        progress: Double? = null,
        stage: String? = null,
        appendLines: List<String> = emptyList()
    ) {
        synchronized(lock) {
            val nextLogs = if (appendLines.isEmpty()) {
                state.logLines
            } else {
                appendLinesLocked(state.logLines, appendLines)
            }
            state = state.copy(
                progress = progress ?: state.progress,
                stage = stage ?: state.stage,
                logLines = nextLogs
            )
        }
    }

    private fun appendLogChunk(chunk: String) {
        val lines = chunk
            .replace("\r\n", "\n")
            .replace('\r', '\n')
            .lineSequence()
            .map { it.trimEnd() }
            .filter { it.isNotBlank() }
            .toList()
        if (lines.isEmpty()) {
            return
        }
        synchronized(lock) {
            state = state.copy(logLines = appendLinesLocked(state.logLines, lines))
        }
    }

    private suspend fun fail(
        message: String,
        stage: String,
        progress: Double
    ) {
        withContext(Dispatchers.IO) {
            synchronized(lock) {
                state = state.copy(
                    running = false,
                    completed = true,
                    success = false,
                    progress = progress,
                    stage = stage,
                    logLines = appendLinesLocked(
                        state.logLines,
                        listOf("[错误] $message")
                    ),
                    gatewayBaseUrl = null,
                    gatewayToken = null,
                    errorMessage = message
                )
            }
        }
    }

    private fun appendLinesLocked(current: List<String>, incoming: List<String>): List<String> {
        if (incoming.isEmpty()) {
            return current
        }
        val merged = buildList {
            addAll(current)
            incoming.forEach { line ->
                val trimmed = line.trimEnd()
                if (trimmed.isNotBlank()) {
                    add(trimmed)
                }
            }
        }
        return if (merged.size > MAX_LOG_LINES) {
            merged.takeLast(MAX_LOG_LINES)
        } else {
            merged
        }
    }

    private fun quoteShell(value: String): String {
        return "'" + value.replace("'", "'\"'\"'") + "'"
    }

    private fun validateGatewayConfig(configJson: String) {
        val root = try {
            JSONObject(configJson)
        } catch (e: Exception) {
            throw IllegalArgumentException("configJson 不是合法 JSON")
        }
        val gateway = root.optJSONObject("gateway")
            ?: throw IllegalArgumentException("configJson 缺少 gateway 配置")
        val auth = gateway.optJSONObject("auth")
            ?: throw IllegalArgumentException("configJson 缺少 gateway.auth 配置")
        val authMode = auth.optString("mode").trim()
        require(authMode == "token") { "gateway.auth.mode 必须保持为 token" }
    }

    private fun generateGatewayToken(): String {
        val bytes = ByteArray(24)
        secureRandom.nextBytes(bytes)
        return buildString(bytes.size * 2) {
            bytes.forEach { append("%02x".format(it)) }
        }
    }
}
