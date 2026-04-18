package cn.com.omnimind.baselib.database

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update

@Dao
interface SyncConflictRecordDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entry: SyncConflictRecord): Long

    @Update
    suspend fun update(entry: SyncConflictRecord)

    @Query("SELECT * FROM sync_conflict_record ORDER BY createdAt DESC")
    suspend fun getAll(): List<SyncConflictRecord>

    @Query("SELECT * FROM sync_conflict_record WHERE status = :status ORDER BY createdAt DESC")
    suspend fun getByStatus(status: String): List<SyncConflictRecord>

    @Query("SELECT * FROM sync_conflict_record WHERE id = :id LIMIT 1")
    suspend fun getById(id: Long): SyncConflictRecord?

    @Query("SELECT COUNT(*) FROM sync_conflict_record WHERE status = :status")
    suspend fun countByStatus(status: String): Int
}
