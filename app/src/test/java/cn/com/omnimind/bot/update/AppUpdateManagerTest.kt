package cn.com.omnimind.bot.update

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AppUpdateManagerTest {
    @Test
    fun normalizeVersionStripsLeadingV() {
        assertEquals("0.0.1", AppUpdateManager.normalizeVersion("v0.0.1"))
        assertEquals("1.2.3", AppUpdateManager.normalizeVersion("V1.2.3"))
    }

    @Test
    fun compareVersionsUsesSemanticOrdering() {
        assertEquals(1, AppUpdateManager.compareVersions("0.0.2", "0.0.1"))
        assertEquals(0, AppUpdateManager.compareVersions("v1.2.0", "1.2"))
        assertEquals(-1, AppUpdateManager.compareVersions("1.9.9", "2.0.0"))
    }

    @Test
    fun selectPreferredApkAssetPrefersReleaseNamingConvention() {
        val assets = listOf(
            ReleaseAsset(
                name = "app-production-release.apk",
                downloadUrl = "https://example.com/app-production-release.apk"
            ),
            ReleaseAsset(
                name = "OpenOmniBot-v0.0.2.apk",
                downloadUrl = "https://example.com/OpenOmniBot-v0.0.2.apk"
            )
        )

        val selected = AppUpdateManager.selectPreferredApkAsset(assets)
        assertEquals("OpenOmniBot-v0.0.2.apk", selected?.name)
    }

    @Test
    fun selectPreferredApkAssetReturnsNullWhenNoApkExists() {
        val selected = AppUpdateManager.selectPreferredApkAsset(emptyList())
        assertNull(selected)
    }
}
