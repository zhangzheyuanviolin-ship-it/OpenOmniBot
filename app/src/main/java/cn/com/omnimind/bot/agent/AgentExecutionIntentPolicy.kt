package cn.com.omnimind.bot.agent

object AgentExecutionIntentPolicy {
    private val pseudoToolMarkupRegex = Regex(
        pattern = """<\s*/?\s*tool_call\b|<\s*function=|<\s*/\s*function\s*>|<\s*parameter=""",
        options = setOf(RegexOption.IGNORE_CASE)
    )

    private val strongExecutionKeywords = listOf(
        "vlm",
        "mcp",
        "memory",
        "subagent",
        "terminal",
        "schedule",
        "alarm",
        "calendar",
        "终端",
        "命令行",
        "定时",
        "提醒",
        "闹钟",
        "日历",
        "日程",
        "会议",
        "分钟后",
        "小时后",
        "每天",
        "每周",
        "记住",
        "记忆",
        "保存偏好",
        "播放",
        "搜一下",
        "搜个",
        "搜首",
        "发消息",
        "导航到"
    )

    private val actionKeywords = listOf(
        "执行",
        "操作",
        "打开",
        "点击",
        "进入",
        "启动",
        "播放",
        "搜索",
        "查找",
        "发送",
        "创建",
        "删除",
        "修改",
        "设置",
        "run ",
        "open ",
        "click "
    )

    private val instructionKeywords = listOf(
        "帮我",
        "请",
        "麻烦",
        "替我",
        "给我",
        "现在",
        "立刻"
    )

    private val knowledgeQuestionKeywords = listOf(
        "是什么",
        "什么意思",
        "为什么",
        "如何",
        "怎么",
        "介绍",
        "解释",
        "推荐",
        "原理"
    )

    fun isExecutionIntent(userMessage: String): Boolean {
        val text = userMessage.trim().lowercase()
        if (text.isBlank()) return false
        if (containsPseudoToolMarkup(text)) {
            return true
        }
        if (strongExecutionKeywords.any { text.contains(it) }) {
            return true
        }
        val hasAction = actionKeywords.any { text.contains(it) }
        val isKnowledgeQuestion = knowledgeQuestionKeywords.any { text.contains(it) }
        if (!hasAction || isKnowledgeQuestion) {
            return false
        }
        val hasInstruction = instructionKeywords.any { text.contains(it) }
        return hasInstruction || !text.endsWith("吗") && !text.endsWith("?") && !text.endsWith("？")
    }

    fun shouldRetryNoToolCall(
        executionIntent: Boolean,
        toolExecutionCount: Int,
        retryCount: Int,
        maxRetries: Int
    ): Boolean {
        return executionIntent &&
            toolExecutionCount == 0 &&
            retryCount < maxRetries
    }

    fun shouldFailNoToolCall(
        executionIntent: Boolean,
        toolExecutionCount: Int,
        retryCount: Int,
        maxRetries: Int
    ): Boolean {
        return executionIntent &&
            toolExecutionCount == 0 &&
            retryCount >= maxRetries
    }

    fun containsPseudoToolMarkup(text: String): Boolean {
        return text.isNotBlank() && pseudoToolMarkupRegex.containsMatchIn(text)
    }
}
