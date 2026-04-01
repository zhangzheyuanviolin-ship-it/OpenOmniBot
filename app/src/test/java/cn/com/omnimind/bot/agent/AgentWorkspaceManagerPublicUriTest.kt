package cn.com.omnimind.bot.agent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AgentWorkspaceManagerPublicUriTest {
    @Test
    fun publicStoragePathRoundTripsThroughOmnibotUri() {
        val uri = AgentWorkspaceManager.publicUriForStoragePath(
            "/storage/DCIM/Camera/demo.jpg"
        )

        assertEquals("omnibot://public/DCIM/Camera/demo.jpg", uri)
        assertEquals(
            "/storage/DCIM/Camera/demo.jpg",
            AgentWorkspaceManager.storagePathForPublicUri(uri!!)
        )
    }

    @Test
    fun publicStorageRootMapsToRootUriAndRejectsWorkspacePath() {
        assertEquals(
            "omnibot://public",
            AgentWorkspaceManager.publicUriForStoragePath("/storage")
        )
        assertEquals(
            "/storage",
            AgentWorkspaceManager.storagePathForPublicUri("omnibot://public")
        )
        assertNull(AgentWorkspaceManager.publicUriForStoragePath("/workspace/demo.txt"))
    }
}
