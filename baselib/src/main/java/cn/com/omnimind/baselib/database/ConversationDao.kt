package cn.com.omnimind.baselib.database

import androidx.room.*

@Dao
interface ConversationDao {

    @Insert
    suspend fun insert(conversation: Conversation): Long

    @Update
    suspend fun update(conversation: Conversation)

    @Delete
    suspend fun delete(conversation: Conversation)

    @Query("SELECT * FROM conversations WHERE id = :id")
    suspend fun getById(id: Long): Conversation?

    @Query("SELECT * FROM conversations WHERE syncId = :syncId LIMIT 1")
    suspend fun getBySyncId(syncId: String): Conversation?

    @Query("SELECT * FROM conversations ORDER BY updatedAt DESC")
    suspend fun getAll(): List<Conversation>

    @Query("SELECT * FROM conversations WHERE updatedAt > :updatedAfter ORDER BY updatedAt ASC, id ASC")
    suspend fun getUpdatedAfter(updatedAfter: Long): List<Conversation>

    @Query("SELECT * FROM conversations ORDER BY updatedAt DESC LIMIT :limit OFFSET :offset")
    suspend fun getConversationsByPage(offset: Int, limit: Int): List<Conversation>

    @Query("SELECT COUNT(*) FROM conversations")
    suspend fun getConversationCount(): Int

    @Query("DELETE FROM conversations WHERE id = :id")
    suspend fun deleteById(id: Long): Int

    @Query("DELETE FROM conversations WHERE syncId = :syncId")
    suspend fun deleteBySyncId(syncId: String): Int

    @Query("DELETE FROM conversations")
    suspend fun deleteAll(): Int

    @Query("UPDATE conversations SET messageCount = messageCount + 1, updatedAt = :updatedAt WHERE id = :id")
    suspend fun incrementMessageCount(id: Long, updatedAt: Long)

    @Query("SELECT * FROM conversations WHERE status = :status ORDER BY updatedAt DESC")
    suspend fun getByStatus(status: Int): List<Conversation>

    @Query("SELECT MAX(updatedAt) FROM conversations")
    suspend fun getMaxUpdatedAt(): Long?
}
