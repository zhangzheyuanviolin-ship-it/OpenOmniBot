package cn.com.omnimind.baselib.database

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

@Entity(
    tableName = "sync_outbox",
    indices = [
        Index(value = ["opId"], unique = true),
        Index(value = ["nextRetryAt"]),
        Index(value = ["docType", "docSyncId"])
    ]
)
data class SyncOutbox(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val opId: String = UUID.randomUUID().toString(),
    val docType: String,
    val docSyncId: String,
    val opType: String,
    val payloadJson: String,
    val contentHash: String = "",
    val attempts: Int = 0,
    val nextRetryAt: Long = 0,
    val lastError: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis()
)
