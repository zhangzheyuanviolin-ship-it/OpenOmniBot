package cn.com.omnimind.assists.task.vlmserver

import cn.com.omnimind.assists.util.TimeUtil
import cn.com.omnimind.baselib.llm.ModelSceneRegistry

/**
 * 主 VLM prompt 构造器：
 * - system: 稳定规则、工具协议、GUI 操作规范
 * - user: 当前轮动态上下文 + 当前截图
 */
object PromptTemplate {
    fun getPrompt(context: UIContext, sceneId: String? = null): String {
        return buildTurnUserPrompt(context, sceneId)
    }

    fun buildSystemPrompt(sceneId: String? = null): String {
        val resolvedSceneId = if (sceneId.isNullOrBlank()) {
            "scene.vlm.operation.primary"
        } else {
            sceneId
        }
        val runtimeProfile = ModelSceneRegistry.getRuntimeProfile(resolvedSceneId)
        val parser = runtimeProfile?.responseParser ?: ModelSceneRegistry.ResponseParser.TEXT_CONTENT
        val template = ModelSceneRegistry.getPrompt(resolvedSceneId)
            ?: ModelSceneRegistry.getPrompt("scene.vlm.operation.primary")
            ?: throw IllegalStateException("scene.vlm.operation.primary prompt not found")

        val responseContract = if (parser == ModelSceneRegistry.ResponseParser.OPENAI_TOOL_ACTIONS) {
            VLMToolDefinitions.responseContract()
        } else {
            ""
        }

        return ModelSceneRegistry.renderPrompt(
            template,
            mapOf(
                "priorityEvent" to "若后续 user 消息包含紧急事件，请优先处理。",
                "overallTask" to "见后续 user 消息",
                "currentStepGoal" to "见后续 user 消息",
                "stepSkillGuidance" to "见后续 user 消息",
                "summaryHistory" to "见后续 user 消息",
                "currentState" to "见后续 user 消息",
                "nextStepHint" to "见后续 user 消息",
                "completedMilestones" to "见后续 user 消息",
                "keyMemory" to "见后续 user 消息",
                "installedApps" to "见后续 user 消息",
                "currentTime" to "见后续 user 消息",
                "responseContract" to responseContract
            )
        )
    }

    fun buildTurnUserPrompt(context: UIContext, sceneId: String? = null): String {
        val resolvedSceneId = if (sceneId.isNullOrBlank()) {
            "scene.vlm.operation.primary"
        } else {
            sceneId
        }
        val summaryHistory = if (context.runningSummary.isNotEmpty()) {
            context.runningSummary
        } else if (context.trace.isNotEmpty()) {
            context.trace.last().summary
        } else {
            "暂无历史操作"
        }
        val installedApps = if (context.installedApplications.isNotEmpty()) {
            context.installedApplications.entries.joinToString("\n") { (packageName, appName) ->
                "- ${packageName} -> ${appName}"
            }
        } else {
            "暂无数据"
        }
        val completedMilestones = if (context.completedMilestones.isNotEmpty()) {
            context.completedMilestones.joinToString("、")
        } else {
            "暂无"
        }
        val keyMemory = if (context.keyMemory.isNotEmpty()) {
            context.keyMemory.joinToString("；")
        } else {
            "暂无"
        }
        val priorityEventSection = if (context.priorityEvent != null) {
            buildString {
                appendLine("【紧急事件】")
                appendLine(context.priorityEvent)
                if (context.suggestCompletion) {
                    appendLine("如果已经确认任务完成，请尽快调用 finished 工具结束任务。")
                }
                appendLine()
            }.trim()
        } else {
            ""
        }

        return buildString {
            appendLine("以下是当前这一轮的动态上下文，请结合当前截图选择下一步动作。")
            appendLine("场景：$resolvedSceneId")
            appendLine("当前时间：${TimeUtil.getCurrentTimeString()}")
            appendLine("用户任务：${context.overallTask}")
            appendLine("当前子目标：${context.activeGoal()}")
            appendLine("技能提示：${context.stepSkillGuidance.ifEmpty { "无" }}")
            if (priorityEventSection.isNotBlank()) {
                appendLine(priorityEventSection)
            }
            appendLine("当前状态：${context.currentState.ifEmpty { "未知" }}")
            appendLine("建议下一步：${context.nextStepHint.ifEmpty { "无" }}")
            appendLine("已完成里程碑：$completedMilestones")
            appendLine("关键记忆：$keyMemory")
            appendLine("历史总结：$summaryHistory")
            appendLine("已安装应用：$installedApps")
            appendLine()
            appendLine("输出要求：")
            appendLine("1. 直接从 tools 列表中选择下一步动作，每轮只调用一个工具。")
            appendLine("2. click/long_press 只填 x、y；scroll 只填 x1、y1、x2、y2；每个坐标字段都必须是单个数值。")
            appendLine("3. assistant.content 只写 observation/thought/summary 元信息；只有真正完成任务时才调用 finished。")
            appendLine("4. 只要返回 package_name 或 open_app.package_name，必须从上面的已安装应用列表中原样选择一个 package name；禁止猜测常见默认包名。")
            appendLine("5. 如果目标应用有多个候选，优先使用已安装列表里的精确 package；例如联系人若存在 com.google.android.contacts，就必须使用它，不要改成 com.android.contacts。")
            appendLine("6. 如果当前任务需要打开某个应用，但已安装应用列表里没有明确 package，就不要猜；改用 info/feedback 请求更多信息或先通过界面观察确认。")
        }.trim()
    }

    fun buildToolCallRetryPrompt(context: UIContext, retryState: VLMToolCallRetryState): String {
        val thinking = retryState.thinking
        return buildString {
            val failureReason = retryState.failureReason?.trim().orEmpty()
            if (failureReason.isNotEmpty()) {
                appendLine("系统检查到你上一轮的 tool_call 参数不合规：$failureReason")
            } else {
                appendLine("系统检查到你上一轮没有返回标准 tool_calls，但当前任务仍是执行型 GUI 自动化。")
            }
            appendLine("请在本轮严格返回一个原生 tool_call，并从 tools 列表中选择下一步动作。")
            appendLine("不要只输出 observation/thought/summary JSON，不要在 assistant.content 中写动作参数，也不要提前宣布任务完成。")
            appendLine("只有当用户目标已经真正完成时，才能调用 finished。")
            appendLine("若你判断下一步是点击、输入、滑动、返回、等待或结束，请直接使用对应工具。")
            appendLine("若需要坐标，必须分别写入 x/y 或 x1/y1/x2/y2；每个字段都只能是单个数值，不要返回 [x,y]、coordinates 或对象。")
            appendLine("本次为第 ${retryState.retryIndex} 次协议纠偏。")
            appendLine("用户原始任务：${context.overallTask}")
            appendLine("当前子目标：${context.activeGoal()}")
            thinking.finishReason?.takeIf { it.isNotBlank() }?.let {
                appendLine("上一轮 finish_reason：$it")
            }
            thinking.observation.takeIf { it.isNotBlank() }?.let {
                appendLine("上一轮 observation：${truncateForRetry(it)}")
            }
            thinking.thought.takeIf { it.isNotBlank() }?.let {
                appendLine("上一轮 thought：${truncateForRetry(it)}")
            }
            thinking.summary.takeIf { it.isNotBlank() }?.let {
                appendLine("上一轮 summary：${truncateForRetry(it)}")
            }
            thinking.reasoning.takeIf { it.isNotBlank() }?.let {
                appendLine("上一轮 reasoning_content：${truncateForRetry(it, maxLen = 900)}")
            }
        }.trim()
    }

    private fun truncateForRetry(text: String, maxLen: Int = 280): String {
        val normalized = text.replace("\r\n", "\n").trim()
        return if (normalized.length <= maxLen) normalized else normalized.take(maxLen) + "..."
    }
}
