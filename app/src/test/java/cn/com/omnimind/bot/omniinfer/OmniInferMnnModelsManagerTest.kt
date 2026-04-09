package cn.com.omnimind.bot.omniinfer

import com.alibaba.mls.api.download.DownloadInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class OmniInferMnnModelsManagerTest {

    @Test
    fun dedupeInstalledRecords_mergesEntriesSharingSameLocalDirectory() {
        val records = listOf(
            record(
                id = "ModelScope/MNN/Qwen3.5-2B-MNN",
                path = "/data/user/0/cn.com.omnimind.bot/files/.mnnmodels/modelscope/Qwen3.5-2B-MNN",
            ),
            record(
                id = "Modelers/MNN/Qwen3.5-2B-MNN",
                path = "/data/user/0/cn.com.omnimind.bot/files/.mnnmodels/modelscope/Qwen3.5-2B-MNN",
            ),
            record(
                id = "HuggingFace/taobao-mnn/Qwen3.5-2B-MNN",
                path = "/data/user/0/cn.com.omnimind.bot/files/.mnnmodels/hf/Qwen3.5-2B-MNN",
            ),
        )

        val deduped = OmniInferMnnModelsManager.dedupeInstalledRecords(records)

        assertEquals(2, deduped.size)
        assertEquals("ModelScope/MNN/Qwen3.5-2B-MNN", deduped[0].id)
        assertEquals("HuggingFace/taobao-mnn/Qwen3.5-2B-MNN", deduped[1].id)
    }

    @Test
    fun dedupeInstalledRecords_prefersPreferredIdWhenDirectoriesMatch() {
        val records = listOf(
            record(
                id = "ModelScope/MNN/Qwen3.5-2B-MNN",
                path = "/data/user/0/cn.com.omnimind.bot/files/.mnnmodels/modelscope/Qwen3.5-2B-MNN",
            ),
            record(
                id = "Modelers/MNN/Qwen3.5-2B-MNN",
                path = "/data/user/0/cn.com.omnimind.bot/files/.mnnmodels/modelscope/Qwen3.5-2B-MNN",
            ),
        )

        val deduped = OmniInferMnnModelsManager.dedupeInstalledRecords(
            records = records,
            preferredIds = setOf("Modelers/MNN/Qwen3.5-2B-MNN"),
        )

        assertEquals(1, deduped.size)
        assertTrue(deduped.single().id == "Modelers/MNN/Qwen3.5-2B-MNN")
    }

    private fun record(
        id: String,
        path: String,
    ): OmniInferMnnModelsManager.InstalledModelRecord {
        return OmniInferMnnModelsManager.InstalledModelRecord(
            id = id,
            name = id.substringAfterLast('/'),
            path = path,
            configPath = "$path/config.json",
            source = id.substringBefore('/'),
            description = "",
            vendor = "",
            tags = listOf("MNN"),
            extraTags = emptyList(),
            fileSize = 0L,
            downloadedAt = 0L,
            readOnly = false,
            downloadInfo = DownloadInfo(),
        )
    }
}
