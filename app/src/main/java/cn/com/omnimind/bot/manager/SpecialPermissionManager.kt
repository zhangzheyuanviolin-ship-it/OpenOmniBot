package cn.com.omnimind.bot.manager

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import cn.com.omnimind.baselib.permission.PermissionRequest
import cn.com.omnimind.baselib.util.OmniLog
import cn.com.omnimind.bot.agent.AgentWorkspaceManager
import cn.com.omnimind.bot.terminal.EmbeddedTerminalAutoStartManager
import cn.com.omnimind.bot.terminal.EmbeddedTerminalLaunchHelper
import cn.com.omnimind.bot.terminal.EmbeddedTerminalRuntime
import cn.com.omnimind.bot.terminal.EmbeddedTerminalSetupManager
import cn.com.omnimind.bot.termux.TermuxCommandRunner
import cn.com.omnimind.bot.util.AssistsUtil
import cn.com.omnimind.bot.workspace.WorkspaceStorageAccess
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class SpecialPermissionManager(private val context: Context) {

    companion object {
        private const val TAG = "[PlatformManager]"
        private const val MAX_INIT_LOG_LINES = 160
        private val BASE_PACKAGE_NAMES = listOf(
            "bash",
            "ca-certificates",
            "curl",
            "git",
            "gcompat",
            "glib",
            "nodejs",
            "npm",
            "python3",
            "py3-pip",
            "py3-virtualenv",
            "ripgrep",
            "tmux",
            "xz"
        )
    }

    private data class EmbeddedTerminalInitState(
        val running: Boolean = false,
        val completed: Boolean = false,
        val success: Boolean? = null,
        val progress: Double = 0.0,
        val stage: String = "",
        val logLines: List<String> = emptyList(),
        val startedAt: Long = 0L,
        val updatedAt: Long = 0L,
        val completedAt: Long? = null,
        val seenBasePackages: Set<String> = emptySet()
    )

    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val embeddedTerminalInitLock = Any()
    private var embeddedTerminalInitState = EmbeddedTerminalInitState()
    private val embeddedTerminalSetupManager = EmbeddedTerminalSetupManager(context)
    private val embeddedTerminalAutoStartManager = EmbeddedTerminalAutoStartManager(context)
    var onEmbeddedTerminalInitProgress: ((Map<String, Any?>) -> Unit)? = null

    fun isAccessibilityServiceEnabled(result: MethodChannel.Result) {
        try {
            val isEnabled = AssistsUtil.Core.isAccessibilityServiceEnabled()
            result.success(isEnabled)
        } catch (e: Exception) {
            OmniLog.e(TAG, "Error checking accessibility service", e)
            result.error("CHECK_FAILED", "Failed to check accessibility service.", e.message)
        }
    }

    fun isIgnoringBatteryOptimizations(result: MethodChannel.Result) {
        try {
            val value = AssistsUtil.Setting.isIgnoringBatteryOptimizations(context);
            result.success(value)
        } catch (e: Exception) {
            OmniLog.e(TAG, "Error checking battery optimization", e)
            result.error("CHECK_FAILED", "Failed to check battery optimization.", e.message)
        }
    }

    fun openBatteryOptimizationSettings(result: MethodChannel.Result) {
        try {
            AssistsUtil.Setting.openBatteryOptimizationSettings(context)
            OmniLog.v(TAG, "Requesting to ignore battery optimizations.")
            result.success(null)

        } catch (e: Exception) {
            OmniLog.e(TAG, "请求忽略电池优化时发生异常，可能没有 Activity 能处理此 Intent。", e)
            result.error(
                "INTENT_FAILED",
                "无法打开电池优化设置页面，可能没有 Activity 能处理此 Intent。",
                e.message
            )
        }

    }

    fun openAccessibilitySettings(result: MethodChannel.Result) {
        try {
            AssistsUtil.Setting.openAccessibilitySettings(context);
            OmniLog.v(TAG, "Opening accessibility settings.")
            result.success(null)

        } catch (e: Exception) {
            OmniLog.e(TAG, "请求打开辅助功能设置时发生异常，可能没有 Activity 能处理此 Intent。", e)
            result.error(
                "INTENT_FAILED",
                "无法打开辅助功能设置页面，可能没有 Activity 能处理此 Intent。",
                e.message
            )
        }
    }

    fun isOverlayPermission(result: MethodChannel.Result) {
        try {
            val value = AssistsUtil.Setting.isOverlayPermission(context);
            result.success(value)
        } catch (e: Exception) {
            OmniLog.e(TAG, "Error checking battery optimization", e)
            result.error("CHECK_FAILED", "Failed to overlay permission.", e.message)
        }
    }

    fun openOverlaySettings(result: MethodChannel.Result) {
        try {
            AssistsUtil.Setting.openOverlaySettings(context);
            result.success(null)
            OmniLog.v(TAG, "Opening overlay settings.")
        } catch (e: Exception) {
            OmniLog.e(TAG, "请求打开悬浮窗设置时发生异常，可能没有 Activity 能处理此 Intent。", e)
            result.error(
                "INTENT_FAILED",
                "无法打开打开悬浮窗设置页面，可能没有 Activity 能处理此 Intent。",
                e.message
            )
        }

    }

    fun isInstalledAppsPermissionGranted(result: MethodChannel.Result) {
        try {
            val value = AssistsUtil.Setting.isInstalledAppsPermissionGranted(context)
            result.success(value)
        } catch (e: Exception) {
            OmniLog.e(TAG, "Error checking installed apps permission", e)
            result.error("CHECK_FAILED", "Failed to check installed apps permission.", e.message)
        }
    }

    fun openInstalledAppsSettings(result: MethodChannel.Result) {
        try {
            AssistsUtil.Setting.openInstalledAppsSettings(context)
            result.success(null)
            OmniLog.v(TAG, "Opening installed apps settings.")
        } catch (e: Exception) {
            OmniLog.e(
                TAG,
                "请求打开已安装应用列表权限设置时发生异常，可能没有 Activity 能处理此 Intent。",
                e
            )
            result.error(
                "INTENT_FAILED",
                "无法打开已安装应用列表权限设置页面，可能没有 Activity 能处理此 Intent。",
                e.message
            )
        }
    }

    fun openAutoStartSettings(result: MethodChannel.Result) {
        try {
            AssistsUtil.Setting.openAutoStartSettings(context)
            result.success(null)
            OmniLog.v(TAG, "Opening auto start settings.")
        } catch (e: Exception) {
            OmniLog.e(
                TAG,
                "请求打开应用启动管理设置时发生异常，可能没有 Activity 能处理此 Intent。",
                e
            )
            result.error(
                "INTENT_FAILED",
                "无法打开应用启动管理设置页面，可能没有 Activity 能处理此 Intent。",
                e.message
            )
        }
    }

    fun isTermuxInstalled(result: MethodChannel.Result) {
        try {
            result.success(EmbeddedTerminalRuntime.isSupportedDevice())
        } catch (e: Exception) {
            OmniLog.e(TAG, "Error checking embedded terminal availability", e)
            result.error("CHECK_FAILED", "Failed to check embedded terminal availability.", e.message)
        }
    }

    fun openTermuxApp(result: MethodChannel.Result) {
        try {
            if (!EmbeddedTerminalRuntime.isSupportedDevice()) {
                result.success(false)
                return
            }
            EmbeddedTerminalLaunchHelper.launch(context = context)
            result.success(true)
        } catch (e: Exception) {
            OmniLog.e(TAG, "请求打开内嵌终端时发生异常。", e)
            result.error(
                "INTENT_FAILED",
                "无法打开内嵌终端。",
                e.message
            )
        }
    }

    fun isTermuxRunCommandPermissionGranted(result: MethodChannel.Result) {
        try {
            result.success(EmbeddedTerminalRuntime.isSupportedDevice())
        } catch (e: Exception) {
            OmniLog.e(TAG, "Error checking embedded terminal status", e)
            result.error(
                "CHECK_FAILED",
                "Failed to check embedded terminal status.",
                e.message
            )
        }
    }

    fun requestTermuxRunCommandPermission(result: MethodChannel.Result) {
        try {
            result.success(EmbeddedTerminalRuntime.isSupportedDevice())
        } catch (e: Exception) {
            OmniLog.e(TAG, "Error preparing embedded terminal", e)
            result.error(
                "REQUEST_FAILED",
                "Failed to prepare embedded terminal.",
                e.message
            )
        }
    }

    fun openAppDetailsSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            OmniLog.e(TAG, "请求打开应用详情页时发生异常。", e)
            result.error(
                "INTENT_FAILED",
                "无法打开应用详情页，可能没有 Activity 能处理此 Intent。",
                e.message
            )
        }
    }

    fun isNotificationPermissionGranted(result: MethodChannel.Result) {
        try {
            val granted = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                true
            } else {
                ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.POST_NOTIFICATIONS
                ) == PackageManager.PERMISSION_GRANTED
            }
            result.success(granted)
        } catch (e: Exception) {
            OmniLog.e(TAG, "Error checking notification permission", e)
            result.error(
                "CHECK_FAILED",
                "Failed to check notification permission.",
                e.message
            )
        }
    }

    fun requestNotificationPermission(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                result.success(true)
                return
            }
            CoroutineScope(Dispatchers.Default).launch {
                AssistsUtil.UI.closeChatBotDialog()
            }
            PermissionRequest.requestPermissions(
                context,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS)
            ) {
                result.success(it[Manifest.permission.POST_NOTIFICATIONS] == true)
            }
        } catch (e: Exception) {
            OmniLog.e(TAG, "Error requesting notification permission", e)
            result.error(
                "REQUEST_FAILED",
                "Failed to request notification permission.",
                e.message
            )
        }
    }

    fun isWorkspaceStorageAccessGranted(result: MethodChannel.Result) {
        try {
            result.success(WorkspaceStorageAccess.isGranted(context))
        } catch (e: Exception) {
            OmniLog.e(TAG, "Error checking workspace storage access", e)
            result.error(
                "CHECK_FAILED",
                "Failed to check workspace storage access.",
                e.message
            )
        }
    }

    fun openWorkspaceStorageSettings(result: MethodChannel.Result) {
        try {
            val primaryIntent = WorkspaceStorageAccess.buildSettingsIntent(context)
            runCatching {
                context.startActivity(primaryIntent)
            }.recoverCatching {
                context.startActivity(WorkspaceStorageAccess.buildFallbackSettingsIntent())
            }.getOrThrow()
            result.success(true)
        } catch (e: Exception) {
            OmniLog.e(TAG, "请求打开公共 workspace 存储设置页时发生异常。", e)
            result.error(
                "INTENT_FAILED",
                "无法打开公共 workspace 存储设置页，可能没有 Activity 能处理此 Intent。",
                e.message
            )
        }
    }

    fun getWorkspacePathSnapshot(result: MethodChannel.Result) {
        try {
            result.success(AgentWorkspaceManager.workspacePathSnapshot(context))
        } catch (e: Exception) {
            OmniLog.e(TAG, "Error getting workspace path snapshot", e)
            result.error(
                "WORKSPACE_PATH_SNAPSHOT_FAILED",
                "Failed to get workspace path snapshot.",
                e.message
            )
        }
    }

    fun getEmbeddedTerminalRuntimeStatus(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val readiness = EmbeddedTerminalRuntime.inspectRuntimeReadiness(context)
                val workspaceGranted = WorkspaceStorageAccess.isGranted(context)
                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "supported" to readiness.supported,
                            "runtimeReady" to readiness.runtimeReady,
                            "basePackagesReady" to readiness.basePackagesReady,
                            "allReady" to (readiness.supported && readiness.runtimeReady && readiness.basePackagesReady),
                            "missingCommands" to readiness.missingCommands,
                            "message" to readiness.message,
                            "nodeReady" to readiness.nodeReady,
                            "nodeVersion" to readiness.nodeVersion,
                            "nodeMinMajor" to readiness.nodeMinMajor,
                            "pnpmReady" to readiness.pnpmReady,
                            "pnpmVersion" to readiness.pnpmVersion,
                            "workspaceAccessGranted" to workspaceGranted
                        )
                    )
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "Error checking embedded terminal runtime status", e)
                withContext(Dispatchers.Main) {
                    result.error(
                        "CHECK_FAILED",
                        "Failed to check embedded terminal runtime status.",
                        e.message
                    )
                }
            }
        }
    }

    fun getEmbeddedTerminalSetupStatus(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val packageStatus = embeddedTerminalSetupManager.getPackageInstallStatus()
                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "packages" to packageStatus
                        )
                    )
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "Error reading embedded terminal setup status", e)
                withContext(Dispatchers.Main) {
                    result.error(
                        "READ_SETUP_STATUS_FAILED",
                        "Failed to read embedded terminal setup status.",
                        e.message
                    )
                }
            }
        }
    }

    fun getEmbeddedTerminalSetupInventory(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val packageInventory = embeddedTerminalSetupManager.getPackageInventory()
                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "packages" to packageInventory.mapValues { it.value.toMap() }
                        )
                    )
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "Error reading embedded terminal setup inventory", e)
                withContext(Dispatchers.Main) {
                    result.error(
                        "READ_SETUP_INVENTORY_FAILED",
                        "Failed to read embedded terminal setup inventory.",
                        e.message
                    )
                }
            }
        }
    }

    fun installEmbeddedTerminalPackages(call: MethodCall, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val packageIds = call.argument<List<String>>("packageIds").orEmpty()
                val installResult = embeddedTerminalSetupManager.installPackages(packageIds)
                withContext(Dispatchers.Main) {
                    result.success(installResult.toMap())
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "Error installing embedded terminal packages", e)
                withContext(Dispatchers.Main) {
                    result.error(
                        "INSTALL_SETUP_PACKAGES_FAILED",
                        "Failed to install embedded terminal packages.",
                        e.message
                    )
                }
            }
        }
    }

    fun getEmbeddedTerminalSetupSessionSnapshot(result: MethodChannel.Result) {
        try {
            result.success(embeddedTerminalSetupManager.getInstallSessionSnapshot().toMap())
        } catch (e: Exception) {
            OmniLog.e(TAG, "Error reading embedded terminal setup session snapshot", e)
            result.error(
                "READ_SETUP_SESSION_FAILED",
                "Failed to read embedded terminal setup session snapshot.",
                e.message
            )
        }
    }

    fun startEmbeddedTerminalSetupSession(call: MethodCall, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val packageIds = call.argument<List<String>>("packageIds").orEmpty()
                val snapshot = embeddedTerminalSetupManager.startInstallSession(packageIds)
                withContext(Dispatchers.Main) {
                    result.success(snapshot.toMap())
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "Error starting embedded terminal setup session", e)
                withContext(Dispatchers.Main) {
                    result.error(
                        "START_SETUP_SESSION_FAILED",
                        "Failed to start embedded terminal setup session.",
                        e.message
                    )
                }
            }
        }
    }

    fun dismissEmbeddedTerminalSetupSession(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                embeddedTerminalSetupManager.dismissInstallSession()
                withContext(Dispatchers.Main) {
                    result.success(null)
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "Error dismissing embedded terminal setup session", e)
                withContext(Dispatchers.Main) {
                    result.error(
                        "DISMISS_SETUP_SESSION_FAILED",
                        "Failed to dismiss embedded terminal setup session.",
                        e.message
                    )
                }
            }
        }
    }

    fun getEmbeddedTerminalAutoStartTasks(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val tasks = embeddedTerminalAutoStartManager.listTasks()
                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "tasks" to tasks.map { it.toMap() }
                        )
                    )
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "Error reading embedded terminal auto-start tasks", e)
                withContext(Dispatchers.Main) {
                    result.error(
                        "READ_AUTO_START_TASKS_FAILED",
                        "Failed to read embedded terminal auto-start tasks.",
                        e.message
                    )
                }
            }
        }
    }

    fun saveEmbeddedTerminalAutoStartTask(call: MethodCall, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val snapshot = embeddedTerminalAutoStartManager.saveTask(
                    id = call.argument<String>("id"),
                    name = call.argument<String>("name").orEmpty(),
                    command = call.argument<String>("command").orEmpty(),
                    workingDirectory = call.argument<String>("workingDirectory"),
                    enabled = call.argument<Boolean>("enabled") != false
                )
                withContext(Dispatchers.Main) {
                    result.success(snapshot.toMap())
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "Error saving embedded terminal auto-start task", e)
                withContext(Dispatchers.Main) {
                    result.error(
                        "SAVE_AUTO_START_TASK_FAILED",
                        "Failed to save embedded terminal auto-start task.",
                        e.message
                    )
                }
            }
        }
    }

    fun deleteEmbeddedTerminalAutoStartTask(call: MethodCall, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                embeddedTerminalAutoStartManager.deleteTask(
                    taskId = call.argument<String>("id").orEmpty()
                )
                withContext(Dispatchers.Main) {
                    result.success(null)
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "Error deleting embedded terminal auto-start task", e)
                withContext(Dispatchers.Main) {
                    result.error(
                        "DELETE_AUTO_START_TASK_FAILED",
                        "Failed to delete embedded terminal auto-start task.",
                        e.message
                    )
                }
            }
        }
    }

    fun runEmbeddedTerminalAutoStartTask(call: MethodCall, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val runResult = embeddedTerminalAutoStartManager.runTaskNow(
                    taskId = call.argument<String>("id").orEmpty()
                )
                withContext(Dispatchers.Main) {
                    result.success(runResult.toMap())
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "Error running embedded terminal auto-start task", e)
                withContext(Dispatchers.Main) {
                    result.error(
                        "RUN_AUTO_START_TASK_FAILED",
                        "Failed to run embedded terminal auto-start task.",
                        e.message
                    )
                }
            }
        }
    }

    fun openNativeTerminal(call: MethodCall, result: MethodChannel.Result) {
        try {
            val openSetup = call.argument<Boolean>("openSetup") == true
            val setupPackageIds = call.argument<List<String>>("setupPackageIds")
                .orEmpty()
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .distinct()
            EmbeddedTerminalLaunchHelper.launch(
                context = context,
                openSetup = openSetup,
                setupPackageIds = setupPackageIds
            )
            result.success(true)
        } catch (e: Exception) {
            OmniLog.e(TAG, "Error opening native terminal", e)
            result.error(
                "OPEN_NATIVE_TERMINAL_FAILED",
                "Failed to open native terminal.",
                e.message
            )
        }
    }

    fun prepareTermuxLiveWrapper(result: MethodChannel.Result) {
        resetEmbeddedTerminalInitState()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                emitEmbeddedTerminalInitProgress("status", "开始准备内嵌 Alpine 终端环境")
                val status =
                    TermuxCommandRunner.prepareLiveEnvironment(context) { progress ->
                        emitEmbeddedTerminalInitProgress(
                            kind = progress.kind.name.lowercase(),
                            message = progress.message
                        )
                    }
                emitEmbeddedTerminalInitProgress(
                    kind = if (status.success) "status" else "error",
                    message = status.message
                )
                markEmbeddedTerminalInitCompleted(status.success, status.message)
                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "success" to status.success,
                            "wrapperReady" to status.wrapperReady,
                            "sharedStorageReady" to status.sharedStorageReady,
                            "message" to status.message
                        )
                    )
                }
            } catch (e: Exception) {
                OmniLog.e(TAG, "Error preparing embedded terminal runtime", e)
                emitEmbeddedTerminalInitProgress(
                    kind = "error",
                    message = e.message ?: "检查内嵌终端环境失败"
                )
                markEmbeddedTerminalInitCompleted(
                    success = false,
                    finalMessage = e.message ?: "检查内嵌终端环境失败"
                )
                withContext(Dispatchers.Main) {
                    result.error(
                        "PREPARE_FAILED",
                        "Failed to prepare embedded terminal runtime.",
                        e.message
                    )
                }
            }
        }
    }

    fun getEmbeddedTerminalInitSnapshot(result: MethodChannel.Result) {
        try {
            result.success(buildEmbeddedTerminalInitSnapshot())
        } catch (e: Exception) {
            OmniLog.e(TAG, "Error reading embedded terminal init snapshot", e)
            result.error(
                "READ_FAILED",
                "Failed to read embedded terminal init snapshot.",
                e.message
            )
        }
    }

    private fun emitEmbeddedTerminalInitProgress(
        kind: String,
        message: String
    ) {
        if (message.isBlank()) {
            return
        }
        updateEmbeddedTerminalInitState(kind, message)
        val callback = onEmbeddedTerminalInitProgress ?: return
        mainScope.launch {
            callback(
                mapOf(
                    "kind" to kind,
                    "message" to message,
                    "timestamp" to System.currentTimeMillis()
                )
            )
        }
    }

    private fun resetEmbeddedTerminalInitState() {
        val now = System.currentTimeMillis()
        synchronized(embeddedTerminalInitLock) {
            embeddedTerminalInitState = EmbeddedTerminalInitState(
                running = true,
                completed = false,
                success = null,
                progress = 0.02,
                stage = "准备开始",
                logLines = listOf("[系统] 正在启动内嵌 Alpine 环境初始化..."),
                startedAt = now,
                updatedAt = now
            )
        }
    }

    private fun updateEmbeddedTerminalInitState(
        kind: String,
        message: String
    ) {
        val normalizedMessage = message.trim()
        if (normalizedMessage.isBlank()) {
            return
        }

        val normalizedLines = normalizeEmbeddedTerminalInitLines(normalizedMessage)
        if (normalizedLines.isEmpty()) {
            return
        }

        synchronized(embeddedTerminalInitLock) {
            val now = System.currentTimeMillis()
            val current =
                if (embeddedTerminalInitState.startedAt == 0L) {
                    EmbeddedTerminalInitState(
                        running = true,
                        startedAt = now,
                        updatedAt = now
                    )
                } else {
                    embeddedTerminalInitState
                }

            val nextSeenBasePackages =
                if (kind == "output") {
                    current.seenBasePackages + extractSeenBasePackages(normalizedLines)
                } else {
                    current.seenBasePackages
                }

            val derivedProgress = deriveEmbeddedTerminalInitProgress(
                kind = kind,
                message = normalizedMessage,
                seenBasePackages = nextSeenBasePackages,
                currentProgress = current.progress
            )

            embeddedTerminalInitState = current.copy(
                running = true,
                completed = false,
                success = null,
                progress = maxOf(current.progress, derivedProgress).coerceAtMost(0.99),
                stage = if (kind == "output") current.stage else normalizedMessage,
                logLines = mergeEmbeddedTerminalInitLogLines(
                    current.logLines,
                    formatEmbeddedTerminalInitLogLines(kind, normalizedLines)
                ),
                updatedAt = now,
                seenBasePackages = nextSeenBasePackages
            )
        }
    }

    private fun markEmbeddedTerminalInitCompleted(
        success: Boolean,
        finalMessage: String
    ) {
        val normalizedMessage = finalMessage.trim().ifBlank {
            if (success) {
                "内嵌 Alpine 终端和基础 Agent CLI 包均已就绪。"
            } else {
                "检查内嵌终端环境失败"
            }
        }
        synchronized(embeddedTerminalInitLock) {
            val now = System.currentTimeMillis()
            val current = embeddedTerminalInitState
            embeddedTerminalInitState = current.copy(
                running = false,
                completed = true,
                success = success,
                progress = if (success) 1.0 else current.progress.coerceAtLeast(0.02),
                stage = normalizedMessage,
                updatedAt = now,
                completedAt = now
            )
        }
    }

    private fun buildEmbeddedTerminalInitSnapshot(): Map<String, Any?> {
        val snapshot =
            synchronized(embeddedTerminalInitLock) {
                embeddedTerminalInitState
            }
        return mapOf(
            "running" to snapshot.running,
            "completed" to snapshot.completed,
            "success" to snapshot.success,
            "progress" to snapshot.progress,
            "stage" to snapshot.stage,
            "logLines" to snapshot.logLines,
            "startedAt" to snapshot.startedAt.takeIf { it > 0L },
            "updatedAt" to snapshot.updatedAt.takeIf { it > 0L },
            "completedAt" to snapshot.completedAt
        )
    }

    private fun normalizeEmbeddedTerminalInitLines(message: String): List<String> {
        return message
            .replace("\r\n", "\n")
            .replace('\r', '\n')
            .split('\n')
            .map { it.trimEnd() }
            .filter { it.isNotBlank() }
    }

    private fun formatEmbeddedTerminalInitLogLines(
        kind: String,
        lines: List<String>
    ): List<String> {
        val prefix =
            when (kind) {
                "error" -> "[错误] "
                "output" -> ""
                else -> "[阶段] "
            }
        return lines.map { line -> "$prefix$line" }
    }

    private fun mergeEmbeddedTerminalInitLogLines(
        currentLines: List<String>,
        appendedLines: List<String>
    ): List<String> {
        if (appendedLines.isEmpty()) {
            return currentLines
        }
        val merged = currentLines + appendedLines
        return if (merged.size > MAX_INIT_LOG_LINES) {
            merged.takeLast(MAX_INIT_LOG_LINES)
        } else {
            merged
        }
    }

    private fun extractSeenBasePackages(lines: List<String>): Set<String> {
        val lowerCaseLines = lines.map { it.lowercase() }
        return BASE_PACKAGE_NAMES.filter { packageName ->
            val lowerPackageName = packageName.lowercase()
            lowerCaseLines.any { line ->
                line.contains(lowerPackageName) &&
                    (
                        line.contains("fetch ") ||
                            line.contains("installing ") ||
                            line.contains("upgrading ") ||
                            line.contains("get:") ||
                            line.contains("selecting previously") ||
                            line.contains("unpacking") ||
                            line.contains("setting up") ||
                            line.contains("preparing to unpack")
                        )
            }
        }.toSet()
    }

    private fun deriveEmbeddedTerminalInitProgress(
        kind: String,
        message: String,
        seenBasePackages: Set<String>,
        currentProgress: Double
    ): Double {
        val normalizedMessage = message.trim()
        val stageProgress =
            when {
                normalizedMessage.contains("开始准备内嵌 Alpine 终端环境") -> 0.04
                normalizedMessage.contains("正在准备 workspace 和运行目录") -> 0.10
                normalizedMessage.contains("正在初始化宿主终端运行时") -> 0.14
                normalizedMessage.contains("正在校验 Alpine 终端运行资源") -> 0.24
                normalizedMessage.contains("正在安装 Alpine 终端运行资源") -> 0.42
                normalizedMessage.contains("宿主终端环境校验完成") -> 0.60
                normalizedMessage.contains("正在检查基础 Agent CLI 包") -> 0.68
                normalizedMessage.contains("基础 Agent CLI 包已就绪") -> 0.96
                normalizedMessage.contains("正在安装基础 Agent CLI 包") -> 0.72
                normalizedMessage.contains("基础 Agent CLI 包安装完成") -> 0.98
                normalizedMessage.contains("均已就绪") -> 1.0
                else -> null
            }
        if (stageProgress != null) {
            return stageProgress
        }

        if (kind != "output") {
            return currentProgress
        }

        if (normalizedMessage.contains("fetch ", ignoreCase = true)) {
            return 0.74
        }
        if (normalizedMessage.contains("installing ", ignoreCase = true)) {
            return 0.76
        }
        if (normalizedMessage.contains("upgrading ", ignoreCase = true) ||
            normalizedMessage.contains("executing busybox", ignoreCase = true)
        ) {
            return 0.78
        }
        if (normalizedMessage.contains("npm install -g pnpm", ignoreCase = true) ||
            normalizedMessage.contains("python3 -m pip install", ignoreCase = true)
        ) {
            return 0.80
        }
        if (normalizedMessage.contains("Fetched ")) {
            return 0.84
        }
        if (seenBasePackages.isNotEmpty()) {
            val installProgress = seenBasePackages.size.toDouble() / BASE_PACKAGE_NAMES.size.toDouble()
            return 0.82 + installProgress * 0.14
        }

        return currentProgress
    }

    fun isUnknownAppInstallAllowed(result: MethodChannel.Result) {
        try {
            result.success(ExternalApkInstaller.canInstallPackages(context))
        } catch (e: Exception) {
            OmniLog.e(TAG, "Error checking unknown app install permission", e)
            result.error(
                "CHECK_FAILED",
                "Failed to check unknown app install permission.",
                e.message
            )
        }
    }

    fun openUnknownAppInstallSettings(result: MethodChannel.Result) {
        try {
            ExternalApkInstaller.openInstallPermissionSettings(context)
            result.success(true)
        } catch (e: Exception) {
            OmniLog.e(TAG, "请求打开未知应用安装设置页时发生异常。", e)
            result.error(
                "INTENT_FAILED",
                "无法打开未知应用安装设置页，可能没有 Activity 能处理此 Intent。",
                e.message
            )
        }
    }

    fun downloadAndInstallTermuxApk(call: MethodCall, result: MethodChannel.Result) {
        result.success(
            mapOf(
                "success" to true,
                "status" to "not_needed",
                "message" to "终端能力已内置到应用中，无需下载安装独立 Termux。",
                "filePath" to null
            )
        )
    }

    fun requestPermissions(call: MethodCall, result: MethodChannel.Result) {
        try {
            val permissions = call.argument<List<String>>("permissions")
            if (permissions == null||permissions.isEmpty()) {
                result.error("INVALID_ARGUMENT", "Invalid argument: permissions is null.", null)
                return
            }
            val mPermissions = ArrayList<String>();
            mPermissions.addAll(permissions)
            //要权限优先关闭 关闭聊天对话框
            CoroutineScope(Dispatchers.Default).launch {
                AssistsUtil.UI.closeChatBotDialog()
            }
            PermissionRequest.requestPermissions(context, mPermissions.toTypedArray()) {
                val isGranted = it.all { it.value }
                result.success(if (isGranted) "Success" else "Failed")
            }
        } catch (e: Exception) {
            OmniLog.e(TAG, "Error requesting permissions", e)
            result.error("request_Permissions_FAILED", "Failed to request permissions.", e.message)
        }
    }
}
