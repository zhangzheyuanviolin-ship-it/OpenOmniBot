package cn.com.omnimind.baselib.database

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.Date
import java.util.UUID

@Entity(
    tableName = "study_records",
    indices = [Index(value = ["syncId"], unique = true)]
)
data class StudyRecord(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val syncId: String = UUID.randomUUID().toString(),
    val title: String,
    val suggestionId: String,
    val appName: String,
    val packageName: String,
    val createdAt: Long = Date().time,
    val updatedAt: Long = Date().time,
    val isFavorite: Boolean = false
)
