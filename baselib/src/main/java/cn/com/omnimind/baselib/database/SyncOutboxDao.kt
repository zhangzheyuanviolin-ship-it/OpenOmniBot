package cn.com.omnimind.baselib.database

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update

@Dao
interface SyncOutboxDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entry: SyncOutbox): Long

    @Update
    suspend fun update(entry: SyncOutbox)

    @Query(
        """
        SELECT * FROM sync_outbox
        WHERE nextRetryAt <= :now
        ORDER BY createdAt ASC, id ASC
        LIMIT :limit
        """
    )
    suspend fun listReady(now: Long, limit: Int): List<SyncOutbox>

    @Query(
        """
        SELECT * FROM sync_outbox
        WHERE docType = :docType AND docSyncId = :docSyncId
        ORDER BY updatedAt DESC, id DESC
        LIMIT 1
        """
    )
    suspend fun getLatestForDocument(docType: String, docSyncId: String): SyncOutbox?

    @Query("DELETE FROM sync_outbox WHERE id = :id")
    suspend fun deleteById(id: Long)

    @Query("DELETE FROM sync_outbox WHERE docType = :docType AND docSyncId = :docSyncId")
    suspend fun deleteByDocument(docType: String, docSyncId: String)

    @Query("SELECT COUNT(*) FROM sync_outbox")
    suspend fun countAll(): Int

    @Query("DELETE FROM sync_outbox")
    suspend fun deleteAll()
}
