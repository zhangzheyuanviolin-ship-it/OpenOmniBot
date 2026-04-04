// Created by ruoyi.sjd on 2025/5/14.
// Copyright (c) 2024 Alibaba Group Holding Limited All rights reserved.

package com.alibaba.mls.api.ml

import androidx.annotation.Keep

@Keep
data class MlRepoInfo(
    val code: String,
    val msg: String,
    val data: MlRepoData
)

@Keep
data class MlRepoData(
    val tree: List<FileInfo>,
    val last_commit: LastCommitInfo?,
    val commit_count: Int
)

@Keep
data class FileInfo(
    val name: String,
    val path: String,
    val type: String,
    val size: Long,
    val is_lfs: Boolean,
    val etag: String,
    val url: String,
    val commit: CommitInfo?,
    val file_scan: FileScanInfo?
)

@Keep
data class CommitInfo(
    val message: String,
    val commit_sha: String,
    //2025-07-16T11:54:27Z
    val created: String
)

@Keep
data class FileScanInfo(
    val status: String,
    val virus: String,
    val sensitive_item: String,
    val moderation_status: String,
    val moderation_result: String
)

@Keep
data class LastCommitInfo(
    val commit: CommitInfo?,
    val author: AuthorInfo?
)

@Keep
data class AuthorInfo(
    val name: String,
    val avatar_url: String
)
