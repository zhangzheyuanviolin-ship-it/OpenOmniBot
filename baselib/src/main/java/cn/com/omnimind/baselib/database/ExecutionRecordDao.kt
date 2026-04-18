package cn.com.omnimind.baselib.database

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update

@Dao
interface ExecutionRecordDao {
    @Insert
    suspend fun insert(record: ExecutionRecord): Long

    @Update
    suspend fun update(record: ExecutionRecord)

    @Query("SELECT * FROM execution_records WHERE id = :id LIMIT 1")
    suspend fun getById(id: Long): ExecutionRecord?

    @Query("SELECT * FROM execution_records ORDER BY createdAt DESC")
    suspend fun getAll(): List<ExecutionRecord>

    @Query("SELECT * FROM execution_records WHERE syncId = :syncId LIMIT 1")
    suspend fun getBySyncId(syncId: String): ExecutionRecord?

    @Query("SELECT * FROM execution_records WHERE updatedAt > :updatedAfter ORDER BY updatedAt ASC, id ASC")
    suspend fun getUpdatedAfter(updatedAfter: Long): List<ExecutionRecord>

    @Query("SELECT * FROM execution_records WHERE appName = :appName ORDER BY createdAt DESC")
    suspend fun getByAppName(appName: String): List<ExecutionRecord>

    @Query("SELECT appName, packageName, COUNT(*) as count FROM execution_records GROUP BY appName")
    suspend fun getNumGroupByAppName(): List<ExecutionRecordCount>

    @Query("SELECT title, COUNT(*) as count FROM execution_records GROUP BY title")
    suspend fun getNumGroupByTitle(): List<ExecutionRecordTitleCount>

    @Query("UPDATE execution_records SET title = :title, updatedAt = :updatedAt WHERE id = :id")
    suspend fun updateTitleById(id: Long, title: String, updatedAt: Long)

    @Query("UPDATE execution_records SET content = :content, updatedAt = :updatedAt WHERE id = :id")
    suspend fun updateContentById(id: Long, content: String, updatedAt: Long)

    @Query("UPDATE execution_records SET status = :status, updatedAt = :updatedAt WHERE id = :id")
    suspend fun updateStatusById(id: Long, status: String, updatedAt: Long)

    @Query("SELECT * FROM execution_records WHERE title LIKE '%' || :title || '%'")
    suspend fun getByTitle(title: String): List<ExecutionRecord>

    // Updated query to group by nodeId and suggestionId, excluding running records
    @Query("SELECT MAX(id) as id, title, appName, packageName, nodeId, suggestionId, iconUrl, type, content, COUNT(*) as count, MAX(createdAt) as lastExecutionTime FROM execution_records WHERE status != 'running' GROUP BY nodeId, suggestionId ORDER BY lastExecutionTime DESC")
    suspend fun getTaskExecutionInfos(): List<TaskExecutionInfoDTO>

    @Query("DELETE FROM execution_records WHERE id = :id")
    suspend fun deleteById(id: Long)

    @Query("DELETE FROM execution_records WHERE syncId = :syncId")
    suspend fun deleteBySyncId(syncId: String)

    // Updated query to delete by nodeId and suggestionId
    @Query("DELETE FROM execution_records WHERE nodeId = :nodeId AND suggestionId = :suggestionId")
    suspend fun deleteByNodeAndSuggestionId(nodeId: String, suggestionId: String)

    // 按 nodeId 和 suggestionId 获取执行记录列表，排除执行中的记录
    @Query("SELECT * FROM execution_records WHERE nodeId = :nodeId AND suggestionId = :suggestionId AND status != 'running' ORDER BY createdAt DESC")
    suspend fun getByNodeAndSuggestionId(nodeId: String, suggestionId: String): List<ExecutionRecord>

    @Query("SELECT MAX(updatedAt) FROM execution_records")
    suspend fun getMaxUpdatedAt(): Long?

    data class ExecutionRecordCount(val appName: String, val packageName: String, val count: Int)
    data class ExecutionRecordTitleCount(val title: String, val count: Int)
    data class TaskExecutionInfoDTO(
        val id: Long,
        val title: String,
        val appName: String,
        val packageName: String,
        val nodeId: String,
        val suggestionId: String,
        val iconUrl: String?,
        val type: String,
        val content: String?,
        val count: Int,
        val lastExecutionTime: Long
    )
}
