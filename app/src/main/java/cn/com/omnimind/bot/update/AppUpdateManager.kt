package cn.com.omnimind.bot.update

import android.content.Context
import androidx.annotation.VisibleForTesting
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import cn.com.omnimind.baselib.service.DeviceInfoService
import cn.com.omnimind.baselib.util.OmniLog
import cn.com.omnimind.bot.manager.ExternalApkInstallResult
import cn.com.omnimind.bot.manager.ExternalApkInstaller
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.time.Instant
import java.util.Locale
import java.util.concurrent.TimeUnit

data class AppUpdateState(
    val currentVersion: String,
    val latestVersion: String,
    val hasUpdate: Boolean,
    val checkedAt: Long,
    val publishedAt: Long,
    val releaseUrl: String,
    val releaseNotes: String,
    val apkName: String,
    val apkDownloadUrl: String
) {
    fun toMap(): Map<String, Any> = mapOf(
        "currentVersion" to currentVersion,
        "latestVersion" to latestVersion,
        "hasUpdate" to hasUpdate,
        "checkedAt" to checkedAt,
        "publishedAt" to publishedAt,
        "releaseUrl" to releaseUrl,
        "releaseNotes" to releaseNotes,
        "apkName" to apkName,
        "apkDownloadUrl" to apkDownloadUrl
    )
}

@VisibleForTesting
internal data class ReleaseAsset(
    val name: String,
    val downloadUrl: String
)

object AppUpdateManager {
    private const val TAG = "AppUpdateManager"
    private const val PREFS_NAME = "app_update_state"
    private const val KEY_LATEST_VERSION = "latest_version"
    private const val KEY_HAS_UPDATE = "has_update"
    private const val KEY_CHECKED_AT = "checked_at"
    private const val KEY_PUBLISHED_AT = "published_at"
    private const val KEY_RELEASE_URL = "release_url"
    private const val KEY_RELEASE_NOTES = "release_notes"
    private const val KEY_APK_NAME = "apk_name"
    private const val KEY_APK_DOWNLOAD_URL = "apk_download_url"

    private const val LATEST_RELEASE_URL =
        "https://api.github.com/repos/omnimind-ai/OpenOmniBot/releases/latest"
    private const val WORK_NAME = "app_update_periodic_check"
    private const val PERIODIC_CHECK_HOURS = 12L
    private const val SILENT_CHECK_INTERVAL_MS = 6 * 60 * 60 * 1000L
    private const val USER_AGENT = "OpenOmniBot-App"

    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .writeTimeout(20, TimeUnit.SECONDS)
            .build()
    }

    fun schedulePeriodicChecks(context: Context) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val request = PeriodicWorkRequestBuilder<AppUpdateWorker>(
            PERIODIC_CHECK_HOURS,
            TimeUnit.HOURS
        )
            .setConstraints(constraints)
            .build()

        WorkManager.getInstance(context.applicationContext)
            .enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )
    }

    fun requestSilentCheckIfDue(context: Context) {
        schedulePeriodicChecks(context)
        CoroutineScope(Dispatchers.IO).launch {
            runCatching {
                checkNow(context.applicationContext, force = false)
            }.onFailure {
                OmniLog.w(TAG, "Silent app update check failed: ${it.message}")
            }
        }
    }

    fun getCachedStatus(context: Context): AppUpdateState {
        return readState(context.applicationContext, currentVersion(context.applicationContext))
    }

    suspend fun checkNow(context: Context, force: Boolean): AppUpdateState {
        val appContext = context.applicationContext
        val now = System.currentTimeMillis()
        val currentVersion = currentVersion(appContext)
        val cached = readState(appContext, currentVersion)
        if (!force && now - cached.checkedAt < SILENT_CHECK_INTERVAL_MS) {
            return cached
        }

        val fetched = fetchLatestReleaseState(currentVersion)
            .copy(checkedAt = now)
        saveState(appContext, fetched)
        return fetched
    }

    suspend fun installLatestApk(context: Context): ExternalApkInstallResult {
        val installState = resolveInstallState(context)
        if (!installState.hasUpdate || installState.apkDownloadUrl.isBlank()) {
            return ExternalApkInstallResult(
                success = false,
                status = ExternalApkInstaller.STATUS_INSTALL_FAILED,
                message = "当前没有可安装的新版本。"
            )
        }

        val safeFileName = installState.apkName.ifBlank {
            "OpenOmniBot-v${installState.latestVersion}.apk"
        }
        return ExternalApkInstaller.downloadAndInstall(
            context = context,
            downloadUrl = installState.apkDownloadUrl,
            apkFileName = safeFileName,
            displayName = "OpenOmniBot"
        )
    }

    @VisibleForTesting
    internal fun normalizeVersion(raw: String?): String {
        return raw
            ?.trim()
            ?.removePrefix("v")
            ?.removePrefix("V")
            ?.substringBefore('+')
            ?.trim()
            .orEmpty()
    }

    @VisibleForTesting
    internal fun compareVersions(leftRaw: String?, rightRaw: String?): Int {
        val left = normalizeVersion(leftRaw)
        val right = normalizeVersion(rightRaw)
        if (left == right) return 0

        val leftParts = left.split('.').mapNotNull { it.toIntOrNull() }
        val rightParts = right.split('.').mapNotNull { it.toIntOrNull() }
        if (leftParts.isNotEmpty() && rightParts.isNotEmpty()) {
            val maxLength = maxOf(leftParts.size, rightParts.size)
            for (index in 0 until maxLength) {
                val leftValue = leftParts.getOrElse(index) { 0 }
                val rightValue = rightParts.getOrElse(index) { 0 }
                if (leftValue != rightValue) {
                    return leftValue.compareTo(rightValue)
                }
            }
            return 0
        }

        return left.compareTo(right)
    }

    @VisibleForTesting
    internal fun selectPreferredApkAsset(assets: List<ReleaseAsset>): ReleaseAsset? {
        if (assets.isEmpty()) return null
        val preferred = assets.firstOrNull {
            it.name.startsWith("OpenOmniBot-v", ignoreCase = true) &&
                it.name.lowercase(Locale.ROOT).endsWith(".apk")
        }
        if (preferred != null) return preferred
        return assets.firstOrNull { it.name.lowercase(Locale.ROOT).endsWith(".apk") }
    }

    private suspend fun resolveInstallState(context: Context): AppUpdateState {
        val cached = getCachedStatus(context)
        if (cached.hasUpdate && cached.apkDownloadUrl.isNotBlank()) {
            return cached
        }
        return checkNow(context, force = true)
    }

    private fun readState(context: Context, currentVersion: String): AppUpdateState {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val latestVersion = prefs.getString(KEY_LATEST_VERSION, currentVersion).orEmpty().ifBlank {
            currentVersion
        }
        val hasUpdate = prefs.getBoolean(KEY_HAS_UPDATE, false) &&
            compareVersions(latestVersion, currentVersion) > 0
        return AppUpdateState(
            currentVersion = currentVersion,
            latestVersion = latestVersion,
            hasUpdate = hasUpdate,
            checkedAt = prefs.getLong(KEY_CHECKED_AT, 0L),
            publishedAt = prefs.getLong(KEY_PUBLISHED_AT, 0L),
            releaseUrl = prefs.getString(KEY_RELEASE_URL, "").orEmpty(),
            releaseNotes = prefs.getString(KEY_RELEASE_NOTES, "").orEmpty(),
            apkName = prefs.getString(KEY_APK_NAME, "").orEmpty(),
            apkDownloadUrl = prefs.getString(KEY_APK_DOWNLOAD_URL, "").orEmpty()
        )
    }

    private fun saveState(context: Context, state: AppUpdateState) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_LATEST_VERSION, state.latestVersion)
            .putBoolean(KEY_HAS_UPDATE, state.hasUpdate)
            .putLong(KEY_CHECKED_AT, state.checkedAt)
            .putLong(KEY_PUBLISHED_AT, state.publishedAt)
            .putString(KEY_RELEASE_URL, state.releaseUrl)
            .putString(KEY_RELEASE_NOTES, state.releaseNotes)
            .putString(KEY_APK_NAME, state.apkName)
            .putString(KEY_APK_DOWNLOAD_URL, state.apkDownloadUrl)
            .apply()
    }

    private fun currentVersion(context: Context): String {
        return DeviceInfoService.getAppVersion(context)["versionName"]?.toString()
            ?.trim()
            ?.ifBlank { "0.0.0" }
            ?: "0.0.0"
    }

    private fun fetchLatestReleaseState(currentVersion: String): AppUpdateState {
        val request = Request.Builder()
            .url(LATEST_RELEASE_URL)
            .addHeader("Accept", "application/vnd.github+json")
            .addHeader("X-GitHub-Api-Version", "2022-11-28")
            .addHeader("User-Agent", USER_AGENT)
            .get()
            .build()

        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw IOException("GitHub release request failed with code ${response.code}")
            }

            val body = response.body?.string().orEmpty()
            if (body.isBlank()) {
                throw IOException("GitHub release response body is empty")
            }

            val release = JSONObject(body)
            if (release.optBoolean("draft") || release.optBoolean("prerelease")) {
                return AppUpdateState(
                    currentVersion = currentVersion,
                    latestVersion = currentVersion,
                    hasUpdate = false,
                    checkedAt = System.currentTimeMillis(),
                    publishedAt = 0L,
                    releaseUrl = "",
                    releaseNotes = "",
                    apkName = "",
                    apkDownloadUrl = ""
                )
            }
            val latestVersion = normalizeVersion(release.optString("tag_name"))
                .ifBlank { currentVersion }
            val releaseUrl = release.optString("html_url")
            val releaseNotes = release.optString("body")
            val publishedAt = parseGithubTimeToMillis(release.optString("published_at"))
            val assets = parseAssets(release.optJSONArray("assets"))
            val preferredAsset = selectPreferredApkAsset(assets)

            return AppUpdateState(
                currentVersion = currentVersion,
                latestVersion = latestVersion,
                hasUpdate = compareVersions(latestVersion, currentVersion) > 0,
                checkedAt = System.currentTimeMillis(),
                publishedAt = publishedAt,
                releaseUrl = releaseUrl,
                releaseNotes = releaseNotes,
                apkName = preferredAsset?.name.orEmpty(),
                apkDownloadUrl = preferredAsset?.downloadUrl.orEmpty()
            )
        }
    }

    private fun parseAssets(array: JSONArray?): List<ReleaseAsset> {
        if (array == null) return emptyList()
        val assets = mutableListOf<ReleaseAsset>()
        for (index in 0 until array.length()) {
            val raw = array.optJSONObject(index) ?: continue
            val name = raw.optString("name")
            if (!name.lowercase(Locale.ROOT).endsWith(".apk")) continue
            val downloadUrl = raw.optString("browser_download_url")
            if (downloadUrl.isBlank()) continue
            assets += ReleaseAsset(name = name, downloadUrl = downloadUrl)
        }
        return assets
    }

    private fun parseGithubTimeToMillis(raw: String?): Long {
        if (raw.isNullOrBlank()) return 0L
        return runCatching { Instant.parse(raw).toEpochMilli() }.getOrDefault(0L)
    }
}

class AppUpdateWorker(
    appContext: Context,
    workerParams: androidx.work.WorkerParameters
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork(): androidx.work.ListenableWorker.Result {
        return runCatching {
            AppUpdateManager.checkNow(applicationContext, force = true)
            androidx.work.ListenableWorker.Result.success()
        }.getOrElse {
            OmniLog.w("AppUpdateWorker", "Periodic app update check failed: ${it.message}")
            androidx.work.ListenableWorker.Result.retry()
        }
    }
}
