package cn.com.omnimind.bot.agent

object AgentSystemPrompt {
    fun build(
        workspace: AgentWorkspaceDescriptor,
        installedSkills: List<SkillIndexEntry>,
        skillsRootShellPath: String,
        skillsRootAndroidPath: String,
        resolvedSkills: List<ResolvedSkillContext>,
        memoryContext: WorkspaceMemoryPromptContext?
    ): String {
        val visibleInstalledSkills = installedSkills.filter { skill ->
            skill.installed &&
                skill.enabled &&
                SkillCompatibilityChecker.evaluate(skill).available
        }
        val installedSkillSection = if (visibleInstalledSkills.isEmpty()) {
            "当前未安装额外 skills。"
        } else {
            buildString {
                appendLine("已安装 skills 索引：")
                visibleInstalledSkills.forEach { skill ->
                    val description = skill.description
                        .replace(Regex("\\s+"), " ")
                        .trim()
                        .ifBlank { "无描述" }
                        .let { text ->
                            if (text.length <= 160) text else text.take(160) + "..."
                        }
                    val capabilities = buildList {
                        if (skill.hasScripts) add("scripts")
                        if (skill.hasReferences) add("references")
                        if (skill.hasAssets) add("assets")
                        if (skill.hasEvals) add("evals")
                    }.joinToString(", ").ifBlank { "metadata-only" }
                    appendLine(
                        "- id=${skill.id} | name=${skill.name} | path=${skill.shellSkillFilePath} | capabilities=$capabilities | description=$description"
                    )
                }
            }.trim()
        }
        val loadedSkillSection = if (resolvedSkills.isEmpty()) {
            "当前未命中额外 skill，因此本轮没有注入任何 skill 正文。"
        } else {
            buildString {
                appendLine("当前已加载的 skills 正文：")
                resolvedSkills.forEach { skill ->
                    appendLine("- ${skill.promptSummary(1200)}")
                }
            }.trim()
        }
        val soulSection = memoryContext?.soul
            ?.takeIf { it.isNotBlank() }
            ?.let {
                """
                Agent 灵魂（来自 `.omnibot/agent/SOUL.md`）：
                $it
                """.trimIndent()
            } ?: "未读取到 SOUL.md，请按默认安全策略执行。"

        val memorySection = memoryContext?.let { context ->
            buildString {
                appendLine("Workspace 记忆上下文（来自 `.omnibot/memory`）：")
                appendLine("- 长期记忆（MEMORY.md）：")
                appendLine(context.longTermMemory.ifBlank { "（为空）" })
                appendLine("- 今日短期记忆摘要（short-memories）：")
                appendLine(context.todayShortMemory.ifBlank { "（为空）" })
            }.trim()
        } ?: "Workspace 记忆未加载，本轮按无记忆上下文执行。"

        return """
            你是在 Alpine 工作环境内的 AI Agent，你同时能通过工具调用操作用户的手机 。

            
        """.trimIndent()
    }
}
