package cn.com.omnimind.baselib.database

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "sync_checkpoint")
data class SyncCheckpoint(
    @PrimaryKey
    val checkpointKey: String,
    val remoteCursor: Long = 0,
    val lastSuccessfulSyncAt: Long = 0,
    val lastMetadataSyncAt: Long = 0,
    val lastFileScanAt: Long = 0,
    val lastSettingsHash: String = "",
    val updatedAt: Long = System.currentTimeMillis()
)
