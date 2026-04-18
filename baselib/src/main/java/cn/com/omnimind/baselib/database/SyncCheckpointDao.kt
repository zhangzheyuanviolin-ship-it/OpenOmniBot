package cn.com.omnimind.baselib.database

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface SyncCheckpointDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entry: SyncCheckpoint)

    @Query("SELECT * FROM sync_checkpoint WHERE checkpointKey = :checkpointKey LIMIT 1")
    suspend fun getByKey(checkpointKey: String): SyncCheckpoint?
}
