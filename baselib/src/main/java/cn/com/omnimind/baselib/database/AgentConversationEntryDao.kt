package cn.com.omnimind.baselib.database

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface AgentConversationEntryDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entry: AgentConversationEntry): Long

    @Query(
        """
        SELECT * FROM agent_conversation_entries
        WHERE conversationId = :conversationId AND conversationMode = :conversationMode
        ORDER BY createdAt ASC, id ASC
        """
    )
    suspend fun getThreadEntriesAsc(
        conversationId: Long,
        conversationMode: String
    ): List<AgentConversationEntry>

    @Query(
        """
        SELECT * FROM agent_conversation_entries
        WHERE conversationId = :conversationId AND conversationMode = :conversationMode
        ORDER BY createdAt DESC, id DESC
        """
    )
    suspend fun getThreadEntriesDesc(
        conversationId: Long,
        conversationMode: String
    ): List<AgentConversationEntry>

    @Query(
        """
        SELECT * FROM agent_conversation_entries
        WHERE conversationId = :conversationId
        ORDER BY createdAt DESC, id DESC
        """
    )
    suspend fun getConversationEntriesDesc(conversationId: Long): List<AgentConversationEntry>

    @Query(
        """
        SELECT * FROM agent_conversation_entries
        WHERE conversationId = :conversationId
        ORDER BY createdAt ASC, id ASC
        """
    )
    suspend fun getConversationEntriesAsc(conversationId: Long): List<AgentConversationEntry>

    @Query(
        """
        SELECT * FROM agent_conversation_entries
        WHERE conversationId = :conversationId
        ORDER BY createdAt DESC, id DESC
        LIMIT 1
        """
    )
    suspend fun getLatestConversationEntry(conversationId: Long): AgentConversationEntry?

    @Query(
        """
        SELECT * FROM agent_conversation_entries
        WHERE conversationId = :conversationId
        ORDER BY createdAt ASC, id ASC
        LIMIT 1
        """
    )
    suspend fun getEarliestConversationEntry(conversationId: Long): AgentConversationEntry?

    @Query(
        """
        SELECT * FROM agent_conversation_entries
        WHERE conversationId = :conversationId
        ORDER BY updatedAt DESC, id DESC
        LIMIT 1
        """
    )
    suspend fun getLatestConversationUpdate(conversationId: Long): AgentConversationEntry?

    @Query(
        """
        SELECT COUNT(*) FROM agent_conversation_entries
        WHERE conversationId = :conversationId
        """
    )
    suspend fun countConversationEntries(conversationId: Long): Int

    @Query(
        """
        SELECT * FROM agent_conversation_entries
        WHERE conversationId = :conversationId
          AND conversationMode = :conversationMode
          AND entryId = :entryId
        LIMIT 1
        """
    )
    suspend fun getByThreadAndEntryId(
        conversationId: Long,
        conversationMode: String,
        entryId: String
    ): AgentConversationEntry?

    @Query(
        """
        SELECT * FROM agent_conversation_entries
        WHERE conversationId = :conversationId AND conversationMode = :conversationMode
        ORDER BY createdAt DESC, id DESC
        LIMIT :limit OFFSET :offset
        """
    )
    suspend fun getThreadEntriesDescPaged(
        conversationId: Long,
        conversationMode: String,
        limit: Int,
        offset: Int
    ): List<AgentConversationEntry>

    @Query(
        """
        SELECT COUNT(*) FROM agent_conversation_entries
        WHERE conversationId = :conversationId AND conversationMode = :conversationMode
        """
    )
    suspend fun countThreadEntries(
        conversationId: Long,
        conversationMode: String
    ): Int

    @Query(
        """
        DELETE FROM agent_conversation_entries
        WHERE conversationId = :conversationId AND conversationMode = :conversationMode
        """
    )
    suspend fun deleteThreadEntries(
        conversationId: Long,
        conversationMode: String
    ): Int

    @Query(
        """
        DELETE FROM agent_conversation_entries
        WHERE conversationId = :conversationId
        """
    )
    suspend fun deleteConversationEntries(conversationId: Long): Int
}
