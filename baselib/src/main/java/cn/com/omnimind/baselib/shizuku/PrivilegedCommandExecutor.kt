package cn.com.omnimind.baselib.shizuku

import android.os.Process
import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

internal object PrivilegedCommandExecutor {

    private const val OUTPUT_LIMIT = 16_000
    private const val COMMAND_TIMEOUT_SECONDS = 8L

    private val allowedSettingsNamespaces = setOf("system", "secure", "global")
    private val allowedDumpsysServices = setOf(
        "activity",
        "alarm",
        "battery",
        "connectivity",
        "deviceidle",
        "input",
        "input_method",
        "notification",
        "package",
        "power",
        "usagestats",
        "wifi",
        "window"
    )
    private val allowedLogcatBuffers = setOf("main", "system", "crash", "events", "radio", "kernel")
    private val allowedAppOpsModes = setOf("allow", "ignore", "deny", "default", "foreground")

    fun currentBackend(): ShizukuBackend {
        return if (Process.myUid() == 0) ShizukuBackend.ROOT else ShizukuBackend.ADB
    }

    fun execute(request: PrivilegedRequest): PrivilegedResult {
        val backend = currentBackend()
        val action = PrivilegedActionPolicy.normalizeAction(request.action)
        val arguments = request.arguments

        if (!PrivilegedActionPolicy.isSupported(action, backend, includeInternal = true, arguments = arguments)) {
            return failure(
                request = request,
                backend = backend,
                code = "unsupported_action",
                message = "Action is not available for the current Shizuku backend."
            )
        }

        if ((request.requiresConfirmation || PrivilegedActionPolicy.requiresConfirmation(action)) &&
            !isExplicitlyConfirmed(arguments)
        ) {
            return failure(
                request = request,
                backend = backend,
                code = "confirmation_required",
                message = "This privileged action requires explicit confirmation.",
                requiresConfirmation = true
            )
        }

        val command = runCatching {
            buildCommand(action, arguments, backend)
        }.getOrElse { error ->
            return failure(
                request = request,
                backend = backend,
                code = "invalid_arguments",
                message = error.message ?: "Invalid privileged action arguments."
            )
        }

        val result = exec(command)
        val trimmedOutput = trimOutput(result.output)
        return if (result.success) {
            val data = when (action) {
                PrivilegedActionPolicy.ACTION_SETTINGS_GET -> mapOf("value" to trimmedOutput.trim())
                PrivilegedActionPolicy.ACTION_DIAGNOSTICS_GETPROP -> mapOf("value" to trimmedOutput.trim())
                PrivilegedActionPolicy.ACTION_DIAGNOSTICS_LIST_PACKAGES -> {
                    val filter = arguments["filter"]?.trim().orEmpty()
                    val packages = trimmedOutput
                        .lineSequence()
                        .map { it.removePrefix("package:").trim() }
                        .filter { it.isNotEmpty() }
                        .filter { filter.isBlank() || it.contains(filter, ignoreCase = true) }
                        .joinToString("\n")
                    mapOf("packages" to packages)
                }
                else -> emptyMap()
            }
            PrivilegedResult(
                requestId = request.requestId,
                action = action,
                success = true,
                code = "ok",
                message = "Privileged action executed successfully.",
                backend = backend,
                output = trimmedOutput,
                exitCode = result.exitCode,
                availableActions = PrivilegedActionPolicy.visibleAgentActions(backend),
                data = data
            )
        } else {
            failure(
                request = request,
                backend = backend,
                code = if (result.timedOut) "timeout" else "command_failed",
                message = if (result.timedOut) {
                    "Privileged action timed out."
                } else {
                    "Privileged action failed."
                },
                output = trimmedOutput,
                exitCode = result.exitCode
            )
        }
    }

    private fun buildCommand(
        action: String,
        arguments: Map<String, String>,
        backend: ShizukuBackend,
    ): List<String> {
        return when (action) {
            PrivilegedActionPolicy.ACTION_PACKAGE_LAUNCH -> {
                val packageName = requirePackageName(arguments["packageName"])
                val activityName = arguments["activityName"]?.trim().orEmpty()
                if (activityName.isNotEmpty()) {
                    requireSafeComponent(activityName)
                    listOf("am", "start", "-n", "$packageName/$activityName")
                } else {
                    listOf(
                        "monkey",
                        "-p",
                        packageName,
                        "-c",
                        "android.intent.category.LAUNCHER",
                        "1"
                    )
                }
            }
            PrivilegedActionPolicy.ACTION_PACKAGE_FORCE_STOP -> {
                listOf("am", "force-stop", requirePackageName(arguments["packageName"]))
            }
            PrivilegedActionPolicy.ACTION_PACKAGE_GRANT_PERMISSION -> {
                listOf(
                    "pm",
                    "grant",
                    requirePackageName(arguments["packageName"]),
                    requirePermissionName(arguments["permission"])
                )
            }
            PrivilegedActionPolicy.ACTION_PACKAGE_REVOKE_PERMISSION -> {
                listOf(
                    "pm",
                    "revoke",
                    requirePackageName(arguments["packageName"]),
                    requirePermissionName(arguments["permission"])
                )
            }
            PrivilegedActionPolicy.ACTION_PACKAGE_SET_APPOPS -> {
                val mode = arguments["mode"]?.trim()?.lowercase().orEmpty()
                require(allowedAppOpsModes.contains(mode)) { "Unsupported appops mode." }
                listOf(
                    "appops",
                    "set",
                    requirePackageName(arguments["packageName"]),
                    requireSimpleToken(arguments["op"], "op"),
                    mode
                )
            }
            PrivilegedActionPolicy.ACTION_SETTINGS_GET -> {
                listOf(
                    "settings",
                    "get",
                    requireSettingsNamespace(arguments["namespace"]),
                    requireSimpleToken(arguments["key"], "key")
                )
            }
            PrivilegedActionPolicy.ACTION_SETTINGS_PUT -> {
                listOf(
                    "settings",
                    "put",
                    requireSettingsNamespace(arguments["namespace"]),
                    requireSimpleToken(arguments["key"], "key"),
                    requireNotBlank(arguments["value"], "value")
                )
            }
            PrivilegedActionPolicy.ACTION_DEVICE_KEYEVENT -> {
                listOf("input", "keyevent", requireKeyEvent(arguments["key"]))
            }
            PrivilegedActionPolicy.ACTION_DEVICE_EXPAND_NOTIFICATIONS -> {
                listOf("cmd", "statusbar", "expand-notifications")
            }
            PrivilegedActionPolicy.ACTION_DEVICE_EXPAND_QUICK_SETTINGS -> {
                listOf("cmd", "statusbar", "expand-settings")
            }
            PrivilegedActionPolicy.ACTION_DEVICE_SET_WIFI_ENABLED -> {
                listOf("svc", "wifi", if (isEnabled(arguments)) "enable" else "disable")
            }
            PrivilegedActionPolicy.ACTION_DEVICE_SET_MOBILE_DATA_ENABLED -> {
                require(backend == ShizukuBackend.ROOT) { "Mobile data control requires root backend." }
                listOf("svc", "data", if (isEnabled(arguments)) "enable" else "disable")
            }
            PrivilegedActionPolicy.ACTION_DEVICE_INPUT_TEXT -> {
                listOf("input", "text", encodeInputText(requireNotBlank(arguments["text"], "text")))
            }
            PrivilegedActionPolicy.ACTION_DIAGNOSTICS_GETPROP -> {
                val name = arguments["name"]?.trim().orEmpty()
                if (name.isBlank()) {
                    listOf("getprop")
                } else {
                    listOf("getprop", requireSimpleToken(name, "name"))
                }
            }
            PrivilegedActionPolicy.ACTION_DIAGNOSTICS_DUMPSYS -> {
                val service = arguments["service"]?.trim()?.lowercase().orEmpty()
                require(allowedDumpsysServices.contains(service)) { "Unsupported dumpsys service." }
                listOf("dumpsys", service)
            }
            PrivilegedActionPolicy.ACTION_DIAGNOSTICS_LIST_PACKAGES -> {
                listOf("pm", "list", "packages")
            }
            PrivilegedActionPolicy.ACTION_DIAGNOSTICS_LOGCAT_TAIL -> {
                val buffer = arguments["buffer"]?.trim()?.lowercase()?.ifEmpty { "main" } ?: "main"
                require(allowedLogcatBuffers.contains(buffer)) { "Unsupported logcat buffer." }
                if (buffer == "kernel") {
                    require(backend == ShizukuBackend.ROOT) { "Kernel logcat requires root backend." }
                }
                val lines = arguments["lines"]?.trim()?.toIntOrNull()?.coerceIn(1, 200) ?: 80
                listOf("logcat", "-d", "-b", buffer, "-t", lines.toString())
            }
            else -> error("Unsupported action.")
        }
    }

    private fun exec(command: List<String>): ExecResult {
        val process = ProcessBuilder(command)
            .redirectErrorStream(true)
            .start()
        val outputBuffer = ByteArrayOutputStream()
        val readerThread = thread(start = true, isDaemon = true) {
            process.inputStream.use { input ->
                input.copyTo(outputBuffer)
            }
        }
        val finished = process.waitFor(COMMAND_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        if (!finished) {
            process.destroyForcibly()
            readerThread.join(500)
            return ExecResult(
                success = false,
                timedOut = true,
                exitCode = null,
                output = outputBuffer.toString()
            )
        }
        readerThread.join(500)
        return ExecResult(
            success = process.exitValue() == 0,
            timedOut = false,
            exitCode = process.exitValue(),
            output = outputBuffer.toString()
        )
    }

    private fun trimOutput(value: String): String {
        val normalized = value.trim()
        if (normalized.length <= OUTPUT_LIMIT) {
            return normalized
        }
        return normalized.take(OUTPUT_LIMIT)
    }

    private fun failure(
        request: PrivilegedRequest,
        backend: ShizukuBackend,
        code: String,
        message: String,
        output: String = "",
        exitCode: Int? = null,
        requiresConfirmation: Boolean = false,
    ): PrivilegedResult {
        return PrivilegedResult(
            requestId = request.requestId,
            action = request.action,
            success = false,
            code = code,
            message = message,
            backend = backend,
            output = output,
            exitCode = exitCode,
            requiresConfirmation = requiresConfirmation,
            availableActions = PrivilegedActionPolicy.visibleAgentActions(backend)
        )
    }

    private fun requirePackageName(value: String?): String {
        return requireNotBlank(value, "packageName").also {
            require(Regex("^[A-Za-z0-9._]+$").matches(it)) { "Invalid packageName." }
        }
    }

    private fun requirePermissionName(value: String?): String {
        return requireNotBlank(value, "permission").also {
            require(Regex("^[A-Za-z0-9._]+$").matches(it)) { "Invalid permission." }
        }
    }

    private fun requireSettingsNamespace(value: String?): String {
        val namespace = value?.trim()?.lowercase().orEmpty()
        require(allowedSettingsNamespaces.contains(namespace)) { "Unsupported namespace." }
        return namespace
    }

    private fun requireSimpleToken(value: String?, fieldName: String): String {
        return requireNotBlank(value, fieldName).also {
            require(Regex("^[A-Za-z0-9_./:-]+$").matches(it)) { "Invalid $fieldName." }
        }
    }

    private fun requireKeyEvent(value: String?): String {
        return requireNotBlank(value, "key").also {
            require(Regex("^[A-Za-z0-9_]+$").matches(it)) { "Invalid key event." }
        }
    }

    private fun requireSafeComponent(value: String) {
        require(Regex("^[A-Za-z0-9_.$]+$").matches(value)) { "Invalid activityName." }
    }

    private fun requireNotBlank(value: String?, fieldName: String): String {
        val trimmed = value?.trim().orEmpty()
        require(trimmed.isNotEmpty()) { "$fieldName is required." }
        return trimmed
    }

    private fun isEnabled(arguments: Map<String, String>): Boolean {
        return arguments["enabled"]?.trim()?.lowercase() in setOf("1", "true", "yes", "on", "enable", "enabled")
    }

    private fun isExplicitlyConfirmed(arguments: Map<String, String>): Boolean {
        return arguments["confirmed"]?.trim()?.lowercase() in setOf("1", "true", "yes", "confirm", "confirmed")
    }

    private fun encodeInputText(text: String): String {
        return text
            .replace("%", "%25")
            .replace(" ", "%s")
            .replace("\n", " ")
    }

    private data class ExecResult(
        val success: Boolean,
        val timedOut: Boolean,
        val exitCode: Int?,
        val output: String,
    )
}
