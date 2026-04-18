package cn.com.omnimind.baselib.database

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.Date
import java.util.UUID

@Entity(
    tableName = "favorite_records",
    indices = [Index(value = ["syncId"], unique = true)]
)
data class FavoriteRecord(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val syncId: String = UUID.randomUUID().toString(),
    val title: String,
    val desc: String,
    val type: String,
    val imagePath: String,
    val packageName: String = "",  // 添加默认值
    val status: Int = 0, // 0为识别中,1为识别成功,2为识别失败
    val createdAt: Long = Date().time,
    val updatedAt: Long = Date().time
)
