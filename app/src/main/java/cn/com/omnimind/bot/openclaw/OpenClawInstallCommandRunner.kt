package cn.com.omnimind.bot.openclaw

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

class OpenClawInstallCommandRunner(
    private val context: Context
) {
    data class Result(
        val success: Boolean,
        val timedOut: Boolean,
        val exitCode: Int?,
        val output: String,
        val errorMessage: String?
    )

    companion object {
        private const val FAKE_KERNEL_RELEASE = "6.17.0-PRoot-Distro"
        private const val FAKE_KERNEL_VERSION =
            "#1 SMP PREEMPT_DYNAMIC Fri, 10 Oct 2025 00:00:00 +0000"
    }

    suspend fun execute(
        command: String,
        timeoutSeconds: Int,
        onOutputChunk: (String) -> Unit = {}
    ): Result = withContext(Dispatchers.IO) {
        OpenClawRuntimeSupport.ensureRuntimeFiles(context)

        val builder = ProcessBuilder(
            OpenClawRuntimeSupport.resolveHostBashPath(context),
            "-c",
            buildHostScript(command)
        )
        builder.directory(context.filesDir)
        builder.redirectErrorStream(true)
        val environment = builder.environment()
        environment.clear()
        environment.putAll(OpenClawRuntimeSupport.buildHostEnvironment(context))

        val process = try {
            builder.start()
        } catch (error: Exception) {
            return@withContext Result(
                success = false,
                timedOut = false,
                exitCode = null,
                output = "",
                errorMessage = error.message ?: "Failed to start install process"
            )
        }

        val output = StringBuilder()
        val readerThread = thread(
            name = "openclaw-install-output",
            isDaemon = true
        ) {
            try {
                BufferedReader(InputStreamReader(process.inputStream)).use { reader ->
                    while (true) {
                        val line = reader.readLine() ?: break
                        if (line.contains("proot warning") || line.contains("can't sanitize")) {
                            continue
                        }
                        synchronized(output) {
                            output.appendLine(line)
                        }
                        runCatching { onOutputChunk(line + "\n") }
                    }
                }
            } catch (_: Exception) {
            }
        }

        val exited = process.waitFor(timeoutSeconds.toLong(), TimeUnit.SECONDS)
        if (!exited) {
            process.destroyForcibly()
            readerThread.join(2_000L)
            val captured = synchronized(output) { output.toString().trim() }
            return@withContext Result(
                success = false,
                timedOut = true,
                exitCode = null,
                output = captured,
                errorMessage = "Command timed out after ${timeoutSeconds}s"
            )
        }

        readerThread.join(2_000L)
        val exitCode = process.exitValue()
        val captured = synchronized(output) { output.toString().trim() }
        Result(
            success = exitCode == 0,
            timedOut = false,
            exitCode = exitCode,
            output = captured,
            errorMessage = if (exitCode == 0) null else "Command failed with exit code $exitCode"
        )
    }

    private fun buildHostScript(command: String): String {
        val rootfsDir = OpenClawRuntimeSupport.ubuntuRootfsDir(context)
        val rootfsPath = quoteShell(rootfsDir.absolutePath)
        val installedRootfsDir = quoteShell(rootfsDir.parentFile?.absolutePath ?: rootfsDir.absolutePath)
        val prootPath = quoteShell(java.io.File(context.filesDir, "usr/bin/proot").absolutePath)
        val resolvPath = quoteShell(java.io.File(rootfsDir, "etc/resolv.conf").absolutePath)
        val guestScriptName = "operit_openclaw_install_${UUID.randomUUID().toString().replace("-", "")}.sh"
        val guestScriptPath = quoteShell(java.io.File(rootfsDir, "tmp/$guestScriptName").absolutePath)
        val guestScriptGuestPath = quoteShell("/tmp/$guestScriptName")
        val fakeLoadavg = quoteShell(java.io.File(rootfsDir, "proc/.loadavg").absolutePath)
        val fakeStat = quoteShell(java.io.File(rootfsDir, "proc/.stat").absolutePath)
        val fakeUptime = quoteShell(java.io.File(rootfsDir, "proc/.uptime").absolutePath)
        val fakeVersion = quoteShell(java.io.File(rootfsDir, "proc/.version").absolutePath)
        val fakeVmstat = quoteShell(java.io.File(rootfsDir, "proc/.vmstat").absolutePath)
        val fakeCapLastCap = quoteShell(java.io.File(rootfsDir, "proc/.sysctl_entry_cap_last_cap").absolutePath)
        val fakeMaxUserWatches = quoteShell(java.io.File(rootfsDir, "proc/.sysctl_inotify_max_user_watches").absolutePath)
        val fakeFipsEnabled = quoteShell(java.io.File(rootfsDir, "proc/.sysctl_crypto_fips_enabled").absolutePath)
        val fakeSelinux = quoteShell(java.io.File(rootfsDir, "sys/.empty").absolutePath)
        val etcDirPath = quoteShell(java.io.File(rootfsDir, "etc").absolutePath)
        val tmpDirPath = quoteShell(java.io.File(rootfsDir, "tmp").absolutePath)
        val dnsContent = OpenClawRuntimeSupport.defaultDnsForShell().trimEnd()
        val normalizedCommand = command.trimEnd()

        return buildString {
            appendLine("set -eu")
            appendLine("source \"\${HOME}/common.sh\"")
            appendLine("install_ubuntu")
            appendLine("configure_sources")
            appendLine("fix_permissions")
            appendLine()
            appendLine("if [ -f \"\${HOME}/setup_fake_sysdata.sh\" ]; then")
            appendLine("  export INSTALLED_ROOTFS_DIR=$installedRootfsDir")
            appendLine("  export distro_name=ubuntu")
            appendLine("  export DEFAULT_FAKE_KERNEL_RELEASE=${quoteShell(FAKE_KERNEL_RELEASE)}")
            appendLine("  export DEFAULT_FAKE_KERNEL_VERSION=${quoteShell(FAKE_KERNEL_VERSION)}")
            appendLine("  . \"\${HOME}/setup_fake_sysdata.sh\"")
            appendLine("  setup_fake_sysdata || true")
            appendLine("fi")
            appendLine()
            appendLine("mkdir -p $rootfsPath/tmp")
            appendLine("mkdir -p $rootfsPath/tmp/npm-cache/_cacache/tmp")
            appendLine("mkdir -p $rootfsPath/tmp/npm-cache/_cacache/content-v2")
            appendLine("mkdir -p $rootfsPath/tmp/npm-cache/_cacache/index-v5")
            appendLine("mkdir -p $rootfsPath/tmp/npm-cache/_logs")
            appendLine("mkdir -p $rootfsPath/root/.npm")
            appendLine("mkdir -p $rootfsPath/root/.config")
            appendLine("mkdir -p $rootfsPath/root/.cache")
            appendLine("mkdir -p $rootfsPath/root/.cache/openclaw")
            appendLine("mkdir -p $rootfsPath/root/.cache/node")
            appendLine("mkdir -p $rootfsPath/root/.config/openclaw")
            appendLine("mkdir -p $rootfsPath/root/.local/share")
            appendLine("mkdir -p $rootfsPath/usr/local/lib/node_modules")
            appendLine("mkdir -p $rootfsPath/usr/local/bin")
            appendLine("mkdir -p $rootfsPath/dev/shm")
            appendLine("mkdir -p $rootfsPath/run/lock")
            appendLine()
            appendLine("if [ ! -s $resolvPath ]; then")
            appendLine("  mkdir -p $etcDirPath")
            appendLine("  cat > $resolvPath <<'EOF_RESOLV'")
            appendLine(dnsContent)
            appendLine("EOF_RESOLV")
            appendLine("fi")
            appendLine()
            appendLine("cat > $guestScriptPath <<'EOF_GUEST'")
            appendLine(normalizedCommand)
            appendLine("EOF_GUEST")
            appendLine("chmod 700 $guestScriptPath")
            appendLine()
            appendLine("PROOT_ARGS=\"\"")
            appendLine("append_bind_arg() {")
            appendLine("  bind_source=\"\$1\"")
            appendLine("  bind_target=\"\$2\"")
            appendLine("  if [ ! -e \"\$bind_source\" ] && [ ! -L \"\$bind_source\" ]; then")
            appendLine("    return 0")
            appendLine("  fi")
            appendLine("  if [ -n \"\$bind_target\" ] && [ \"\$bind_source\" != \"\$bind_target\" ]; then")
            appendLine("    PROOT_ARGS=\"\$PROOT_ARGS --bind=\$bind_source:\$bind_target\"")
            appendLine("  else")
            appendLine("    PROOT_ARGS=\"\$PROOT_ARGS --bind=\$bind_source\"")
            appendLine("  fi")
            appendLine("}")
            appendLine()
            appendLine("append_bind_arg /dev /dev")
            appendLine("append_bind_arg /dev/urandom /dev/random")
            appendLine("append_bind_arg /proc /proc")
            appendLine("append_bind_arg /proc/self/fd /dev/fd")
            appendLine("append_bind_arg /proc/self/fd/0 /dev/stdin")
            appendLine("append_bind_arg /proc/self/fd/1 /dev/stdout")
            appendLine("append_bind_arg /proc/self/fd/2 /dev/stderr")
            appendLine("append_bind_arg /sys /sys")
            appendLine("append_bind_arg $fakeLoadavg /proc/loadavg")
            appendLine("append_bind_arg $fakeStat /proc/stat")
            appendLine("append_bind_arg $fakeUptime /proc/uptime")
            appendLine("append_bind_arg $fakeVersion /proc/version")
            appendLine("append_bind_arg $fakeVmstat /proc/vmstat")
            appendLine("append_bind_arg $fakeCapLastCap /proc/sys/kernel/cap_last_cap")
            appendLine("append_bind_arg $fakeMaxUserWatches /proc/sys/fs/inotify/max_user_watches")
            appendLine("append_bind_arg $fakeFipsEnabled /proc/sys/crypto/fips_enabled")
            appendLine("append_bind_arg $fakeSelinux /sys/fs/selinux")
            appendLine("append_bind_arg $resolvPath /etc/resolv.conf")
            appendLine("append_bind_arg $tmpDirPath /dev/shm")
            appendLine("if [ -e /storage ]; then")
            appendLine("  append_bind_arg /storage /storage")
            appendLine("fi")
            appendLine("if [ -e /storage/emulated/0 ]; then")
            appendLine("  append_bind_arg /storage/emulated/0 /sdcard")
            appendLine("fi")
            appendLine()
            appendLine("exec $prootPath \\")
            appendLine("  --root-id \\")
            appendLine("  --kernel-release=$FAKE_KERNEL_RELEASE \\")
            appendLine("  --link2symlink \\")
            appendLine("  -L \\")
            appendLine("  --kill-on-exit \\")
            appendLine("  --rootfs=$rootfsPath \\")
            appendLine("  --cwd=/root \\")
            appendLine("  \$PROOT_ARGS \\")
            appendLine("  /usr/bin/env -i \\")
            appendLine("    HOME=/root \\")
            appendLine("    LANG=C.UTF-8 \\")
            appendLine("    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \\")
            appendLine("    TERM=xterm-256color \\")
            appendLine("    TMPDIR=/tmp \\")
            appendLine("    DEBIAN_FRONTEND=noninteractive \\")
            appendLine("    npm_config_cache=/tmp/npm-cache \\")
            appendLine("    /bin/bash -lc \"/bin/bash --noprofile --norc $guestScriptGuestPath; rc=\\${'$'}?; rm -f $guestScriptGuestPath; exit \\${'$'}rc\"")
        }
    }

    private fun quoteShell(value: String): String {
        return "'" + value.replace("'", "'\"'\"'") + "'"
    }
}
