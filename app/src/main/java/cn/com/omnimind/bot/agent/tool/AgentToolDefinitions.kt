package cn.com.omnimind.bot.agent

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.add
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

object AgentToolDefinitions {
    private const val TOOL_TITLE_FIELD = "tool_title"
    private const val TOOL_TITLE_RULE =
        "调用时必须提供 tool_title，作为展示给用户的简洁标题，建议 4-12 个字并使用与用户相同的语言。"

    private fun toolTitlePropertySchema(): JsonObject = buildJsonObject {
        put("type", "string")
        put("description", "本次工具调用要做什么的简洁标题，展示给用户，建议 4-12 个字并使用与用户相同的语言。")
    }

    private fun ensureToolTitleDescription(description: String): String {
        val trimmed = description.trim()
        if (trimmed.contains(TOOL_TITLE_FIELD)) {
            return trimmed
        }
        if (trimmed.isEmpty()) {
            return TOOL_TITLE_RULE
        }
        return "$trimmed $TOOL_TITLE_RULE"
    }

    fun decorateParameterSchema(parameters: JsonObject): JsonObject {
        val properties = (parameters["properties"] as? JsonObject) ?: JsonObject(emptyMap())
        val required = (parameters["required"] as? JsonArray)
            ?.mapNotNull { it.jsonPrimitive.contentOrNull?.trim() }
            ?.filter { it.isNotEmpty() }
            ?.toMutableList()
            ?: mutableListOf()

        val updatedProperties = buildJsonObject {
            put(TOOL_TITLE_FIELD, toolTitlePropertySchema())
            properties.forEach { (key, value) ->
                if (key != TOOL_TITLE_FIELD) {
                    put(key, value)
                }
            }
        }

        if (!required.contains(TOOL_TITLE_FIELD)) {
            required.add(0, TOOL_TITLE_FIELD)
        }

        return buildJsonObject {
            parameters.forEach { (key, value) ->
                when (key) {
                    "properties" -> put("properties", updatedProperties)
                    "required" -> {
                        put(
                            "required",
                            buildJsonArray {
                                required.forEach { add(JsonPrimitive(it)) }
                            }
                        )
                    }

                    else -> put(key, value)
                }
            }
            if (parameters["properties"] == null) {
                put("properties", updatedProperties)
            }
            if (parameters["required"] == null) {
                put(
                    "required",
                    buildJsonArray {
                        required.forEach { add(JsonPrimitive(it)) }
                    }
                )
            }
        }
    }

    fun decorateToolDefinition(definition: JsonObject): JsonObject {
        val function = definition["function"] as? JsonObject ?: return definition
        val parameters = (function["parameters"] as? JsonObject) ?: buildJsonObject {
            put("type", "object")
            put("properties", JsonObject(emptyMap()))
        }

        return buildJsonObject {
            definition.forEach { (key, value) ->
                if (key != "function") {
                    put(key, value)
                }
            }
            put(
                "function",
                buildJsonObject {
                    function.forEach { (key, value) ->
                        when (key) {
                            "description" -> put(
                                "description",
                                ensureToolTitleDescription(
                                    value.jsonPrimitive.contentOrNull.orEmpty()
                                )
                            )

                            "parameters" -> put(
                                "parameters",
                                decorateParameterSchema(parameters)
                            )

                            else -> put(key, value)
                        }
                    }
                    if (function["description"] == null) {
                        put("description", TOOL_TITLE_RULE)
                    }
                    if (function["parameters"] == null) {
                        put("parameters", decorateParameterSchema(parameters))
                    }
                }
            )
        }
    }

    val contextAppsQueryTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "context_apps_query")
            put("displayName", "查询已安装应用")
            put("toolType", "builtin")
            put("description", "查询设备已安装应用列表。需要应用包名或确认应用是否已安装时优先调用。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("query") {
                        put("type", "string")
                        put("description", "可选关键词，可匹配应用名或包名。")
                    }
                    putJsonObject("limit") {
                        put("type", "integer")
                        put("description", "可选，返回数量上限，默认 20，范围 1-100。")
                    }
                }
            }
        }
    }

    val contextTimeNowTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "context_time_now")
            put("displayName", "查询当前时间")
            put("toolType", "builtin")
            put("description", "查询当前时间信息。需要日期、时间、时区或星期信息时调用。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("timezone") {
                        put("type", "string")
                        put("description", "可选 IANA 时区，例如 Asia/Shanghai、America/Los_Angeles。默认使用系统时区。")
                    }
                }
            }
        }
    }

    val vlmTaskTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "vlm_task")
            put("displayName", "视觉执行")
            put("toolType", "builtin")
            put(
                "description",
                "使用视觉语言模型执行手机屏幕操作任务。该工具会阻塞等待到任务完成、需要用户输入、屏幕锁定或超时，再把终态结果返回给模型。若需要最终整理文本，必须设置 needSummary=true。"
            )
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("goal") {
                        put("type", "string")
                        put("description", "任务目标，使用第一人称描述。")
                    }
                    putJsonObject("packageName") {
                        put("type", "string")
                        put("description", "目标应用包名。")
                    }
                    putJsonObject("needSummary") {
                        put("type", "boolean")
                        put("description", "是否在结束后生成总结。设为 true 时，工具结果会尽量直接返回最终整理文本。")
                    }
                    putJsonObject("startFromCurrent") {
                        put("type", "boolean")
                        put("description", "仅在用户明确要求从当前页面继续时设为 true。")
                    }
                }
                putJsonArray("required") {
                    add("goal")
                }
            }
        }
    }

    val terminalExecuteTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "terminal_execute")
            put("displayName", "终端执行")
            put("toolType", "terminal")
            put(
                "description",
                "通过应用内置的 Alpine（proot）环境执行一次性的非交互终端命令。这是默认首选的终端工具，适合文件处理、脚本、网络诊断、git、python、包管理等绝大多数 CLI 任务；不用于手机界面操作，也不用于交互式 TUI。只有明确需要跨多轮保留 cwd、环境或后台进程时，才改用 terminal_session_*。"
            )
            put(
                "postToolRule",
                "terminal_execute 应单独占据当前 tool_calls。该工具会固定在 executionMode=proot（prootDistro=alpine）执行，传入 termux/debian 等参数会被忽略。若执行失败，可在下一轮基于 stdout/stderr/errorMessage 自行决定是否再次显式调用 terminal_execute；不要在同一个 tool_calls 中串联其他结果依赖型工具。"
            )
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("command") {
                        put("type", "string")
                        put("description", "要执行的单次 shell 命令，必须非交互。")
                    }
                    putJsonObject("executionMode") {
                        put("type", "string")
                        put("description", "可选。兼容字段，当前固定在 proot Alpine 执行，传入 termux 也会被自动忽略。")
                        putJsonArray("enum") {
                            add("proot")
                            add("termux")
                        }
                    }
                    putJsonObject("prootDistro") {
                        put("type", "string")
                        put("description", "可选。兼容字段，当前固定使用 alpine，传入其他 distro 会被自动忽略。")
                    }
                    putJsonObject("workingDirectory") {
                        put("type", "string")
                        put("description", "可选工作目录，建议使用绝对路径。")
                    }
                    putJsonObject("timeoutSeconds") {
                        put("type", "integer")
                        put("description", "等待结果的超时时间，默认 60 秒，范围 5-300。")
                    }
                }
                putJsonArray("required") {
                    add("command")
                }
            }
        }
    }

    val terminalSessionStartTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "terminal_session_start")
            put("displayName", "启动终端会话")
            put("toolType", "terminal")
            put("description", "启动一个可复用的 Alpine 终端会话，仅用于确实需要在后续多轮中保留 cwd、shell 环境、中间文件状态或后台进程的任务。返回的 sessionId 由底层 ReTerminal 原生生成并持久托管，后续必须显式传给 terminal_session_exec/read/stop。不要为了运行单条命令、检查工具是否存在、读取单个文件或执行一次性脚本而使用它，这些场景应优先用 terminal_execute。")
            put("postToolRule", "启动后等待工具结果，再决定是否继续向该 session 发送命令。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("sessionName") {
                        put("type", "string")
                        put("description", "可选，会话名称。未传时自动生成。")
                    }
                    putJsonObject("workingDirectory") {
                        put("type", "string")
                        put("description", "可选，会话初始工作目录。默认使用当前 workspace cwd。")
                    }
                }
            }
        }
    }

    val terminalSessionExecTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "terminal_session_exec")
            put("displayName", "执行会话命令")
            put("toolType", "terminal")
            put("description", "向已有终端 session 发送一条非交互命令，并等待该命令完成。只在你明确想复用同一个 session 的 cwd、环境变量、后台任务或中间状态时使用。若命令会持续运行很久（例如启动 node/python 服务），应设置较短 timeoutSeconds，让工具尽快返回，再用 terminal_session_read 追踪输出，并在不再需要时调用 terminal_session_stop。")
            put("postToolRule", "执行后等待结果，再判断是否继续读取日志、再次执行或结束 session。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("sessionId") {
                        put("type", "string")
                        put("description", "terminal_session_start 返回的 sessionId。")
                    }
                    putJsonObject("command") {
                        put("type", "string")
                        put("description", "要执行的单次非交互 shell 命令。")
                    }
                    putJsonObject("workingDirectory") {
                        put("type", "string")
                        put("description", "可选，本次命令执行前要切换到的目录。")
                    }
                    putJsonObject("timeoutSeconds") {
                        put("type", "integer")
                        put("description", "等待该命令完成的超时时间，默认 120 秒，范围 5-600。")
                    }
                }
                putJsonArray("required") {
                    add("sessionId")
                    add("command")
                }
            }
        }
    }

    val terminalSessionReadTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "terminal_session_read")
            put("displayName", "读取会话输出")
            put("toolType", "terminal")
            put("description", "读取终端 session 最近一次命令日志或最近的终端输出。默认应把它视为读取该 session 最新尾部输出，而不是重新查看最早的历史。只在已经启动并复用了 terminal_session_* 的前提下使用。")
            put("postToolRule", "读取结果后再决定是否继续执行命令。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("sessionId") {
                        put("type", "string")
                        put("description", "terminal session id。")
                    }
                    putJsonObject("maxChars") {
                        put("type", "integer")
                        put("description", "最多返回多少字符，默认 4000，范围 256-64000。")
                    }
                }
                putJsonArray("required") {
                    add("sessionId")
                }
            }
        }
    }

    val terminalSessionStopTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "terminal_session_stop")
            put("displayName", "结束终端会话")
            put("toolType", "terminal")
            put("description", "停止已有终端 session，并清理对应 tmux 会话。完成状态化终端任务后再调用。")
            put("postToolRule", "结束后等待工具结果，再回复用户。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("sessionId") {
                        put("type", "string")
                        put("description", "terminal session id。")
                    }
                }
                putJsonArray("required") {
                    add("sessionId")
                }
            }
        }
    }

    val browserUseTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "browser_use")
            put("displayName", "浏览器操作")
            put("toolType", "browser")
            put(
                "description",
                "控制一个最多 3 个标签页的离屏浏览器。不要用它打开 App deep link、omnibot:// 非 browser 资源或应用内路由。浏览器只支持访问 http(s) 页面，以及 omnibot://browser/... 资源文件。使用 navigate 打开页面，screenshot 查看当前视口截图（传 read_image=true 可让模型直接看到截图内容），click/type/hover 与元素交互，get_text/get_readable 抽取内容，scroll 导航长页面，scroll_and_collect 在一次调用中滚动并收集无限列表内容，find_elements 发现可交互元素，get_page_info 获取页面元信息，get_backbone 获取 DOM 骨架，execute_js 执行脚本，fetch 复用当前页面 session 下载资源并返回 omnibot://browser/... 产物，new_tab/close_tab/list_tabs 管理标签页，go_back/go_forward 浏览器前进后退，press_key 模拟键盘按键，wait_for_selector 等待元素出现，get_cookies 返回 cookie 摘要与可复用的 offload env 脚本路径，set_user_agent 切换 desktop_safari 或 mobile_safari。tool_title 必须是 5-10 个字的简洁摘要，并使用与用户相同的语言。"
            )
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("tool_title") {
                        put("type", "string")
                        put("description", "本次工具调用要做什么的简洁摘要，5-10 个字，展示给用户。")
                    }
                    putJsonObject("action") {
                        put("type", "string")
                        put("description", "浏览器动作。")
                        putJsonArray("enum") {
                            add("navigate")
                            add("screenshot")
                            add("click")
                            add("type")
                            add("get_text")
                            add("scroll")
                            add("get_page_info")
                            add("execute_js")
                            add("find_elements")
                            add("hover")
                            add("get_readable")
                            add("set_user_agent")
                            add("get_backbone")
                            add("fetch")
                            add("new_tab")
                            add("close_tab")
                            add("list_tabs")
                            add("get_cookies")
                            add("scroll_and_collect")
                            add("go_back")
                            add("go_forward")
                            add("press_key")
                            add("wait_for_selector")
                        }
                    }
                    putJsonObject("url") {
                        put("type", "string")
                        put("description", "navigate 打开的 URL，或 fetch 下载的资源 URL。")
                    }
                    putJsonObject("selector") {
                        put("type", "string")
                        put("description", "CSS selector。适用于 click/type/get_text/scroll/hover/find_elements。")
                    }
                    putJsonObject("text") {
                        put("type", "string")
                        put("description", "type 动作要输入的文本。")
                    }
                    putJsonObject("script") {
                        put("type", "string")
                        put("description", "execute_js 动作要执行的 JavaScript 代码。")
                    }
                    putJsonObject("coordinate_x") {
                        put("type", "integer")
                        put("description", "点击或输入目标的 X 坐标，可替代 selector。")
                    }
                    putJsonObject("coordinate_y") {
                        put("type", "integer")
                        put("description", "点击或输入目标的 Y 坐标，可替代 selector。")
                    }
                    putJsonObject("amount") {
                        put("type", "integer")
                        put("description", "滚动像素量，默认 500。")
                    }
                    putJsonObject("direction") {
                        put("type", "string")
                        put("description", "滚动方向。")
                        putJsonArray("enum") {
                            add("up")
                            add("down")
                        }
                    }
                    putJsonObject("tab_id") {
                        put("type", "integer")
                        put("description", "目标标签页 ID；不传时默认使用最近活跃标签页。")
                    }
                    putJsonObject("item_selector") {
                        put("type", "string")
                        put("description", "scroll_and_collect 的内容项 selector；不传时自动探测。")
                    }
                    putJsonObject("scroll_count") {
                        put("type", "integer")
                        put("description", "scroll_and_collect 的滚动次数，默认 10，最大 20。")
                    }
                    putJsonObject("max_depth") {
                        put("type", "integer")
                        put("description", "get_backbone 的最大深度，默认 5。")
                    }
                    putJsonObject("user_agent") {
                        put("type", "string")
                        put("description", "要切换到的 user agent profile。")
                        putJsonArray("enum") {
                            add("desktop_safari")
                            add("mobile_safari")
                        }
                    }
                    putJsonObject("keywords") {
                        put(
                            "description",
                            "get_cookies 的 cookie 名过滤关键词。可传空格分隔字符串，兼容数组字符串输入。fuzzy=true 时要求所有关键词都包含在 cookie 名中；fuzzy=false 时要求精确命中任一 cookie 名。"
                        )
                    }
                    putJsonObject("fuzzy") {
                        put("type", "boolean")
                        put("description", "get_cookies 的关键词匹配模式，默认 true。")
                    }
                    putJsonObject("read_image") {
                        put("type", "boolean")
                        put("description", "仅 screenshot 时生效。设为 true 时，截图会以 base64 图片嵌入工具结果，供模型直接分析页面内容。默认 false。")
                    }
                    putJsonObject("key") {
                        put("type", "string")
                        put("description", "press_key 动作要模拟的按键名，例如 Enter、Escape、Tab、ArrowDown。")
                    }
                    putJsonObject("timeout_ms") {
                        put("type", "integer")
                        put("description", "wait_for_selector 的超时毫秒数，默认 5000，范围 500-30000。")
                    }
                }
                putJsonArray("required") {
                    add("tool_title")
                    add("action")
                }
            }
        }
    }

    val fileReadTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "file_read")
            put("displayName", "读取文件")
            put("toolType", "workspace")
            put("description", "读取 workspace 或 Omnibot 白名单目录中的文件内容。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("path") {
                        put("type", "string")
                        put("description", "文件路径，可使用相对 workspace 路径或 omnibot:// uri。")
                    }
                    putJsonObject("maxChars") {
                        put("type", "integer")
                        put("description", "最多读取字符数，默认 8000，范围 128-64000。")
                    }
                    putJsonObject("offset") {
                        put("type", "integer")
                        put("description", "可选，从指定字符偏移开始读取。")
                    }
                    putJsonObject("lineStart") {
                        put("type", "integer")
                        put("description", "可选，从第几行开始读取，1-based。")
                    }
                    putJsonObject("lineCount") {
                        put("type", "integer")
                        put("description", "可选，读取多少行。")
                    }
                }
                putJsonArray("required") {
                    add("path")
                }
            }
        }
    }

    val fileWriteTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "file_write")
            put("displayName", "写入文件")
            put("toolType", "workspace")
            put("description", "创建或覆盖 workspace 内文件。新建文件优先使用此工具。")
            put("postToolRule", "写入后等待结果，再决定是否继续读取或修改。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("path") {
                        put("type", "string")
                        put("description", "目标文件路径。")
                    }
                    putJsonObject("content") {
                        put("type", "string")
                        put("description", "要写入的完整文本内容。")
                    }
                    putJsonObject("append") {
                        put("type", "boolean")
                        put("description", "是否追加写入，默认 false。")
                    }
                }
                putJsonArray("required") {
                    add("path")
                    add("content")
                }
            }
        }
    }

    val fileEditTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "file_edit")
            put("displayName", "编辑文件")
            put("toolType", "workspace")
            put("description", "对已有文件做精确字符串替换。修改现有文件优先使用此工具。")
            put("postToolRule", "编辑后等待结果，再判断是否继续读取验证。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("path") {
                        put("type", "string")
                        put("description", "目标文件路径。")
                    }
                    putJsonObject("oldText") {
                        put("type", "string")
                        put("description", "要替换的原始文本。")
                    }
                    putJsonObject("newText") {
                        put("type", "string")
                        put("description", "替换后的文本。")
                    }
                    putJsonObject("replaceAll") {
                        put("type", "boolean")
                        put("description", "是否替换全部匹配，默认 false。")
                    }
                }
                putJsonArray("required") {
                    add("path")
                    add("oldText")
                    add("newText")
                }
            }
        }
    }

    val fileListTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "file_list")
            put("displayName", "列出文件")
            put("toolType", "workspace")
            put("description", "列出某个目录下的文件和子目录。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("path") {
                        put("type", "string")
                        put("description", "目录路径。默认当前 workspace。")
                    }
                    putJsonObject("recursive") {
                        put("type", "boolean")
                        put("description", "是否递归列出。默认 false。")
                    }
                    putJsonObject("maxDepth") {
                        put("type", "integer")
                        put("description", "递归时最大深度，默认 2，范围 1-6。")
                    }
                    putJsonObject("limit") {
                        put("type", "integer")
                        put("description", "最多返回多少项，默认 200，范围 1-1000。")
                    }
                }
            }
        }
    }

    val fileSearchTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "file_search")
            put("displayName", "搜索文件")
            put("toolType", "workspace")
            put("description", "在目录中递归搜索文件名或文本内容。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("path") {
                        put("type", "string")
                        put("description", "搜索起始目录，默认当前 workspace。")
                    }
                    putJsonObject("query") {
                        put("type", "string")
                        put("description", "要搜索的关键词。")
                    }
                    putJsonObject("caseSensitive") {
                        put("type", "boolean")
                        put("description", "是否区分大小写，默认 false。")
                    }
                    putJsonObject("maxResults") {
                        put("type", "integer")
                        put("description", "最多返回结果数，默认 50，范围 1-200。")
                    }
                }
                putJsonArray("required") {
                    add("query")
                }
            }
        }
    }

    val fileStatTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "file_stat")
            put("displayName", "查看文件信息")
            put("toolType", "workspace")
            put("description", "查看文件或目录的元信息。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("path") {
                        put("type", "string")
                        put("description", "目标路径。")
                    }
                }
                putJsonArray("required") {
                    add("path")
                }
            }
        }
    }

    val fileMoveTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "file_move")
            put("displayName", "移动文件")
            put("toolType", "workspace")
            put("description", "移动或重命名 workspace 中的文件。")
            put("postToolRule", "移动后等待结果，再决定是否继续读取。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("sourcePath") {
                        put("type", "string")
                        put("description", "源路径。")
                    }
                    putJsonObject("targetPath") {
                        put("type", "string")
                        put("description", "目标路径。")
                    }
                    putJsonObject("overwrite") {
                        put("type", "boolean")
                        put("description", "是否覆盖目标文件，默认 false。")
                    }
                }
                putJsonArray("required") {
                    add("sourcePath")
                    add("targetPath")
                }
            }
        }
    }

    val skillsListTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "skills_list")
            put("displayName", "列出 Skills")
            put("toolType", "skill")
            put("description", "列出当前可用的 skills 索引，包括 id、名称、路径和能力目录。用户询问有哪些 skills、某类 skill 是否已安装，或你想先查目录再决定读取 SKILL.md 时优先调用。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("query") {
                        put("type", "string")
                        put("description", "可选关键词，匹配 skill id、名称、描述或路径。")
                    }
                    putJsonObject("limit") {
                        put("type", "integer")
                        put("description", "返回数量上限，默认 50，范围 1-200。")
                    }
                }
            }
        }
    }

    val skillsReadTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "skills_read")
            put("displayName", "读取 Skill")
            put("toolType", "skill")
            put("description", "按 skill id、名称或路径读取某个已安装 skill 的 SKILL.md 正文和相关目录信息。当你知道某个 skill 可能相关，但本轮只掌握索引信息时调用。")
            put("postToolRule", "读取 skill 后等待结果，再根据返回的正文、scripts、references、assets 路径决定下一步。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("skillId") {
                        put("type", "string")
                        put("description", "skill 的 id、名称、SKILL.md 路径或 skill 根目录路径。建议先用 skills_list 查看。")
                    }
                    putJsonObject("maxChars") {
                        put("type", "integer")
                        put("description", "最多返回多少字符的正文，默认 16000，范围 512-64000。")
                    }
                }
                putJsonArray("required") {
                    add("skillId")
                }
            }
        }
    }

    val scheduleTaskCreateTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "schedule_task_create")
            put("displayName", "创建定时任务")
            put("toolType", "schedule")
            put("description", "创建新的定时任务。执行后等待工具结果，再决定是否回复用户。")
            put("postToolRule", "创建完成后不要在同一轮继续调用其他工具；请等待工具结果，并通过 response 输出最终答复。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("title") { put("type", "string") }
                    putJsonObject("targetKind") {
                        put("type", "string")
                        putJsonArray("enum") {
                            add("vlm")
                            add("subagent")
                        }
                    }
                    putJsonObject("goal") { put("type", "string") }
                    putJsonObject("packageName") { put("type", "string") }
                    putJsonObject("subagentConversationId") { put("type", "string") }
                    putJsonObject("subagentPrompt") { put("type", "string") }
                    putJsonObject("notificationEnabled") { put("type", "boolean") }
                    putJsonObject("scheduleType") {
                        put("type", "string")
                        putJsonArray("enum") {
                            add("fixed_time")
                            add("countdown")
                        }
                    }
                    putJsonObject("fixedTime") { put("type", "string") }
                    putJsonObject("countdownMinutes") { put("type", "integer") }
                    putJsonObject("repeatDaily") { put("type", "boolean") }
                    putJsonObject("enabled") { put("type", "boolean") }
                }
                putJsonArray("required") {
                    add("title")
                    add("targetKind")
                    add("scheduleType")
                    add("repeatDaily")
                }
            }
        }
    }

    val scheduleTaskListTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "schedule_task_list")
            put("displayName", "查看定时任务")
            put("toolType", "schedule")
            put("description", "查看当前已有的定时任务列表。执行后等待工具结果。")
            put("postToolRule", "查看结果后再决定是否需要修改、删除或向用户总结。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {}
            }
        }
    }

    val scheduleTaskUpdateTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "schedule_task_update")
            put("displayName", "修改定时任务")
            put("toolType", "schedule")
            put("description", "修改已有定时任务的时间、标题、每日重复或启停状态。")
            put("postToolRule", "修改完成后不要同轮回复，等待工具结果。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("taskId") { put("type", "string") }
                    putJsonObject("title") { put("type", "string") }
                    putJsonObject("targetKind") {
                        put("type", "string")
                        putJsonArray("enum") {
                            add("vlm")
                            add("subagent")
                        }
                    }
                    putJsonObject("fixedTime") { put("type", "string") }
                    putJsonObject("countdownMinutes") { put("type", "integer") }
                    putJsonObject("repeatDaily") { put("type", "boolean") }
                    putJsonObject("enabled") { put("type", "boolean") }
                    putJsonObject("subagentConversationId") { put("type", "string") }
                    putJsonObject("subagentPrompt") { put("type", "string") }
                    putJsonObject("notificationEnabled") { put("type", "boolean") }
                }
                putJsonArray("required") {
                    add("taskId")
                }
            }
        }
    }

    val scheduleTaskDeleteTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "schedule_task_delete")
            put("displayName", "删除定时任务")
            put("toolType", "schedule")
            put("description", "删除已有定时任务。执行后等待工具结果。")
            put("postToolRule", "删除完成后等待工具结果，再输出最终回复。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("taskId") { put("type", "string") }
                }
                putJsonArray("required") {
                    add("taskId")
                }
            }
        }
    }

    val alarmReminderCreateTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "alarm_reminder_create")
            put("displayName", "创建提醒闹钟")
            put("toolType", "alarm")
            put(
                "description",
                "创建提醒闹钟。exact_alarm 模式使用 AlarmManager 精确提醒；clock_app 模式调用系统闹钟应用创建闹钟；若用户未明确指定，优先使用 exact_alarm。用于单纯提醒，不执行自动化任务。"
            )
            put("postToolRule", "创建后等待工具结果，再决定是否继续。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("mode") {
                        put("type", "string")
                        putJsonArray("enum") {
                            add("exact_alarm")
                            add("clock_app")
                        }
                        put("description", "闹钟模式：exact_alarm=应用内精确提醒；clock_app=系统闹钟。")
                    }
                    putJsonObject("title") {
                        put("type", "string")
                        put("description", "提醒标题。")
                    }
                    putJsonObject("triggerAt") {
                        put("type", "string")
                        put("description", "触发时间，ISO-8601 格式，例如 2026-03-17T21:30:00+08:00。")
                    }
                    putJsonObject("message") {
                        put("type", "string")
                        put("description", "可选提醒内容。")
                    }
                    putJsonObject("timezone") {
                        put("type", "string")
                        put("description", "可选 IANA 时区，未传默认系统时区。")
                    }
                    putJsonObject("allowWhileIdle") {
                        put("type", "boolean")
                        put("description", "仅 exact_alarm 模式生效，是否在待机时也精确触发。默认 true。")
                    }
                    putJsonObject("skipUi") {
                        put("type", "boolean")
                        put("description", "仅 clock_app 模式生效，是否尝试跳过系统闹钟界面。默认 false。")
                    }
                }
                putJsonArray("required") {
                    add("mode")
                    add("title")
                    add("triggerAt")
                }
            }
        }
    }

    val alarmReminderListTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "alarm_reminder_list")
            put("displayName", "查看提醒闹钟")
            put("toolType", "alarm")
            put("description", "查看由本应用创建并托管的 exact_alarm 提醒闹钟列表。")
            put("postToolRule", "查看结果后再决定是否删除或继续创建。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {}
            }
        }
    }

    val alarmReminderDeleteTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "alarm_reminder_delete")
            put("displayName", "删除提醒闹钟")
            put("toolType", "alarm")
            put("description", "按 alarmId 删除本应用创建并托管的 exact_alarm 提醒闹钟。")
            put("postToolRule", "删除后等待工具结果，再向用户确认。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("alarmId") {
                        put("type", "string")
                        put("description", "闹钟 ID。")
                    }
                }
                putJsonArray("required") {
                    add("alarmId")
                }
            }
        }
    }

    val calendarListTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "calendar_list")
            put("displayName", "查看日历列表")
            put("toolType", "calendar")
            put("description", "查询设备日历账户列表，可用于选择 calendarId。")
            put("postToolRule", "查看结果后再决定新建或管理日程。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("writableOnly") {
                        put("type", "boolean")
                        put("description", "是否仅返回可写日历。默认 true。")
                    }
                    putJsonObject("visibleOnly") {
                        put("type", "boolean")
                        put("description", "是否仅返回可见日历。默认 true。")
                    }
                }
            }
        }
    }

    val calendarEventCreateTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "calendar_event_create")
            put("displayName", "创建日程")
            put("toolType", "calendar")
            put("description", "创建日历事件。用于管理日程，不触发自动化任务。")
            put("postToolRule", "创建后等待工具结果，再向用户确认。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("title") { put("type", "string") }
                    putJsonObject("startAt") {
                        put("type", "string")
                        put("description", "开始时间，ISO-8601。")
                    }
                    putJsonObject("endAt") {
                        put("type", "string")
                        put("description", "结束时间，ISO-8601。")
                    }
                    putJsonObject("calendarId") {
                        put("type", "string")
                        put("description", "可选，目标日历 ID。")
                    }
                    putJsonObject("description") { put("type", "string") }
                    putJsonObject("location") { put("type", "string") }
                    putJsonObject("timezone") {
                        put("type", "string")
                        put("description", "可选 IANA 时区，未传默认系统时区。")
                    }
                    putJsonObject("allDay") { put("type", "boolean") }
                    putJsonObject("reminderMinutes") {
                        put("type", "array")
                        put("description", "提醒分钟列表，例如 [10, 30]。")
                        putJsonObject("items") {
                            put("type", "integer")
                        }
                    }
                }
                putJsonArray("required") {
                    add("title")
                    add("startAt")
                    add("endAt")
                }
            }
        }
    }

    val calendarEventListTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "calendar_event_list")
            put("displayName", "查询日程")
            put("toolType", "calendar")
            put("description", "按时间范围、关键字、calendarId 查询日历事件。")
            put("postToolRule", "查看结果后再决定是否更新或删除。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("calendarId") { put("type", "string") }
                    putJsonObject("startAt") {
                        put("type", "string")
                        put("description", "可选，查询起始时间，ISO-8601。")
                    }
                    putJsonObject("endAt") {
                        put("type", "string")
                        put("description", "可选，查询结束时间，ISO-8601。")
                    }
                    putJsonObject("query") {
                        put("type", "string")
                        put("description", "可选关键词，匹配标题或地点。")
                    }
                    putJsonObject("limit") {
                        put("type", "integer")
                        put("description", "可选返回上限，默认 50，范围 1-200。")
                    }
                }
            }
        }
    }

    val calendarEventUpdateTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "calendar_event_update")
            put("displayName", "修改日程")
            put("toolType", "calendar")
            put("description", "按 eventId 修改日历事件。")
            put("postToolRule", "修改后等待工具结果，再向用户同步。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("eventId") {
                        put("type", "string")
                        put("description", "事件 ID。")
                    }
                    putJsonObject("title") { put("type", "string") }
                    putJsonObject("startAt") { put("type", "string") }
                    putJsonObject("endAt") { put("type", "string") }
                    putJsonObject("description") { put("type", "string") }
                    putJsonObject("location") { put("type", "string") }
                    putJsonObject("timezone") { put("type", "string") }
                    putJsonObject("allDay") { put("type", "boolean") }
                    putJsonObject("reminderMinutes") {
                        put("type", "array")
                        putJsonObject("items") {
                            put("type", "integer")
                        }
                    }
                }
                putJsonArray("required") {
                    add("eventId")
                }
            }
        }
    }

    val calendarEventDeleteTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "calendar_event_delete")
            put("displayName", "删除日程")
            put("toolType", "calendar")
            put("description", "按 eventId 删除日历事件。")
            put("postToolRule", "删除后等待工具结果，再向用户确认。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("eventId") { put("type", "string") }
                }
                putJsonArray("required") {
                    add("eventId")
                }
            }
        }
    }

    val musicPlaybackControlTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "music_playback_control")
            put("displayName", "音乐播放控制")
            put("toolType", "music")
            put(
                "description",
                "控制安卓系统级音乐播放。action=play 且提供 source 时，会由应用前台媒体会话播放本地文件、omnibot workspace/public 文件、file/content Uri 或 http(s) 直链音频；play 不提供 source 时，退化为向系统当前播放器发送播放媒体键。pause/resume/stop/next/previous 会优先控制当前由本应用托管的音频播放，若没有本地会话则退化为发送系统媒体键；seek 和 status 仅针对本应用托管的播放会话。"
            )
            put("postToolRule", "执行后等待工具结果，再决定是否继续调整播放。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("action") {
                        put("type", "string")
                        put("description", "要执行的播放控制动作。")
                        putJsonArray("enum") {
                            add("play")
                            add("pause")
                            add("resume")
                            add("stop")
                            add("seek")
                            add("status")
                            add("next")
                            add("previous")
                        }
                    }
                    putJsonObject("source") {
                        put("type", "string")
                        put("description", "仅 play 时可选。支持 omnibot://、/workspace、/storage、相对 workspace 路径、file://、content://、http(s) 直链。留空表示只向系统发送播放媒体键。")
                    }
                    putJsonObject("title") {
                        put("type", "string")
                        put("description", "仅 play 时可选，前台通知与系统媒体会话里显示的标题。")
                    }
                    putJsonObject("loop") {
                        put("type", "boolean")
                        put("description", "仅 play 时可选，是否循环播放。默认 false。")
                    }
                    putJsonObject("positionSeconds") {
                        put("type", "integer")
                        put("description", "仅 seek 时使用，目标播放秒数。")
                    }
                }
                putJsonArray("required") {
                    add("action")
                }
            }
        }
    }

    val memorySearchTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "memory_search")
            put("displayName", "检索记忆")
            put("toolType", "memory")
            put("description", "在 workspace 记忆中检索与当前问题相关的长期/短期记忆。优先使用向量召回，配置缺失时自动降级词法检索。")
            put("postToolRule", "读取结果后再决定是否写入新的短期或长期记忆。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("query") {
                        put("type", "string")
                        put("description", "检索语句。")
                    }
                    putJsonObject("limit") {
                        put("type", "integer")
                        put("description", "返回条数上限，默认 8，范围 1-20。")
                    }
                }
                putJsonArray("required") {
                    add("query")
                }
            }
        }
    }

    val memoryWriteDailyTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "memory_write_daily")
            put("displayName", "写入当日记忆")
            put("toolType", "memory")
            put("description", "将当轮过程性信息写入 `.omnibot/memory/short-memories/YY-MM-DD.md`。")
            put("postToolRule", "写入成功后再继续执行其他步骤。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("text") {
                        put("type", "string")
                        put("description", "要写入的短期记忆文本。")
                    }
                }
                putJsonArray("required") {
                    add("text")
                }
            }
        }
    }

    val memoryUpsertLongTermTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "memory_upsert_longterm")
            put("displayName", "沉淀长期记忆")
            put("toolType", "memory")
            put("description", "将稳定偏好、长期约束、身份事实写入 `.omnibot/memory/MEMORY.md`。自动去重相同条目。")
            put("postToolRule", "写入后等待工具结果，再向用户确认。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("text") {
                        put("type", "string")
                        put("description", "要沉淀的长期记忆内容。")
                    }
                }
                putJsonArray("required") {
                    add("text")
                }
            }
        }
    }

    val memoryRollupDayTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "memory_rollup_day")
            put("displayName", "整理当日记忆")
            put("toolType", "memory")
            put("description", "整理某一天短期记忆并按策略沉淀到长期记忆。默认整理今天。")
            put("postToolRule", "整理后等待工具结果，再决定是否补充长期记忆。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("date") {
                        put("type", "string")
                        put("description", "可选日期，格式 YYYY-MM-DD。")
                    }
                }
            }
        }
    }

    val subagentDispatchTool: JsonObject = buildJsonObject {
        put("type", "function")
        putJsonObject("function") {
            put("name", "subagent_dispatch")
            put("displayName", "分派子任务")
            put("toolType", "subagent")
            put("description", "把多个可并行的小任务分派给 subagent 集群执行，并返回聚合结果。")
            put("postToolRule", "分派后等待工具结果，再汇总给用户。")
            putJsonObject("parameters") {
                put("type", "object")
                putJsonObject("properties") {
                    putJsonObject("tasks") {
                        put("type", "array")
                        putJsonObject("items") {
                            put("type", "string")
                        }
                        put("description", "需要并行执行的子任务列表。")
                    }
                    putJsonObject("concurrency") {
                        put("type", "integer")
                        put("description", "并发度，默认 2，范围 1-6。")
                    }
                    putJsonObject("mergeInstruction") {
                        put("type", "string")
                        put("description", "结果聚合要求，可选。")
                    }
                }
                putJsonArray("required") {
                    add("tasks")
                }
            }
        }
    }

    val builtinTools: List<JsonObject> = listOf(
        contextAppsQueryTool,
        contextTimeNowTool,
        vlmTaskTool,
        terminalExecuteTool,
        terminalSessionStartTool,
        terminalSessionExecTool,
        terminalSessionReadTool,
        terminalSessionStopTool,
        browserUseTool,
        fileReadTool,
        fileWriteTool,
        fileEditTool,
        fileListTool,
        fileSearchTool,
        fileStatTool,
        fileMoveTool,
        skillsListTool,
        skillsReadTool
    ).map(::decorateToolDefinition)

    val scheduleTools: List<JsonObject> = listOf(
        scheduleTaskCreateTool,
        scheduleTaskListTool,
        scheduleTaskUpdateTool,
        scheduleTaskDeleteTool
    ).map(::decorateToolDefinition)

    val alarmTools: List<JsonObject> = listOf(
        alarmReminderCreateTool,
        alarmReminderListTool,
        alarmReminderDeleteTool
    ).map(::decorateToolDefinition)

    val calendarTools: List<JsonObject> = listOf(
        calendarListTool,
        calendarEventCreateTool,
        calendarEventListTool,
        calendarEventUpdateTool,
        calendarEventDeleteTool
    ).map(::decorateToolDefinition)

    val musicTools: List<JsonObject> = listOf(
        musicPlaybackControlTool
    ).map(::decorateToolDefinition)

    val memoryTools: List<JsonObject> = listOf(
        memorySearchTool,
        memoryWriteDailyTool,
        memoryUpsertLongTermTool,
        memoryRollupDayTool
    ).map(::decorateToolDefinition)

    val subagentTools: List<JsonObject> = listOf(
        subagentDispatchTool
    ).map(::decorateToolDefinition)

    fun staticTools(): List<JsonObject> = builtinTools + scheduleTools + alarmTools + calendarTools + musicTools
}
