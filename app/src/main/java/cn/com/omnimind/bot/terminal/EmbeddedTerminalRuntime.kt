package cn.com.omnimind.bot.terminal

import android.content.Context
import android.os.Build
import cn.com.omnimind.bot.agent.AgentWorkspaceManager
import cn.com.omnimind.bot.termux.TermuxCommandBuilder
import cn.com.omnimind.bot.termux.TermuxLiveUpdate
import com.ai.assistance.operit.terminal.TerminalManager
import com.ai.assistance.operit.terminal.data.TerminalSessionData
import com.ai.assistance.operit.terminal.provider.type.HiddenExecResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

object EmbeddedTerminalRuntime {
    data class EnvironmentProgress(
        val kind: Kind,
        val message: String
    ) {
        enum class Kind {
            STATUS,
            OUTPUT,
            ERROR
        }
    }

    data class EnvironmentStatus(
        val success: Boolean,
        val initialized: Boolean,
        val basePackagesReady: Boolean,
        val message: String
    )

    data class RuntimeReadinessStatus(
        val supported: Boolean,
        val runtimeReady: Boolean,
        val basePackagesReady: Boolean,
        val missingCommands: List<String>,
        val message: String
    )

    data class CommandResult(
        val success: Boolean,
        val timedOut: Boolean,
        val exitCode: Int?,
        val output: String,
        val errorMessage: String?,
        val sessionId: String,
        val rawExtras: Map<String, Any?> = emptyMap()
    )

    data class SessionStartResult(
        val sessionId: String,
        val currentDirectory: String,
        val transcript: String
    )

    data class SessionCommandResult(
        val sessionId: String,
        val completed: Boolean,
        val success: Boolean,
        val exitCode: Int?,
        val output: String,
        val transcript: String,
        val currentDirectory: String,
        val errorMessage: String? = null
    )

    data class SessionReadResult(
        val sessionId: String,
        val transcript: String,
        val currentDirectory: String,
        val commandRunning: Boolean
    )

    private data class SessionHandle(
        val externalSessionId: String,
        val terminalSessionId: String,
        val mutex: Mutex = Mutex()
    )

    private data class BasePackageProbeResult(
        val missingCommands: List<String> = emptyList(),
        val errorMessage: String? = null
    )

    private const val PREFS_NAME = "embedded_terminal_runtime"
    private const val KEY_BASE_PACKAGE_VERSION = "base_package_version"
    private const val BASE_PACKAGE_VERSION = 2
    private const val SESSION_DONE_PREFIX = "__OMNIBOT_SESSION_DONE__"
    private const val DEFAULT_CURRENT_DIRECTORY = "/root"
    private const val BASE_PACKAGE_READY_MARKER = "__OMNIBOT_BASE_PACKAGES_READY__"
    private const val BASE_PACKAGE_MISSING_MARKER = "__OMNIBOT_BASE_PACKAGES_MISSING__"

    private val sessionHandles = ConcurrentHashMap<String, SessionHandle>()
    private val packageInstallMutex = Mutex()
    private val requiredCliCommands = listOf(
        "curl",
        "fuser",
        "git",
        "node",
        "npm",
        "pipx",
        "pkill",
        "python",
        "python3",
        "pip3",
        "rg",
        "tmux",
        "uv",
        "xz"
    )

    private val ansiEscapeRegex = Regex("""\u001B(?:\[[0-?]*[ -/]*[@-~]|\([A-Za-z0-9])""")
    private val knownNoiseRegexes = listOf(
        Regex("""^Warning: CPU doesn't support 32-bit instructions, some software may not work\.$"""),
        Regex("""^proot warning: can't sanitize binding "/proc/self/fd/\d+": No such file or directory$""")
    )

    private val basePackageBootstrapCommand = """
        export DEBIAN_FRONTEND=noninteractive
        apt-get update &&
        apt-get install -y \
          ca-certificates \
          curl \
          git \
          nodejs \
          npm \
          pipx \
          procps \
          psmisc \
          python-is-python3 \
          python3 \
          python3-pip \
          python3-venv \
          ripgrep \
          tmux \
          xz-utils && \
        export PATH="${'$'}HOME/.local/bin:${'$'}PATH" && \
        pipx install uv --force && \
        if [ -x "${'$'}HOME/.local/bin/uv" ]; then ln -sf "${'$'}HOME/.local/bin/uv" /usr/local/bin/uv; fi && \
        if [ -x "${'$'}HOME/.local/bin/uvx" ]; then ln -sf "${'$'}HOME/.local/bin/uvx" /usr/local/bin/uvx; fi
    """.trimIndent()

    fun isSupportedDevice(): Boolean {
        return Build.SUPPORTED_ABIS.any { it == "arm64-v8a" }
    }

    suspend fun warmup(
        context: Context,
        onProgress: suspend (EnvironmentProgress) -> Unit = {}
    ): EnvironmentStatus {
        return prepareEnvironment(
            context = context,
            installBasePackages = false,
            onProgress = onProgress
        )
    }

    suspend fun inspectRuntimeReadiness(
        context: Context,
        onProgress: suspend (EnvironmentProgress) -> Unit = {}
    ): RuntimeReadinessStatus {
        if (!isSupportedDevice()) {
            return RuntimeReadinessStatus(
                supported = false,
                runtimeReady = false,
                basePackagesReady = false,
                missingCommands = emptyList(),
                message = "当前设备 ABI 不受支持，内嵌 Ubuntu 终端仅支持 arm64-v8a。"
            )
        }

        val environmentStatus = prepareEnvironment(
            context = context,
            installBasePackages = false,
            onProgress = onProgress
        )
        if (!environmentStatus.success || !environmentStatus.initialized) {
            return RuntimeReadinessStatus(
                supported = true,
                runtimeReady = false,
                basePackagesReady = false,
                missingCommands = emptyList(),
                message = environmentStatus.message.ifBlank { "内嵌 Ubuntu 终端初始化失败。" }
            )
        }

        val probeResult = probeBasePackageCommands(context)
        val probeError = probeResult.errorMessage
        if (probeError != null) {
            return RuntimeReadinessStatus(
                supported = true,
                runtimeReady = true,
                basePackagesReady = false,
                missingCommands = emptyList(),
                message = probeError
            )
        }

        val missingCommands = probeResult.missingCommands
        if (missingCommands.isEmpty()) {
            markBasePackagesReady(context)
            return RuntimeReadinessStatus(
                supported = true,
                runtimeReady = true,
                basePackagesReady = true,
                missingCommands = emptyList(),
                message = "内嵌 Ubuntu 终端和基础 Agent CLI 包均已就绪。"
            )
        }

        return RuntimeReadinessStatus(
            supported = true,
            runtimeReady = true,
            basePackagesReady = false,
            missingCommands = missingCommands,
            message = "检测到基础 Agent CLI 包缺失：${missingCommands.joinToString(", ")}"
        )
    }

    suspend fun prepareEnvironment(
        context: Context,
        installBasePackages: Boolean,
        onProgress: suspend (EnvironmentProgress) -> Unit = {}
    ): EnvironmentStatus {
        if (!isSupportedDevice()) {
            emitEnvironmentProgress(
                onProgress,
                EnvironmentProgress(
                    kind = EnvironmentProgress.Kind.ERROR,
                    message = "当前设备 ABI 不受支持，内嵌 Ubuntu 终端仅支持 arm64-v8a。"
                )
            )
            return EnvironmentStatus(
                success = false,
                initialized = false,
                basePackagesReady = false,
                message = "当前设备 ABI 不受支持，内嵌 Ubuntu 终端仅支持 arm64-v8a。"
            )
        }

        emitEnvironmentProgress(
            onProgress,
            EnvironmentProgress(
                kind = EnvironmentProgress.Kind.STATUS,
                message = "正在准备 workspace 和运行目录"
            )
        )
        withContext(Dispatchers.IO) {
            AgentWorkspaceManager(context).ensureRuntimeDirectories()
        }

        val manager = terminalManager(context)
        emitEnvironmentProgress(
            onProgress,
            EnvironmentProgress(
                kind = EnvironmentProgress.Kind.STATUS,
                message = "正在初始化宿主终端运行时"
            )
        )
        val initialized =
            manager.initializeEnvironment { message ->
                emitEnvironmentProgress(
                    onProgress,
                    EnvironmentProgress(
                        kind = EnvironmentProgress.Kind.STATUS,
                        message = message
                    )
                )
            }
        if (!initialized) {
            emitEnvironmentProgress(
                onProgress,
                EnvironmentProgress(
                    kind = EnvironmentProgress.Kind.ERROR,
                    message = "内嵌 Ubuntu 终端初始化失败。"
                )
            )
            return EnvironmentStatus(
                success = false,
                initialized = false,
                basePackagesReady = isBasePackagesReady(context),
                message = "内嵌 Ubuntu 终端初始化失败。"
            )
        }

        if (!installBasePackages) {
            val basePackagesReady = isBasePackagesReady(context)
            emitEnvironmentProgress(
                onProgress,
                EnvironmentProgress(
                    kind = EnvironmentProgress.Kind.STATUS,
                    message = if (basePackagesReady) {
                        "内嵌 Ubuntu 终端已就绪。"
                    } else {
                        "内嵌 Ubuntu 终端已就绪，基础 Agent CLI 包尚未完成预装。"
                    }
                )
            )
            return EnvironmentStatus(
                success = true,
                initialized = true,
                basePackagesReady = basePackagesReady,
                message = if (basePackagesReady) {
                    "内嵌 Ubuntu 终端已就绪。"
                } else {
                    "内嵌 Ubuntu 终端已就绪，基础 Agent CLI 包尚未完成预装。"
                }
            )
        }

        return packageInstallMutex.withLock {
            emitEnvironmentProgress(
                onProgress,
                EnvironmentProgress(
                    kind = EnvironmentProgress.Kind.STATUS,
                    message = "正在检查基础 Agent CLI 包"
                )
            )
            val preflightProbe = probeBasePackageCommands(context)
            if (preflightProbe.errorMessage == null && preflightProbe.missingCommands.isEmpty()) {
                markBasePackagesReady(context)
                emitEnvironmentProgress(
                    onProgress,
                    EnvironmentProgress(
                        kind = EnvironmentProgress.Kind.STATUS,
                        message = "基础 Agent CLI 包已就绪。"
                    )
                )
                return@withLock EnvironmentStatus(
                    success = true,
                    initialized = true,
                    basePackagesReady = true,
                    message = "内嵌 Ubuntu 终端和基础 Agent CLI 包均已就绪。"
                )
            }

            if (preflightProbe.missingCommands.isNotEmpty()) {
                emitEnvironmentProgress(
                    onProgress,
                    EnvironmentProgress(
                        kind = EnvironmentProgress.Kind.STATUS,
                        message = "检测到基础 Agent CLI 包缺失：${preflightProbe.missingCommands.joinToString(", ")}"
                    )
                )
            } else if (preflightProbe.errorMessage != null && isBasePackagesReady(context)) {
                emitEnvironmentProgress(
                    onProgress,
                    EnvironmentProgress(
                        kind = EnvironmentProgress.Kind.STATUS,
                        message = "基础 Agent CLI 包检查异常，准备重新安装。"
                    )
                )
            }

            emitEnvironmentProgress(
                onProgress,
                EnvironmentProgress(
                    kind = EnvironmentProgress.Kind.STATUS,
                    message = "正在安装基础 Agent CLI 包（git、python、node 等）"
                )
            )
            val installResult = manager.executeHiddenCommand(
                command = basePackageBootstrapCommand,
                executorKey = "embedded-bootstrap",
                timeoutMs = 15 * 60 * 1000L,
                onOutputChunk = { chunk ->
                    val normalizedChunk = chunk.replace("\r\n", "\n").replace('\r', '\n')
                    if (normalizedChunk.isNotBlank()) {
                        emitEnvironmentProgress(
                            onProgress,
                            EnvironmentProgress(
                                kind = EnvironmentProgress.Kind.OUTPUT,
                                message = normalizedChunk
                            )
                        )
                    }
                }
            )
            if (installResult.isOk && installResult.exitCode == 0) {
                val postInstallProbe = probeBasePackageCommands(context)
                if (postInstallProbe.errorMessage == null && postInstallProbe.missingCommands.isEmpty()) {
                    markBasePackagesReady(context)
                    emitEnvironmentProgress(
                        onProgress,
                        EnvironmentProgress(
                            kind = EnvironmentProgress.Kind.STATUS,
                            message = "基础 Agent CLI 包安装完成。"
                        )
                    )
                    return@withLock EnvironmentStatus(
                        success = true,
                        initialized = true,
                        basePackagesReady = true,
                        message = "内嵌 Ubuntu 终端和基础 Agent CLI 包均已就绪。"
                    )
                }
                val failureMessage = postInstallProbe.errorMessage
                    ?: buildMissingBasePackageFailureMessage(postInstallProbe.missingCommands)
                emitEnvironmentProgress(
                    onProgress,
                    EnvironmentProgress(
                        kind = EnvironmentProgress.Kind.ERROR,
                        message = failureMessage
                    )
                )
                EnvironmentStatus(
                    success = false,
                    initialized = true,
                    basePackagesReady = false,
                    message = failureMessage
                )
            } else {
                val failureMessage = buildInstallFailureMessage(installResult)
                emitEnvironmentProgress(
                    onProgress,
                    EnvironmentProgress(
                        kind = EnvironmentProgress.Kind.ERROR,
                        message = failureMessage
                    )
                )
                EnvironmentStatus(
                    success = false,
                    initialized = true,
                    basePackagesReady = false,
                    message = failureMessage
                )
            }
        }
    }

    suspend fun executeCommand(
        context: Context,
        command: String,
        workingDirectory: String?,
        timeoutSeconds: Int,
        onLiveUpdate: suspend (TermuxLiveUpdate) -> Unit = {}
    ): CommandResult {
        val status = ensureCommandEnvironmentReady(context) { progress ->
            if (progress.message.isBlank()) return@ensureCommandEnvironmentReady
            onLiveUpdate(
                TermuxLiveUpdate(
                    sessionId = "env-bootstrap",
                    summary = progress.message,
                    outputDelta = if (progress.kind == EnvironmentProgress.Kind.OUTPUT) progress.message else "",
                    streamState = when (progress.kind) {
                        EnvironmentProgress.Kind.ERROR -> "error"
                        else -> "running"
                    }
                )
            )
        }
        val liveSessionId = UUID.randomUUID().toString()
        if (!status.success) {
            return CommandResult(
                success = false,
                timedOut = false,
                exitCode = null,
                output = "",
                errorMessage = status.message,
                sessionId = liveSessionId
            )
        }

        onLiveUpdate(
            TermuxLiveUpdate(
                sessionId = liveSessionId,
                summary = "正在执行内嵌 Ubuntu 终端命令",
                streamState = "running"
            )
        )

        val wrappedCommand = wrapOneShotCommand(command, workingDirectory)
        val hiddenResult = terminalManager(context).executeHiddenCommand(
            command = wrappedCommand,
            executorKey = buildExecutorKey(workingDirectory),
            timeoutMs = timeoutSeconds * 1000L
        )
        val cleanedOutput = sanitizeTerminalNoise(hiddenResult.output)
        val trimmedOutput = trimTerminalOutput(cleanedOutput)
        val timedOut = hiddenResult.state == HiddenExecResult.State.TIMEOUT
        val success = hiddenResult.isOk && hiddenResult.exitCode == 0
        val errorMessage = when {
            timedOut -> "终端命令等待超时，可能仍在后台继续运行。"
            hiddenResult.error.isNotBlank() -> hiddenResult.error
            !success && trimmedOutput.isBlank() && hiddenResult.rawOutputPreview.isNotBlank() -> hiddenResult.rawOutputPreview
            else -> null
        }

        if (trimmedOutput.isNotBlank()) {
            onLiveUpdate(
                TermuxLiveUpdate(
                    sessionId = liveSessionId,
                    summary = if (timedOut) "终端命令超时，已返回当前可见输出" else "终端命令执行完成",
                    outputDelta = trimmedOutput.takeLast(4000),
                    streamState = if (timedOut) "running" else "completed"
                )
            )
        }

        return CommandResult(
            success = success,
            timedOut = timedOut,
            exitCode = hiddenResult.exitCode.takeIf { hiddenResult.state == HiddenExecResult.State.OK },
            output = trimmedOutput,
            errorMessage = errorMessage,
            sessionId = liveSessionId,
            rawExtras = buildMap {
                put("hiddenExecState", hiddenResult.state.name)
                if (hiddenResult.rawOutputPreview.isNotBlank()) {
                    put("rawOutputPreview", hiddenResult.rawOutputPreview)
                }
                put("basePackagesReady", status.basePackagesReady)
            }
        )
    }

    suspend fun startSession(
        context: Context,
        requestedSessionId: String,
        workingDirectory: String?
    ): SessionStartResult {
        val status = ensureCommandEnvironmentReady(context)
        require(status.success) { status.message }

        val manager = terminalManager(context)
        val existingHandle = sessionHandles[requestedSessionId]
        val activeHandle = existingHandle?.takeIf { getTerminalSession(context, it) != null }
        val createdNewSession: Boolean

        if (activeHandle != null) {
            createdNewSession = false
        } else {
            if (existingHandle != null) {
                sessionHandles.remove(requestedSessionId, existingHandle)
                runCatching {
                    manager.closeSession(existingHandle.terminalSessionId)
                }
            }
            val created = manager.createNewSession(requestedSessionId)
            sessionHandles[requestedSessionId] = SessionHandle(
                externalSessionId = requestedSessionId,
                terminalSessionId = created.id
            )
            createdNewSession = true
        }

        if (createdNewSession && !workingDirectory.isNullOrBlank()) {
            val cwdResult = executeSessionCommand(
                context = context,
                sessionId = requestedSessionId,
                command = "cd ${TermuxCommandBuilder.quoteForShell(workingDirectory)}",
                workingDirectory = null,
                timeoutSeconds = 30
            )
            require(cwdResult.completed && cwdResult.success) {
                cwdResult.errorMessage ?: "无法切换到工作目录：$workingDirectory"
            }
        }

        val snapshot = readSession(context, requestedSessionId)
        return SessionStartResult(
            sessionId = requestedSessionId,
            currentDirectory = snapshot.currentDirectory,
            transcript = snapshot.transcript
        )
    }

    suspend fun executeSessionCommand(
        context: Context,
        sessionId: String,
        command: String,
        workingDirectory: String?,
        timeoutSeconds: Int
    ): SessionCommandResult {
        val handle = sessionHandles[sessionId]
            ?: return SessionCommandResult(
                sessionId = sessionId,
                completed = false,
                success = false,
                exitCode = null,
                output = "",
                transcript = "",
                currentDirectory = DEFAULT_CURRENT_DIRECTORY,
                errorMessage = "终端会话不存在：$sessionId"
            )

        val status = ensureCommandEnvironmentReady(context)
        if (!status.success) {
            return SessionCommandResult(
                sessionId = sessionId,
                completed = false,
                success = false,
                exitCode = null,
                output = "",
                transcript = "",
                currentDirectory = DEFAULT_CURRENT_DIRECTORY,
                errorMessage = status.message
            )
        }

        return handle.mutex.withLock {
            val preSnapshot = readSession(context, sessionId)
            if (preSnapshot.commandRunning) {
                return@withLock SessionCommandResult(
                    sessionId = sessionId,
                    completed = false,
                    success = false,
                    exitCode = null,
                    output = "",
                    transcript = preSnapshot.transcript,
                    currentDirectory = preSnapshot.currentDirectory,
                    errorMessage = "当前会话仍有命令在执行，请先读取输出或停止会话。"
                )
            }

            if (!workingDirectory.isNullOrBlank()) {
                val cwdResult = sendSessionCommandAndAwait(
                    context = context,
                    handle = handle,
                    command = "cd ${TermuxCommandBuilder.quoteForShell(workingDirectory)}",
                    timeoutSeconds = 30
                )
                if (!cwdResult.completed || !cwdResult.success) {
                    return@withLock cwdResult.copy(sessionId = sessionId)
                }
            }

            sendSessionCommandAndAwait(
                context = context,
                handle = handle,
                command = command,
                timeoutSeconds = timeoutSeconds
            ).copy(sessionId = sessionId)
        }
    }

    suspend fun readSession(
        context: Context,
        sessionId: String
    ): SessionReadResult {
        val handle = sessionHandles[sessionId]
            ?: return SessionReadResult(
                sessionId = sessionId,
                transcript = "",
                currentDirectory = DEFAULT_CURRENT_DIRECTORY,
                commandRunning = false
            )

        val session = getTerminalSession(context, handle) ?: run {
            sessionHandles.remove(sessionId)
            return SessionReadResult(
                sessionId = sessionId,
                transcript = "",
                currentDirectory = DEFAULT_CURRENT_DIRECTORY,
                commandRunning = false
            )
        }

        return SessionReadResult(
            sessionId = sessionId,
            transcript = buildTranscript(session),
            currentDirectory = normalizeCurrentDirectory(session.currentDirectory),
            commandRunning = session.currentExecutingCommand?.isExecuting == true
        )
    }

    fun stopSession(context: Context, sessionId: String): Boolean {
        val handle = sessionHandles.remove(sessionId) ?: return false
        terminalManager(context).closeSession(handle.terminalSessionId)
        return true
    }

    private suspend fun sendSessionCommandAndAwait(
        context: Context,
        handle: SessionHandle,
        command: String,
        timeoutSeconds: Int
    ): SessionCommandResult = coroutineScope {
        val manager = terminalManager(context)
        val commandId = UUID.randomUUID().toString()
        val token = UUID.randomUUID().toString()
        val awaited = async {
            withTimeoutOrNull(timeoutSeconds * 1000L) {
                manager.commandExecutionEvents.first { event ->
                    event.sessionId == handle.terminalSessionId &&
                        event.commandId == commandId &&
                        event.isCompleted
                }
            }
        }

        manager.sendCommandToSession(
            sessionId = handle.terminalSessionId,
            command = wrapPersistentSessionCommand(command, token),
            commandId = commandId
        )

        val completion = awaited.await()
        val snapshot = readSession(context, handle.externalSessionId)
        if (completion == null) {
            return@coroutineScope SessionCommandResult(
                sessionId = handle.externalSessionId,
                completed = false,
                success = false,
                exitCode = null,
                output = "",
                transcript = snapshot.transcript,
                currentDirectory = snapshot.currentDirectory,
                errorMessage = "终端会话命令执行超时，可能仍在后台继续运行。"
            )
        }

        val parsed = parsePersistentCommandOutput(completion.outputChunk, token)
        val cleanedOutput = trimTerminalOutput(sanitizeTerminalNoise(parsed.output))
        SessionCommandResult(
            sessionId = handle.externalSessionId,
            completed = true,
            success = parsed.exitCode == 0,
            exitCode = parsed.exitCode,
            output = cleanedOutput,
            transcript = snapshot.transcript,
            currentDirectory = snapshot.currentDirectory,
            errorMessage = if (parsed.exitCode == 0) null else "终端会话命令执行失败（exit=${parsed.exitCode})"
        )
    }

    private fun wrapOneShotCommand(command: String, workingDirectory: String?): String {
        val trimmedCommand = command.trim()
        val normalizedWorkingDirectory = workingDirectory?.trim().orEmpty()
        return buildString {
            appendLine(buildPythonEnvironmentPrelude())
            if (normalizedWorkingDirectory.isNotBlank()) {
                append("cd ")
                append(TermuxCommandBuilder.quoteForShell(normalizedWorkingDirectory))
                appendLine(" || exit $?")
            }
            appendLine("__omni_prepare_python_env 0 || exit $?")
            append(trimmedCommand)
        }
    }

    private fun wrapPersistentSessionCommand(command: String, token: String): String {
        val normalizedCommand = command.replace("\r\n", "\n").replace("\r", "\n")
        val tokenSuffix = token.replace("-", "")
        val heredocMarker = "__OMNIBOT_SESSION_${tokenSuffix}__"
        return buildString {
            append("__omnibot_session_script=\"\${TMPDIR:-/tmp}/omni_session_")
            append(tokenSuffix)
            append(".sh\"\n")
            append("cat >\"\$__omnibot_session_script\" <<'")
            append(heredocMarker)
            append("'\n")
            append(buildPythonEnvironmentPrelude())
            append("\n")
            append("__omni_prepare_python_env 0 || return $?\n")
            append(normalizedCommand)
            if (!normalizedCommand.endsWith("\n")) {
                append('\n')
            }
            append(heredocMarker)
            append("\n")
            append(". \"\$__omnibot_session_script\"\n")
            append("__omnibot_session_rc=\$?\n")
            append("rm -f \"\$__omnibot_session_script\"\n")
            append("printf '\\n")
            append(SESSION_DONE_PREFIX)
            append(":")
            append(token)
            append(":%s\\n' \"\$__omnibot_session_rc\"\n")
        }
    }

    internal fun buildPythonEnvironmentPrelude(): String = """
        export PATH="${'$'}HOME/.local/bin:${'$'}PATH"
        export UV_LINK_MODE=copy
        __omni_workspace_root=${TermuxCommandBuilder.quoteForShell(AgentWorkspaceManager.SHELL_ROOT_PATH)}
        __omni_uv_env_root="${'$'}HOME/.cache/omnibot/uv-project-envs"

        __omni_locate_python_project_root() {
          __omni_current_dir="${'$'}PWD"
          case "${'$'}__omni_current_dir" in
            "${'$'}__omni_workspace_root"|${'$'}__omni_workspace_root/*) ;;
            *) return 1 ;;
          esac
          while true; do
            if [ -f "${'$'}__omni_current_dir/.venv/bin/activate" ] || \
               [ -f "${'$'}__omni_current_dir/pyproject.toml" ] || \
               [ -f "${'$'}__omni_current_dir/requirements.txt" ] || \
               [ -f "${'$'}__omni_current_dir/requirements-dev.txt" ] || \
               [ -f "${'$'}__omni_current_dir/setup.py" ] || \
               [ -f "${'$'}__omni_current_dir/setup.cfg" ] || \
               [ -f "${'$'}__omni_current_dir/Pipfile" ] || \
               [ -f "${'$'}__omni_current_dir/poetry.lock" ] || \
               [ -f "${'$'}__omni_current_dir/pytest.ini" ] || \
               [ -f "${'$'}__omni_current_dir/tox.ini" ] || \
               [ -f "${'$'}__omni_current_dir/manage.py" ]; then
              printf '%s\n' "${'$'}__omni_current_dir"
              return 0
            fi
            if [ "${'$'}__omni_current_dir" = "${'$'}__omni_workspace_root" ]; then
              break
            fi
            __omni_parent_dir=$(dirname "${'$'}__omni_current_dir")
            if [ "${'$'}__omni_parent_dir" = "${'$'}__omni_current_dir" ]; then
              break
            fi
            __omni_current_dir="${'$'}__omni_parent_dir"
          done
          return 1
        }

        __omni_find_python_project_root() {
          __omni_locate_python_project_root
          __omni_locate_rc="${'$'}?"
          if [ "${'$'}__omni_locate_rc" -eq 0 ]; then
            return 0
          fi
          printf '%s\n' "${'$'}PWD"
        }

        __omni_activate_virtualenv() {
          __omni_target_venv="${'$'}1"
          if [ ! -f "${'$'}__omni_target_venv/bin/activate" ]; then
            return 1
          fi
          if [ "${'$'}VIRTUAL_ENV" != "${'$'}__omni_target_venv" ]; then
            if [ -n "${'$'}VIRTUAL_ENV" ] && command -v deactivate >/dev/null 2>&1; then
              deactivate >/dev/null 2>&1 || true
            fi
            . "${'$'}__omni_target_venv/bin/activate" || return ${'$'}?
          fi
          return 0
        }

        __omni_cleanup_invalid_virtualenv() {
          __omni_candidate_venv="${'$'}1"
          if [ ! -d "${'$'}__omni_candidate_venv" ]; then
            return 0
          fi
          if [ -x "${'$'}__omni_candidate_venv/bin/python" ] || [ -x "${'$'}__omni_candidate_venv/bin/python3" ]; then
            return 0
          fi
          if [ -f "${'$'}__omni_candidate_venv/bin/activate" ] || [ -f "${'$'}__omni_candidate_venv/pyvenv.cfg" ] || [ -d "${'$'}__omni_candidate_venv/bin" ]; then
            printf '[omnibot] Removing invalid virtual environment at %s\n' "${'$'}__omni_candidate_venv" >&2
            rm -rf "${'$'}__omni_candidate_venv" || return ${'$'}?
          fi
          return 0
        }

        __omni_prepare_python_env() {
          __omni_create_if_missing="${'$'}1"
          __omni_project_root=$(__omni_locate_python_project_root 2>/dev/null)
          __omni_project_root_rc="${'$'}?"
          if [ "${'$'}__omni_project_root_rc" -ne 0 ]; then
            if [ -n "${'$'}VIRTUAL_ENV" ] && [ -f "${'$'}VIRTUAL_ENV/bin/activate" ]; then
              return 0
            fi
            if [ "${'$'}__omni_create_if_missing" != "1" ]; then
              return 0
            fi
            __omni_project_root="${'$'}PWD"
          fi
          __omni_venv_dir="${'$'}__omni_project_root/.venv"
          __omni_cleanup_invalid_virtualenv "${'$'}__omni_venv_dir" || return ${'$'}?
          if [ ! -f "${'$'}__omni_venv_dir/bin/activate" ] && [ "${'$'}__omni_create_if_missing" = "1" ]; then
            if [ -d "${'$'}__omni_venv_dir" ]; then
              rm -rf "${'$'}__omni_venv_dir" || return ${'$'}?
            fi
            printf '[omnibot] Creating Python virtual environment at %s\n' "${'$'}__omni_venv_dir" >&2
            command python3 -m venv --copies "${'$'}__omni_venv_dir" || return ${'$'}?
          fi
          if [ -f "${'$'}__omni_venv_dir/bin/activate" ]; then
            __omni_activate_virtualenv "${'$'}__omni_venv_dir" || return ${'$'}?
          fi
          return 0
        }

        __omni_find_uv_workspace_root() {
          __omni_uv_root=$(__omni_locate_python_project_root 2>/dev/null)
          if [ "${'$'}?" -eq 0 ] && [ -n "${'$'}__omni_uv_root" ]; then
            printf '%s\n' "${'$'}__omni_uv_root"
            return 0
          fi
          case "${'$'}PWD" in
            "${'$'}__omni_workspace_root"|${'$'}__omni_workspace_root/*)
              printf '%s\n' "${'$'}PWD"
              return 0
              ;;
            *)
              return 1
              ;;
          esac
        }

        __omni_uv_env_dir_for_root() {
          __omni_uv_root="${'$'}1"
          mkdir -p "${'$'}__omni_uv_env_root" || return ${'$'}?
          __omni_uv_key=$(command python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest())' "${'$'}__omni_uv_root") || return ${'$'}?
          printf '%s/%s\n' "${'$'}__omni_uv_env_root" "${'$'}__omni_uv_key"
        }

        __omni_uv_resolve_target_path() {
          __omni_uv_target="${'$'}1"
          case "${'$'}__omni_uv_target" in
            /*)
              printf '%s\n' "${'$'}__omni_uv_target"
              ;;
            *)
              printf '%s/%s\n' "${'$'}PWD" "${'$'}__omni_uv_target"
              ;;
          esac
        }

        __omni_path_is_under_workspace() {
          __omni_candidate="${'$'}1"
          case "${'$'}__omni_candidate" in
            "${'$'}__omni_workspace_root"|${'$'}__omni_workspace_root/*) return 0 ;;
            *) return 1 ;;
          esac
        }

        uv() {
          __omni_uv_root=$(__omni_find_uv_workspace_root 2>/dev/null)
          if [ "${'$'}?" -ne 0 ] || [ -z "${'$'}__omni_uv_root" ]; then
            command uv "${'$'}@"
            return ${'$'}?
          fi

          __omni_cleanup_invalid_virtualenv "${'$'}__omni_uv_root/.venv" || return ${'$'}?
          __omni_uv_env_dir=$(__omni_uv_env_dir_for_root "${'$'}__omni_uv_root") || return ${'$'}?
          __omni_uv_rc=0

          if [ "${'$'}1" = "venv" ]; then
            shift
            __omni_uv_has_target=0
            __omni_uv_target_path=""
            for __omni_uv_arg in "${'$'}@"; do
              case "${'$'}__omni_uv_arg" in
                -*) ;;
                *)
                  __omni_uv_has_target=1
                  __omni_uv_target_path="${'$'}__omni_uv_arg"
                  break
                  ;;
              esac
            done
            if [ "${'$'}__omni_uv_has_target" = "1" ]; then
              __omni_uv_target_abs=$(__omni_uv_resolve_target_path "${'$'}__omni_uv_target_path")
              if __omni_path_is_under_workspace "${'$'}__omni_uv_target_abs"; then
                command uv venv --link-mode copy "${'$'}@"
              else
                command uv venv "${'$'}@"
              fi
              __omni_uv_rc="${'$'}?"
              if [ "${'$'}__omni_uv_rc" -eq 0 ] && [ -f "${'$'}__omni_uv_target_abs/bin/activate" ]; then
                __omni_activate_virtualenv "${'$'}__omni_uv_target_abs" || return ${'$'}?
              fi
            else
              command uv venv --link-mode copy "${'$'}@" "${'$'}__omni_uv_env_dir"
              __omni_uv_rc="${'$'}?"
            fi
          else
            UV_PROJECT_ENVIRONMENT="${'$'}__omni_uv_env_dir" command uv "${'$'}@"
            __omni_uv_rc="${'$'}?"
          fi

          if [ "${'$'}__omni_uv_rc" -eq 0 ] && [ -f "${'$'}__omni_uv_env_dir/bin/activate" ]; then
            __omni_activate_virtualenv "${'$'}__omni_uv_env_dir" || return ${'$'}?
          fi
          return "${'$'}__omni_uv_rc"
        }

        python() {
          if [ "${'$'}1" = "-m" ] && [ "${'$'}2" = "venv" ]; then
            command python "${'$'}@"
            return ${'$'}?
          fi
          __omni_prepare_python_env 1 || return ${'$'}?
          command python "${'$'}@"
        }

        python3() {
          if [ "${'$'}1" = "-m" ] && [ "${'$'}2" = "venv" ]; then
            command python3 "${'$'}@"
            return ${'$'}?
          fi
          __omni_prepare_python_env 1 || return ${'$'}?
          command python3 "${'$'}@"
        }

        pip() {
          __omni_prepare_python_env 1 || return ${'$'}?
          command python -m pip "${'$'}@"
        }

        pip3() {
          __omni_prepare_python_env 1 || return ${'$'}?
          command python -m pip "${'$'}@"
        }

        pytest() {
          __omni_prepare_python_env 1 || return ${'$'}?
          command python -m pytest "${'$'}@"
        }
    """.trimIndent()

    private fun parsePersistentCommandOutput(
        rawOutput: String,
        token: String
    ): ParsedSessionCommandOutput {
        val regex = Regex("""(?:^|\n)${Regex.escape(SESSION_DONE_PREFIX)}:${Regex.escape(token)}:(-?\d+)\s*$""")
        val match = regex.find(rawOutput)
        val exitCode = match?.groupValues?.getOrNull(1)?.toIntOrNull()
        val cleaned = if (match != null) {
            rawOutput.removeRange(match.range).trim('\n', '\r')
        } else {
            rawOutput.trim('\n', '\r')
        }
        return ParsedSessionCommandOutput(
            output = cleaned,
            exitCode = exitCode
        )
    }

    private fun buildExecutorKey(workingDirectory: String?): String {
        val normalized = workingDirectory?.trim().orEmpty()
        return if (normalized.isBlank()) {
            "embedded-default"
        } else {
            "embedded-${normalized.hashCode()}"
        }
    }

    private fun terminalManager(context: Context): TerminalManager {
        return TerminalManager.getInstance(context.applicationContext)
    }

    private fun getTerminalSession(
        context: Context,
        handle: SessionHandle
    ): TerminalSessionData? {
        return terminalManager(context).terminalState.value.sessions.find { session ->
            session.id == handle.terminalSessionId
        }
    }

    private fun buildTranscript(session: TerminalSessionData): String {
        val lines = session.ansiParser.getFullContent().map { row ->
            buildString(row.size) {
                row.forEach { terminalChar ->
                    append(terminalChar.char)
                }
            }.trimEnd()
        }.toMutableList()

        while (lines.isNotEmpty() && lines.last().isBlank()) {
            lines.removeAt(lines.lastIndex)
        }

        return trimTerminalOutput(
            sanitizeTerminalNoise(lines.joinToString("\n").trim('\n'))
        )
    }

    private fun normalizeCurrentDirectory(prompt: String): String {
        val cleaned = prompt.trim().replace(Regex("""\s+[#$]\s*$"""), "")
        return if (cleaned.isBlank() || cleaned == "$") {
            DEFAULT_CURRENT_DIRECTORY
        } else {
            cleaned
        }
    }

    private fun isBasePackagesReady(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getInt(KEY_BASE_PACKAGE_VERSION, 0) >= BASE_PACKAGE_VERSION
    }

    private fun markBasePackagesReady(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_BASE_PACKAGE_VERSION, BASE_PACKAGE_VERSION)
            .apply()
    }

    private suspend fun ensureCommandEnvironmentReady(
        context: Context,
        onProgress: suspend (EnvironmentProgress) -> Unit = {}
    ): EnvironmentStatus {
        val status = prepareEnvironment(
            context = context,
            installBasePackages = false,
            onProgress = onProgress
        )
        if (!status.success || status.basePackagesReady) {
            return status
        }
        return prepareEnvironment(
            context = context,
            installBasePackages = true,
            onProgress = onProgress
        )
    }

    private suspend fun probeBasePackageCommands(context: Context): BasePackageProbeResult {
        val result = terminalManager(context).executeHiddenCommand(
            command = buildBasePackageProbeCommand(),
            executorKey = "embedded-healthcheck",
            timeoutMs = 60 * 1000L
        )
        if (!result.isOk || result.exitCode != 0) {
            val output = sanitizeTerminalNoise(result.output).takeLast(1200).trim()
            val fallback = result.rawOutputPreview.takeLast(1200).trim()
            val details = when {
                output.isNotBlank() -> output
                fallback.isNotBlank() -> fallback
                result.error.isNotBlank() -> result.error
                else -> "未知错误"
            }
            return BasePackageProbeResult(
                errorMessage = "基础 Agent CLI 包检查失败：$details"
            )
        }

        val outputLines = sanitizeTerminalNoise(result.output)
            .lineSequence()
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .toList()
        val missingLine = outputLines.lastOrNull { line ->
            line.startsWith(BASE_PACKAGE_MISSING_MARKER)
        }
        if (missingLine != null) {
            val missing = missingLine
                .removePrefix(BASE_PACKAGE_MISSING_MARKER)
                .trim()
                .split(Regex("""\s+"""))
                .map { it.trim() }
                .filter { it.isNotBlank() }
                .distinct()
            return BasePackageProbeResult(missingCommands = missing)
        }
        if (outputLines.any { line -> line == BASE_PACKAGE_READY_MARKER }) {
            return BasePackageProbeResult(missingCommands = emptyList())
        }
        return BasePackageProbeResult(
            errorMessage = "基础 Agent CLI 包检查失败：探测结果无法解析。"
        )
    }

    private fun buildBasePackageProbeCommand(): String {
        val commands = requiredCliCommands.joinToString(" ")
        return """
            export PATH="${'$'}HOME/.local/bin:${'$'}PATH"
            missing=""
            for cmd in $commands; do
              if ! command -v "${'$'}cmd" >/dev/null 2>&1; then
                missing="${'$'}missing ${'$'}cmd"
              fi
            done
            if [ -n "${'$'}missing" ]; then
              echo "$BASE_PACKAGE_MISSING_MARKER ${'$'}{missing# }"
            else
              echo "$BASE_PACKAGE_READY_MARKER"
            fi
        """.trimIndent()
    }

    private fun buildInstallFailureMessage(result: HiddenExecResult): String {
        val output = sanitizeTerminalNoise(result.output).takeLast(1200).trim()
        val details = when {
            output.isNotBlank() -> output
            result.rawOutputPreview.isNotBlank() -> result.rawOutputPreview.takeLast(1200)
            result.error.isNotBlank() -> result.error
            else -> "未知错误"
        }
        return "内嵌 Ubuntu 终端已初始化，但基础 Agent CLI 包安装失败：$details"
    }

    private fun buildMissingBasePackageFailureMessage(missingCommands: List<String>): String {
        if (missingCommands.isEmpty()) {
            return "内嵌 Ubuntu 终端已初始化，但基础 Agent CLI 包安装后仍未通过校验。"
        }
        return "内嵌 Ubuntu 终端已初始化，但基础 Agent CLI 包仍缺失：${missingCommands.joinToString(", ")}"
    }

    private fun shouldSuppressTerminalLine(line: String): Boolean {
        val normalized = ansiEscapeRegex.replace(line, "").trim()
        if (normalized.isEmpty()) {
            return false
        }
        return knownNoiseRegexes.any { regex -> regex.matches(normalized) }
    }

    fun sanitizeTerminalNoise(text: String): String {
        if (text.isBlank()) {
            return text
        }
        val filtered = text.lineSequence()
            .filterNot { line -> shouldSuppressTerminalLine(line) }
            .joinToString("\n")
            .replace(Regex("\n{3,}"), "\n\n")
        return filtered.trim('\n')
    }

    fun trimTerminalOutput(
        text: String,
        maxLines: Int = 600,
        maxChars: Int = 64 * 1024
    ): String {
        if (text.isEmpty()) {
            return text
        }

        var candidate = if (text.length > maxChars) text.takeLast(maxChars) else text
        val lines = candidate.split('\n')
        if (lines.size > maxLines) {
            candidate = lines.takeLast(maxLines).joinToString("\n")
        }

        val wasTrimmed = candidate.length < text.length || lines.size > maxLines
        if (!wasTrimmed) {
            return candidate
        }

        val notice = "[更早输出已省略]\n"
        val body = candidate.removePrefix(notice)
        val remaining = (maxChars - notice.length).coerceAtLeast(0)
        return notice + body.takeLast(remaining)
    }

    private suspend fun emitEnvironmentProgress(
        onProgress: suspend (EnvironmentProgress) -> Unit,
        progress: EnvironmentProgress
    ) {
        try {
            onProgress(progress)
        } catch (_: Exception) {
        }
    }

    private data class ParsedSessionCommandOutput(
        val output: String,
        val exitCode: Int?
    )
}
