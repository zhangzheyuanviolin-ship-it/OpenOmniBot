package cn.com.omnimind.baselib.database

import androidx.room.Entity
import androidx.room.PrimaryKey
import java.util.Date

@Entity(tableName = "conversations")
data class Conversation(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,

    // 对话标题（用户可编辑）
    val title: String,

    // 对话模式
    val mode: String = "normal",

    // 对话摘要（AI生成，6个字左右）
    val summary: String? = null,

    // 对话状态
    val status: Int = 0, // 0: 进行中, 1: 已完成

    // 最后一条消息内容
    val lastMessage: String? = null,

    // 消息数量
    val messageCount: Int = 0,

    // 创建时间
    val createdAt: Long = Date().time,

    // 更新时间
    val updatedAt: Long = Date().time
)
