package cn.com.omnimind.baselib.database

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update

@Dao
interface SyncFileIndexDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entry: SyncFileIndex): Long

    @Update
    suspend fun update(entry: SyncFileIndex)

    @Query("SELECT * FROM sync_file_index")
    suspend fun getAll(): List<SyncFileIndex>

    @Query("SELECT * FROM sync_file_index WHERE relativePath = :relativePath LIMIT 1")
    suspend fun getByRelativePath(relativePath: String): SyncFileIndex?

    @Query("DELETE FROM sync_file_index WHERE relativePath = :relativePath")
    suspend fun deleteByRelativePath(relativePath: String)

    @Query("DELETE FROM sync_file_index")
    suspend fun deleteAll()
}
