package cn.com.omnimind.assists.task.vlmserver

import cn.com.omnimind.baselib.llm.ChatCompletionFunction
import cn.com.omnimind.baselib.llm.ChatCompletionTool
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

object VLMToolDefinitions {
    data class ToolSpec(
        val name: String,
        val description: String,
        val parameters: JsonObject,
        val promptGuide: String
    )

    private val toolSpecs: List<ToolSpec> = listOf(
        ToolSpec(
            name = "click",
            description = "点击一个可见目标。",
            parameters = objectSchema(
                properties = linkedMapOf(
                    "target_description" to stringSchema("要点击的目标描述。"),
                    "x" to coordinateNumberSchema("点击位置的 X 坐标。"),
                    "y" to coordinateNumberSchema("点击位置的 Y 坐标。")
                ),
                required = listOf("target_description", "x", "y")
            ),
            promptGuide = "- click(target_description, x, y): 点击一个可见目标。"
        ),
        ToolSpec(
            name = "type",
            description = "在当前输入焦点中输入文本。",
            parameters = objectSchema(
                properties = linkedMapOf(
                    "content" to stringSchema("要输入的文本内容。")
                ),
                required = listOf("content")
            ),
            promptGuide = "- type(content): 在当前输入框输入文本。"
        ),
        ToolSpec(
            name = "scroll",
            description = "从起点滑动到终点。",
            parameters = objectSchema(
                properties = linkedMapOf(
                    "target_description" to stringSchema("本次滚动想浏览或定位的目标描述。"),
                    "x1" to coordinateNumberSchema("起点 X 坐标。"),
                    "y1" to coordinateNumberSchema("起点 Y 坐标。"),
                    "x2" to coordinateNumberSchema("终点 X 坐标。"),
                    "y2" to coordinateNumberSchema("终点 Y 坐标。"),
                    "duration" to numberSchema("滑动时长，单位秒。")
                ),
                required = listOf("target_description", "x1", "y1", "x2", "y2")
            ),
            promptGuide = "- scroll(target_description, x1, y1, x2, y2, duration?): 在屏幕上滑动。"
        ),
        ToolSpec(
            name = "long_press",
            description = "长按一个目标。",
            parameters = objectSchema(
                properties = linkedMapOf(
                    "target_description" to stringSchema("要长按的目标描述。"),
                    "x" to coordinateNumberSchema("长按位置的 X 坐标。"),
                    "y" to coordinateNumberSchema("长按位置的 Y 坐标。")
                ),
                required = listOf("target_description", "x", "y")
            ),
            promptGuide = "- long_press(target_description, x, y): 长按一个目标。"
        ),
        ToolSpec(
            name = "open_app",
            description = "打开指定应用。",
            parameters = objectSchema(
                properties = linkedMapOf(
                    "package_name" to stringSchema("目标应用的 Android package name。")
                ),
                required = listOf("package_name")
            ),
            promptGuide = "- open_app(package_name): 打开指定应用。"
        ),
        ToolSpec(
            name = "press_home",
            description = "回到桌面。",
            parameters = objectSchema(),
            promptGuide = "- press_home(): 回到桌面。"
        ),
        ToolSpec(
            name = "press_back",
            description = "返回上一级。",
            parameters = objectSchema(),
            promptGuide = "- press_back(): 返回上一级。"
        ),
        ToolSpec(
            name = "wait",
            description = "等待界面稳定。",
            parameters = objectSchema(
                properties = linkedMapOf(
                    "duration_ms" to integerSchema("等待时长，单位毫秒。"),
                    "duration" to numberSchema("兼容字段：等待时长，单位秒。")
                ),
                required = listOf("duration_ms")
            ),
            promptGuide = "- wait(duration_ms): 等待指定毫秒数。若服务商兼容性较差，也可额外提供 duration(秒)。"
        ),
        ToolSpec(
            name = "hot_key",
            description = "发送一个受支持的快捷键。",
            parameters = objectSchema(
                properties = linkedMapOf(
                    "key" to enumSchema(
                        description = "当前受支持的快捷键。",
                        values = listOf("ENTER", "BACK", "HOME")
                    )
                ),
                required = listOf("key")
            ),
            promptGuide = "- hot_key(key): 兼容 ENTER / BACK / HOME，但系统导航优先使用 press_back 或 press_home。"
        ),
        ToolSpec(
            name = "finished",
            description = "任务真正完成时结束。",
            parameters = objectSchema(
                properties = linkedMapOf(
                    "content" to stringSchema("给用户的最终完成说明，可为空。")
                )
            ),
            promptGuide = "- finished(content?): 仅在任务真正完成时调用。"
        ),
        ToolSpec(
            name = "info",
            description = "向用户询问或请求手动协助。",
            parameters = objectSchema(
                properties = linkedMapOf(
                    "value" to stringSchema("你要问用户的问题或需要用户执行的说明。")
                ),
                required = listOf("value")
            ),
            promptGuide = "- info(value): 询问用户或请求用户协助。"
        ),
        ToolSpec(
            name = "feedback",
            description = "反馈当前上下文与目标不匹配。",
            parameters = objectSchema(
                properties = linkedMapOf(
                    "value" to stringSchema("反馈原因。")
                ),
                required = listOf("value")
            ),
            promptGuide = "- feedback(value): 请求上层重新规划。"
        ),
        ToolSpec(
            name = "abort",
            description = "任务无法继续时终止。",
            parameters = objectSchema(
                properties = linkedMapOf(
                    "value" to stringSchema("终止任务的原因。")
                )
            ),
            promptGuide = "- abort(value?): 在任务无法继续时终止。"
        ),
        ToolSpec(
            name = "require_user_choice",
            description = "让用户在若干选项中选择一个。",
            parameters = objectSchema(
                properties = linkedMapOf(
                    "options" to stringArraySchema("可供用户选择的选项列表。"),
                    "prompt" to stringSchema("要求用户做选择的提示文案。")
                ),
                required = listOf("options", "prompt")
            ),
            promptGuide = "- require_user_choice(options, prompt): 让用户做互斥选择。"
        ),
        ToolSpec(
            name = "require_user_confirmation",
            description = "让用户确认当前状态后继续。",
            parameters = objectSchema(
                properties = linkedMapOf(
                    "prompt" to stringSchema("要求用户确认的提示文案。")
                ),
                required = listOf("prompt")
            ),
            promptGuide = "- require_user_confirmation(prompt): 让用户确认后继续。"
        )
    )

    private val toolSpecsByName: Map<String, ToolSpec> = toolSpecs.associateBy { it.name }

    fun tools(): List<ChatCompletionTool> {
        return toolSpecs.map { spec ->
            ChatCompletionTool(
                function = ChatCompletionFunction(
                    name = spec.name,
                    description = spec.description,
                    parameters = spec.parameters
                )
            )
        }
    }

    fun renderPromptGuide(): String {
        val guides = toolSpecs.joinToString(separator = "\n") { it.promptGuide }
        return buildString {
            appendLine(guides)
            append("注意：所有 function.arguments 必须是严格合法的 JSON object。坐标必须分别写入 x / y / x1 / y1 / x2 / y2 字段，不要写成 \"x\": 827, 76 这类非法格式。")
        }
    }

    fun responseContract(): String {
        return """{"observation":"当前界面的关键状态","thought":"为什么要执行这个工具","summary":"执行完本步后新的历史总结"}"""
    }

    fun toolSpec(name: String): ToolSpec? = toolSpecsByName[name]

    fun propertiesFor(toolName: String): Map<String, JsonObject> {
        val properties = toolSpec(toolName)?.parameters?.get("properties") as? JsonObject ?: return emptyMap()
        return properties.mapValues { (_, value) -> value as? JsonObject ?: JsonObject(emptyMap()) }
    }

    fun requiredFieldsFor(toolName: String): List<String> {
        val required = toolSpec(toolName)?.parameters?.get("required") as? JsonArray ?: return emptyList()
        return required.mapNotNull { it.jsonPrimitive.contentOrNull?.trim()?.takeIf(String::isNotEmpty) }
    }

    fun normalizeArguments(toolName: String, arguments: JsonObject): JsonObject {
        if (arguments.isEmpty()) return arguments
        val normalized = arguments.toMutableMap()
        when (toolName) {
            "click", "long_press" -> normalizePointArguments(normalized)
            "scroll" -> normalizeScrollArguments(normalized)
        }
        return JsonObject(normalized)
    }

    fun coerceArguments(toolName: String, arguments: JsonObject): JsonObject {
        val properties = propertiesFor(toolName)
        if (properties.isEmpty() || arguments.isEmpty()) return arguments

        val normalized = linkedMapOf<String, JsonElement>()
        arguments.entries.forEach { (field, value) ->
            val schema = properties[field]
            normalized[field] = if (schema != null) {
                coerceValue(value, schema)
            } else {
                value
            }
        }
        return JsonObject(normalized)
    }

    fun validateArguments(toolName: String, arguments: JsonObject) {
        val properties = propertiesFor(toolName)
        val requiredFields = requiredFieldsFor(toolName)
        requiredFields.forEach { field ->
            if (toolName == "wait" && field == "duration_ms" && arguments["duration"] != null) {
                return@forEach
            }
            if (arguments[field] == null || arguments[field] is JsonNull) {
                throw IllegalArgumentException("Tool $toolName missing required argument: $field")
            }
        }

        arguments.entries.forEach { (field, value) ->
            val schema = properties[field] ?: return@forEach
            val expectedType = schema["type"]?.jsonPrimitive?.contentOrNull?.trim().orEmpty()
            if (expectedType.isNotEmpty() && !matchesType(expectedType, value)) {
                val coordinateHint = if (expectedType == "number" && isCoordinateField(field)) {
                    " Coordinate fields must be a single numeric scalar, not [x,y], objects, or tuples."
                } else {
                    ""
                }
                throw IllegalArgumentException(
                    "Tool $toolName argument $field expected $expectedType but got ${describeType(value)}.$coordinateHint"
                )
            }
            val enumValues = (schema["enum"] as? JsonArray).orEmpty()
            if (enumValues.isNotEmpty()) {
                val raw = (value as? JsonPrimitive)?.contentOrNull
                if (raw == null || enumValues.none { it.jsonPrimitive.contentOrNull == raw }) {
                    throw IllegalArgumentException(
                        "Tool $toolName argument $field must be one of ${
                            enumValues.joinToString(",") { it.toString() }
                        }"
                    )
                }
            }
        }
    }

    private fun normalizePointArguments(arguments: MutableMap<String, JsonElement>) {
        extractPoint(arguments["x"])?.let { (x, y) ->
            arguments["x"] = buildNumericPrimitive(x)
            if (extractScalarNumber(arguments["y"]) == null) {
                arguments["y"] = buildNumericPrimitive(y)
            }
        }
        extractPoint(arguments["y"])?.let { (x, y) ->
            if (extractScalarNumber(arguments["x"]) == null) {
                arguments["x"] = buildNumericPrimitive(x)
            }
            arguments["y"] = buildNumericPrimitive(y)
        }
        if (extractScalarNumber(arguments["x"]) != null && extractScalarNumber(arguments["y"]) != null) {
            return
        }

        POINT_ALIAS_FIELDS.firstNotNullOfOrNull { alias ->
            extractPoint(arguments[alias])
        }?.let { (x, y) ->
            if (extractScalarNumber(arguments["x"]) == null) {
                arguments["x"] = buildNumericPrimitive(x)
            }
            if (extractScalarNumber(arguments["y"]) == null) {
                arguments["y"] = buildNumericPrimitive(y)
            }
        }
    }

    private fun normalizeScrollArguments(arguments: MutableMap<String, JsonElement>) {
        extractPoint(arguments["x1"])?.let { (x, y) ->
            arguments["x1"] = buildNumericPrimitive(x)
            if (extractScalarNumber(arguments["y1"]) == null) {
                arguments["y1"] = buildNumericPrimitive(y)
            }
        }
        extractPoint(arguments["x2"])?.let { (x, y) ->
            arguments["x2"] = buildNumericPrimitive(x)
            if (extractScalarNumber(arguments["y2"]) == null) {
                arguments["y2"] = buildNumericPrimitive(y)
            }
        }

        if (hasCompleteScrollCoordinates(arguments)) {
            return
        }

        RANGE_ALIAS_FIELDS.firstNotNullOfOrNull { alias ->
            extractRange(arguments[alias])
        }?.let { (x1, y1, x2, y2) ->
            if (extractScalarNumber(arguments["x1"]) == null) {
                arguments["x1"] = buildNumericPrimitive(x1)
            }
            if (extractScalarNumber(arguments["y1"]) == null) {
                arguments["y1"] = buildNumericPrimitive(y1)
            }
            if (extractScalarNumber(arguments["x2"]) == null) {
                arguments["x2"] = buildNumericPrimitive(x2)
            }
            if (extractScalarNumber(arguments["y2"]) == null) {
                arguments["y2"] = buildNumericPrimitive(y2)
            }
        }

        if (hasCompleteScrollCoordinates(arguments)) {
            return
        }

        val startPoint = RANGE_START_ALIAS_FIELDS.firstNotNullOfOrNull { alias ->
            extractPoint(arguments[alias])
        }
        val endPoint = RANGE_END_ALIAS_FIELDS.firstNotNullOfOrNull { alias ->
            extractPoint(arguments[alias])
        }
        if (startPoint != null && endPoint != null) {
            if (extractScalarNumber(arguments["x1"]) == null) {
                arguments["x1"] = buildNumericPrimitive(startPoint.first)
            }
            if (extractScalarNumber(arguments["y1"]) == null) {
                arguments["y1"] = buildNumericPrimitive(startPoint.second)
            }
            if (extractScalarNumber(arguments["x2"]) == null) {
                arguments["x2"] = buildNumericPrimitive(endPoint.first)
            }
            if (extractScalarNumber(arguments["y2"]) == null) {
                arguments["y2"] = buildNumericPrimitive(endPoint.second)
            }
        }
    }

    private fun hasCompleteScrollCoordinates(arguments: Map<String, JsonElement>): Boolean {
        return extractScalarNumber(arguments["x1"]) != null &&
            extractScalarNumber(arguments["y1"]) != null &&
            extractScalarNumber(arguments["x2"]) != null &&
            extractScalarNumber(arguments["y2"]) != null
    }

    private fun extractPoint(value: JsonElement?): Pair<Double, Double>? {
        return when (value) {
            is JsonArray -> {
                if (value.size < 2) return null
                val x = extractScalarNumber(value[0]) ?: return null
                val y = extractScalarNumber(value[1]) ?: return null
                x to y
            }

            is JsonObject -> {
                val x = extractScalarNumber(value["x"]) ?: return null
                val y = extractScalarNumber(value["y"]) ?: return null
                x to y
            }

            is JsonPrimitive -> extractPointFromString(value.contentOrNull)
            else -> null
        }
    }

    private fun extractRange(value: JsonElement?): ScrollCoordinates? {
        return when (value) {
            is JsonArray -> {
                if (value.size >= 4) {
                    val x1 = extractScalarNumber(value[0]) ?: return null
                    val y1 = extractScalarNumber(value[1]) ?: return null
                    val x2 = extractScalarNumber(value[2]) ?: return null
                    val y2 = extractScalarNumber(value[3]) ?: return null
                    return ScrollCoordinates(x1, y1, x2, y2)
                }
                if (value.size >= 2) {
                    val start = extractPoint(value[0]) ?: return null
                    val end = extractPoint(value[1]) ?: return null
                    return ScrollCoordinates(start.first, start.second, end.first, end.second)
                }
                null
            }

            is JsonObject -> {
                val direct = buildScrollCoordinates(
                    x1 = extractScalarNumber(value["x1"]),
                    y1 = extractScalarNumber(value["y1"]),
                    x2 = extractScalarNumber(value["x2"]),
                    y2 = extractScalarNumber(value["y2"])
                )
                if (direct != null) return direct

                val start = RANGE_START_ALIAS_FIELDS.firstNotNullOfOrNull { alias ->
                    extractPoint(value[alias])
                }
                val end = RANGE_END_ALIAS_FIELDS.firstNotNullOfOrNull { alias ->
                    extractPoint(value[alias])
                }
                if (start != null && end != null) {
                    return ScrollCoordinates(start.first, start.second, end.first, end.second)
                }
                null
            }

            is JsonPrimitive -> extractRangeFromString(value.contentOrNull)
            else -> null
        }
    }

    private fun extractPointFromString(raw: String?): Pair<Double, Double>? {
        val normalized = raw?.trim().orEmpty()
        if (normalized.isEmpty()) return null
        if ((normalized.startsWith("[") && normalized.endsWith("]")) ||
            (normalized.startsWith("{") && normalized.endsWith("}"))
        ) {
            val parsed = runCatching {
                kotlinx.serialization.json.Json.parseToJsonElement(normalized)
            }.getOrNull()
            return extractPoint(parsed)
        }
        val numbers = NUMBER_REGEX.findAll(normalized).mapNotNull { it.value.toDoubleOrNull() }.toList()
        if (numbers.size < 2) return null
        return numbers[0] to numbers[1]
    }

    private fun extractRangeFromString(raw: String?): ScrollCoordinates? {
        val normalized = raw?.trim().orEmpty()
        if (normalized.isEmpty()) return null
        if ((normalized.startsWith("[") && normalized.endsWith("]")) ||
            (normalized.startsWith("{") && normalized.endsWith("}"))
        ) {
            val parsed = runCatching {
                kotlinx.serialization.json.Json.parseToJsonElement(normalized)
            }.getOrNull()
            return extractRange(parsed)
        }
        val numbers = NUMBER_REGEX.findAll(normalized).mapNotNull { it.value.toDoubleOrNull() }.toList()
        if (numbers.size < 4) return null
        return ScrollCoordinates(numbers[0], numbers[1], numbers[2], numbers[3])
    }

    private fun buildScrollCoordinates(
        x1: Double?,
        y1: Double?,
        x2: Double?,
        y2: Double?
    ): ScrollCoordinates? {
        if (x1 == null || y1 == null || x2 == null || y2 == null) return null
        return ScrollCoordinates(x1, y1, x2, y2)
    }

    private fun extractScalarNumber(value: JsonElement?): Double? {
        return when (value) {
            is JsonPrimitive -> value.contentOrNull?.trim()?.toDoubleOrNull()
            else -> null
        }
    }

    private fun isCoordinateField(field: String): Boolean {
        return field == "x" || field == "y" || field == "x1" || field == "y1" || field == "x2" || field == "y2"
    }

    private fun coerceValue(value: JsonElement, schema: JsonObject): JsonElement {
        val type = schema["type"]?.jsonPrimitive?.contentOrNull?.trim().orEmpty()
        return when (type) {
            "string" -> coerceString(value)
            "number" -> coerceNumber(value) ?: value
            "integer" -> coerceInteger(value) ?: value
            "array" -> coerceArray(value, schema) ?: value
            else -> value
        }
    }

    private fun coerceString(value: JsonElement): JsonElement {
        return when (value) {
            is JsonPrimitive -> {
                JsonPrimitive(value.contentOrNull ?: value.toString())
            }

            else -> JsonPrimitive(value.toString())
        }
    }

    private fun coerceNumber(value: JsonElement): JsonPrimitive? {
        val primitive = value as? JsonPrimitive ?: return null
        val raw = primitive.contentOrNull?.trim().orEmpty()
        if (raw.isEmpty()) return null
        val number = raw.toDoubleOrNull() ?: return null
        val asLong = number.toLong()
        return if (number == asLong.toDouble()) JsonPrimitive(asLong) else JsonPrimitive(number)
    }

    private fun coerceInteger(value: JsonElement): JsonPrimitive? {
        val primitive = value as? JsonPrimitive ?: return null
        val raw = primitive.contentOrNull?.trim().orEmpty()
        if (raw.isEmpty()) return null
        val longValue = raw.toLongOrNull()
            ?: raw.toDoubleOrNull()?.toLong()
            ?: return null
        return JsonPrimitive(longValue)
    }

    private fun coerceArray(value: JsonElement, schema: JsonObject): JsonArray? {
        if (value is JsonArray) return value
        val primitive = value as? JsonPrimitive ?: return null
        val raw = primitive.contentOrNull?.trim().orEmpty()
        if (raw.isEmpty()) return JsonArray(emptyList())
        val itemType = ((schema["items"] as? JsonObject)?.get("type") as? JsonPrimitive)?.contentOrNull
        if (itemType == "string") {
            val parts = raw.split(Regex("[,，、\\n]"))
                .map { it.trim().trim('"', '\'') }
                .filter { it.isNotEmpty() }
                .map(::JsonPrimitive)
            return JsonArray(parts)
        }
        return null
    }

    private fun matchesType(expectedType: String, value: JsonElement): Boolean {
        return when (expectedType) {
            "string" -> value is JsonPrimitive && value.isString
            "integer" -> value is JsonPrimitive && !value.isString && (value.longOrNull != null || value.intOrNull != null)
            "number" -> value is JsonPrimitive && !value.isString && value.doubleOrNull != null
            "boolean" -> value is JsonPrimitive && !value.isString && value.booleanOrNull != null
            "object" -> value is JsonObject
            "array" -> value is JsonArray
            else -> true
        }
    }

    private fun describeType(value: JsonElement): String {
        return when (value) {
            is JsonObject -> "object"
            is JsonArray -> "array"
            is JsonNull -> "null"
            is JsonPrimitive -> when {
                value.isString -> "string"
                value.booleanOrNull != null -> "boolean"
                value.intOrNull != null || value.longOrNull != null -> "integer"
                value.doubleOrNull != null -> "number"
                else -> "primitive"
            }
        }
    }

    private fun objectSchema(
        properties: Map<String, JsonObject> = emptyMap(),
        required: List<String> = emptyList()
    ): JsonObject {
        return buildJsonObject {
            put("type", JsonPrimitive("object"))
            put("additionalProperties", JsonPrimitive(false))
            put(
                "properties",
                JsonObject(properties)
            )
            if (required.isNotEmpty()) {
                put(
                    "required",
                    buildJsonArray {
                        required.forEach { add(JsonPrimitive(it)) }
                    }
                )
            }
        }
    }

    private fun stringSchema(description: String): JsonObject {
        return buildJsonObject {
            put("type", JsonPrimitive("string"))
            put("description", JsonPrimitive(description))
        }
    }

    private fun coordinateNumberSchema(description: String): JsonObject {
        return buildJsonObject {
            put("type", JsonPrimitive("number"))
            put(
                "description",
                JsonPrimitive("$description 单个数值，范围 0-1000；不要传数组、对象或坐标对。")
            )
            put("minimum", JsonPrimitive(0))
            put("maximum", JsonPrimitive(1000))
        }
    }

    private fun numberSchema(description: String): JsonObject {
        return buildJsonObject {
            put("type", JsonPrimitive("number"))
            put("description", JsonPrimitive(description))
        }
    }

    private fun integerSchema(description: String): JsonObject {
        return buildJsonObject {
            put("type", JsonPrimitive("integer"))
            put("description", JsonPrimitive(description))
        }
    }

    private fun stringArraySchema(description: String): JsonObject {
        return buildJsonObject {
            put("type", JsonPrimitive("array"))
            put("description", JsonPrimitive(description))
            put(
                "items",
                buildJsonObject {
                    put("type", JsonPrimitive("string"))
                }
            )
        }
    }

    private fun enumSchema(description: String, values: List<String>): JsonObject {
        return buildJsonObject {
            put("type", JsonPrimitive("string"))
            put("description", JsonPrimitive(description))
            put(
                "enum",
                JsonArray(values.map(::JsonPrimitive))
            )
        }
    }

    private data class ScrollCoordinates(
        val x1: Double,
        val y1: Double,
        val x2: Double,
        val y2: Double
    )

    private fun buildNumericPrimitive(number: Double): JsonPrimitive {
        val asLong = number.toLong()
        return if (number == asLong.toDouble()) JsonPrimitive(asLong) else JsonPrimitive(number)
    }

    private val POINT_ALIAS_FIELDS = listOf(
        "position",
        "point",
        "coord",
        "coords",
        "coordinate",
        "coordinates",
        "tap_point",
        "click_point"
    )

    private val RANGE_ALIAS_FIELDS = listOf(
        "path",
        "points",
        "coords",
        "coordinate",
        "coordinates",
        "positions",
        "range"
    )

    private val RANGE_START_ALIAS_FIELDS = listOf("start", "from", "begin", "start_point")
    private val RANGE_END_ALIAS_FIELDS = listOf("end", "to", "finish", "end_point")
    private val NUMBER_REGEX = Regex("""[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?""")
}
