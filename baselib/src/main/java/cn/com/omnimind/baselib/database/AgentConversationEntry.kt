package cn.com.omnimind.baselib.database

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.Date
import java.util.UUID

@Entity(
    tableName = "agent_conversation_entries",
    indices = [
        Index(value = ["syncId"], unique = true),
        Index(
            value = ["conversationId", "conversationMode", "entryId"],
            unique = true
        ),
        Index(value = ["conversationId", "conversationMode", "updatedAt"])
    ]
)
data class AgentConversationEntry(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val syncId: String = UUID.randomUUID().toString(),
    val conversationId: Long,
    val conversationMode: String,
    val entryId: String,
    val entryType: String,
    val status: String,
    val summary: String,
    val payloadJson: String,
    val createdAt: Long = Date().time,
    val updatedAt: Long = Date().time
)
