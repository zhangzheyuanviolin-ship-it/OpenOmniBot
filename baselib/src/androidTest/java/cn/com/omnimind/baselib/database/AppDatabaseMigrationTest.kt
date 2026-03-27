package cn.com.omnimind.baselib.database

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AppDatabaseMigrationTest {

    @After
    fun cleanUp() {
        testContext.deleteDatabase(TEST_DB_NAME)
    }

    @Test
    fun migrate5To9_preservesExistingRows_withoutInjectingSampleConversations() = runBlocking {
        createVersion5Database()

        val database = openMigratedDatabase()
        try {
            val executionRecord = database.executionRecordDao().getAll().single()
            assertEquals(1L, executionRecord.id)
            assertEquals("legacy execution", executionRecord.title)
            assertEquals("legacy-content", executionRecord.content)
            assertEquals("failed", executionRecord.status)

            val favoriteRecord = database.favoriteRecordDao().getAll().single()
            assertEquals(2L, favoriteRecord.id)
            assertEquals("legacy favorite", favoriteRecord.title)
            assertEquals("cn.legacy.favorite", favoriteRecord.packageName)

            assertTrue(database.conversationDao().getAll().isEmpty())
        } finally {
            database.close()
        }
    }

    @Test
    fun migrate8To9_preservesConversationRows_andBackfillsNewColumns() = runBlocking {
        createVersion8Database()

        val database = openMigratedDatabase()
        try {
            val conversation = database.conversationDao().getById(1L)
            assertNotNull(conversation)
            assertEquals("legacy conversation", conversation!!.title)
            assertEquals("agent", conversation.mode)
            assertEquals("legacy summary", conversation.summary)
            assertNull(conversation.contextSummary)
            assertNull(conversation.contextSummaryCutoffEntryDbId)
            assertEquals(0L, conversation.contextSummaryUpdatedAt)
            assertEquals(0, conversation.latestPromptTokens)
            assertEquals(128_000, conversation.promptTokenThreshold)
            assertEquals(0L, conversation.latestPromptTokensUpdatedAt)

            val entry = database.agentConversationEntryDao()
                .getByThreadAndEntryId(1L, "agent", "entry-1")
            assertNotNull(entry)
            assertEquals("queued", entry!!.status)
        } finally {
            database.close()
        }
    }

    private fun openMigratedDatabase(): AppDatabase {
        return Room.databaseBuilder(testContext, AppDatabase::class.java, TEST_DB_NAME)
            .allowMainThreadQueries()
            .addMigrations(*DatabaseHelper.ALL_MIGRATIONS)
            .build()
            .also { it.openHelper.writableDatabase }
    }

    private fun createVersion5Database() {
        val database = openLegacyDatabase(version = 5)
        try {
            createCommonPreConversationTables(database)
            database.execSQL(
                """
                INSERT INTO execution_records
                (id, title, appName, packageName, nodeId, suggestionId, iconUrl, type, content, status, createdAt, updatedAt)
                VALUES
                (1, 'legacy execution', 'Legacy App', 'cn.legacy.app', 'node-1', 'suggestion-1', NULL, 'summary', 'legacy-content', 'failed', 1000, 2000)
                """.trimIndent()
            )
            database.execSQL(
                """
                INSERT INTO favorite_records
                (id, title, `desc`, type, imagePath, packageName, status, createdAt, updatedAt)
                VALUES
                (2, 'legacy favorite', 'legacy desc', 'image', '/tmp/legacy.png', 'cn.legacy.favorite', 1, 3000, 4000)
                """.trimIndent()
            )
        } finally {
            database.close()
        }
    }

    private fun createVersion8Database() {
        val database = openLegacyDatabase(version = 8)
        try {
            createCommonPreConversationTables(database)
            database.execSQL(
                """
                CREATE TABLE IF NOT EXISTS `conversations` (
                    `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                    `title` TEXT NOT NULL,
                    `mode` TEXT NOT NULL DEFAULT 'normal',
                    `summary` TEXT,
                    `status` INTEGER NOT NULL DEFAULT 0,
                    `lastMessage` TEXT,
                    `messageCount` INTEGER NOT NULL DEFAULT 0,
                    `createdAt` INTEGER NOT NULL,
                    `updatedAt` INTEGER NOT NULL
                )
                """.trimIndent()
            )
            database.execSQL(
                """
                CREATE TABLE IF NOT EXISTS `agent_conversation_entries` (
                    `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                    `conversationId` INTEGER NOT NULL,
                    `conversationMode` TEXT NOT NULL,
                    `entryId` TEXT NOT NULL,
                    `entryType` TEXT NOT NULL,
                    `status` TEXT NOT NULL,
                    `summary` TEXT NOT NULL,
                    `payloadJson` TEXT NOT NULL,
                    `createdAt` INTEGER NOT NULL,
                    `updatedAt` INTEGER NOT NULL
                )
                """.trimIndent()
            )
            database.execSQL(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS
                `index_agent_conversation_entries_conversationId_conversationMode_entryId`
                ON `agent_conversation_entries` (`conversationId`, `conversationMode`, `entryId`)
                """.trimIndent()
            )
            database.execSQL(
                """
                CREATE INDEX IF NOT EXISTS
                `index_agent_conversation_entries_conversationId_conversationMode_updatedAt`
                ON `agent_conversation_entries` (`conversationId`, `conversationMode`, `updatedAt`)
                """.trimIndent()
            )
            database.execSQL(
                """
                INSERT INTO conversations
                (id, title, mode, summary, status, lastMessage, messageCount, createdAt, updatedAt)
                VALUES
                (1, 'legacy conversation', 'agent', 'legacy summary', 0, 'last legacy message', 3, 5000, 6000)
                """.trimIndent()
            )
            database.execSQL(
                """
                INSERT INTO agent_conversation_entries
                (id, conversationId, conversationMode, entryId, entryType, status, summary, payloadJson, createdAt, updatedAt)
                VALUES
                (1, 1, 'agent', 'entry-1', 'message', 'queued', 'legacy entry', '{"text":"hello"}', 7000, 8000)
                """.trimIndent()
            )
        } finally {
            database.close()
        }
    }

    private fun createCommonPreConversationTables(database: SQLiteDatabase) {
        database.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `app_icons` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `appName` TEXT NOT NULL,
                `packageName` TEXT NOT NULL,
                `icon_base64` TEXT NOT NULL,
                `icon_path` TEXT NOT NULL,
                `createdAt` INTEGER NOT NULL,
                `updatedAt` INTEGER NOT NULL
            )
            """.trimIndent()
        )
        database.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `study_records` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `title` TEXT NOT NULL,
                `suggestionId` TEXT NOT NULL,
                `appName` TEXT NOT NULL,
                `packageName` TEXT NOT NULL,
                `createdAt` INTEGER NOT NULL,
                `updatedAt` INTEGER NOT NULL,
                `isFavorite` INTEGER NOT NULL
            )
            """.trimIndent()
        )
        database.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `favorite_records` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `title` TEXT NOT NULL,
                `desc` TEXT NOT NULL,
                `type` TEXT NOT NULL,
                `imagePath` TEXT NOT NULL,
                `packageName` TEXT NOT NULL DEFAULT '',
                `status` INTEGER NOT NULL,
                `createdAt` INTEGER NOT NULL,
                `updatedAt` INTEGER NOT NULL
            )
            """.trimIndent()
        )
        database.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `execution_records` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `title` TEXT NOT NULL,
                `appName` TEXT NOT NULL,
                `packageName` TEXT NOT NULL,
                `nodeId` TEXT NOT NULL,
                `suggestionId` TEXT NOT NULL,
                `iconUrl` TEXT,
                `type` TEXT NOT NULL DEFAULT 'unknown',
                `createdAt` INTEGER NOT NULL,
                `updatedAt` INTEGER NOT NULL,
                `content` TEXT,
                `status` TEXT NOT NULL DEFAULT 'success'
            )
            """.trimIndent()
        )
        database.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `messages` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `messageId` TEXT NOT NULL,
                `type` INTEGER NOT NULL,
                `user` INTEGER NOT NULL,
                `content` TEXT NOT NULL,
                `createdAt` INTEGER NOT NULL,
                `updatedAt` INTEGER NOT NULL
            )
            """.trimIndent()
        )
        database.execSQL(
            """
            CREATE TABLE IF NOT EXISTS `cache_suggestion` (
                `id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                `suggestionId` TEXT NOT NULL,
                `packageName` TEXT NOT NULL,
                `indexNum` INTEGER NOT NULL
            )
            """.trimIndent()
        )
    }

    private fun openLegacyDatabase(version: Int): SQLiteDatabase {
        testContext.deleteDatabase(TEST_DB_NAME)
        return testContext.openOrCreateDatabase(TEST_DB_NAME, Context.MODE_PRIVATE, null).apply {
            this.version = version
        }
    }

    private val testContext: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    companion object {
        private const val TEST_DB_NAME = "app-database-migration-test"
    }
}
