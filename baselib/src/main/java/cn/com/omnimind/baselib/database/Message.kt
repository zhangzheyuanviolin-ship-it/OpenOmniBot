package cn.com.omnimind.baselib.database

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.Date
import java.util.UUID

@Entity(
    tableName = "messages",
    indices = [Index(value = ["syncId"], unique = true)]
)
data class Message(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val syncId: String = UUID.randomUUID().toString(),
    val messageId: String ,//消息ID
    val type: Int,//1普通消息 2卡片消息
    val user: Int,//1用户 2机器人 3系统
    val content: String,
    val createdAt: Long = Date().time,
    val updatedAt: Long = Date().time,
)

data class PagedMessagesResult(
    val messageList: List<Message>,
    val hasMore: Boolean
)
