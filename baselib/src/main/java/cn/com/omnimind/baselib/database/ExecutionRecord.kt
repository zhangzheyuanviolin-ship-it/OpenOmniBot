package cn.com.omnimind.baselib.database

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.Date
import java.util.UUID

@Entity(
    tableName = "execution_records",
    indices = [Index(value = ["syncId"], unique = true)]
)
data class ExecutionRecord(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val syncId: String = UUID.randomUUID().toString(),
    val title: String,
    val appName: String,
    val packageName: String,
    val nodeId: String,                 //  标识suggestion
    val suggestionId: String,           //  标识suggestion
    val iconUrl: String? = null,        //  suggestion 图标 URL（相同的suggestion会取最新的记录展示, 学习技能为空即可）
    val type: String = "unknown",       //   system: 系统任务, learning: 学习任务, vlm: 普通vlm任务, summary: 总结任务, unknown: 未知类型
    val content: String? = null,        //   总结任务的 Markdown 内容
    val status: String = "running",     //   running: 执行中, success: 执行成功, failed: 执行失败, cancelled: 用户取消, waiting: 等待用户输入, paused: 用户暂停
    val createdAt: Long = Date().time,
    val updatedAt: Long = Date().time
)
