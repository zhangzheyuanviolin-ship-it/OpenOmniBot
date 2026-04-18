package cn.com.omnimind.baselib.database

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "sync_conflict_record",
    indices = [Index(value = ["status"]), Index(value = ["relativePath"])]
)
data class SyncConflictRecord(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val relativePath: String,
    val localHash: String = "",
    val remoteHash: String = "",
    val remoteObjectKey: String = "",
    val conflictCopyPath: String = "",
    val status: String = "open",
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis()
)
