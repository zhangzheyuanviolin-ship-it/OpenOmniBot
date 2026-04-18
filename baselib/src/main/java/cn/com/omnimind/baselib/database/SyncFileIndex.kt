package cn.com.omnimind.baselib.database

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "sync_file_index",
    indices = [Index(value = ["relativePath"], unique = true)]
)
data class SyncFileIndex(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val relativePath: String,
    val contentHash: String,
    val sizeBytes: Long,
    val lastModifiedAt: Long,
    val objectKey: String = "",
    val status: String = "ready",
    val updatedAt: Long = System.currentTimeMillis()
)
