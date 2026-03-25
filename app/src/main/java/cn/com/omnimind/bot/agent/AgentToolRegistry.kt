package cn.com.omnimind.bot.agent

import cn.com.omnimind.baselib.util.OmniLog
import cn.com.omnimind.bot.mcp.RemoteMcpDiscoveredServer
import cn.com.omnimind.bot.mcp.RemoteMcpToolDescriptor
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

class AgentToolRegistry(
    discoveredServers: List<RemoteMcpDiscoveredServer>
) {
    data class RuntimeToolDescriptor(
        val name: String,
        val displayName: String,
        val toolType: String,
        val serverName: String? = null,
        val remoteTool: RemoteMcpToolDescriptor? = null
    )

    private val tag = "AgentToolRegistry"
    private val toolSchemas = linkedMapOf<String, JsonObject>()
    private val runtimeDescriptors = linkedMapOf<String, RuntimeToolDescriptor>()
    val toolsForModel: List<ChatCompletionTool>

    init {
        val runtimeDefinitions = mutableListOf<JsonObject>()
        runtimeDefinitions.addAll(AgentToolDefinitions.staticTools())
        runtimeDefinitions.addAll(AgentToolDefinitions.memoryTools)
        runtimeDefinitions.addAll(AgentToolDefinitions.subagentTools)
        discoveredServers.flatMap { it.tools }.forEach { tool ->
            runtimeDefinitions.add(toDynamicMcpToolDefinition(tool))
        }

        toolsForModel = runtimeDefinitions.mapNotNull { definition ->
            val function = definition["function"] as? JsonObject ?: return@mapNotNull null
            val name = function["name"]?.jsonPrimitive?.contentOrNull?.trim().orEmpty()
            if (name.isBlank()) return@mapNotNull null
            val description = function["description"]?.jsonPrimitive?.contentOrNull.orEmpty()
            val parameters = (function["parameters"] as? JsonObject) ?: JsonObject(emptyMap())
            val displayName = function["displayName"]?.jsonPrimitive?.contentOrNull?.trim()
                .takeUnless { it.isNullOrBlank() } ?: name
            val toolType = function["toolType"]?.jsonPrimitive?.contentOrNull?.trim()
                .takeUnless { it.isNullOrBlank() } ?: "builtin"
            val serverName = function["serverName"]?.jsonPrimitive?.contentOrNull?.trim()
                ?.takeIf { it.isNotEmpty() }

            toolSchemas[name] = parameters
            runtimeDescriptors[name] = RuntimeToolDescriptor(
                name = name,
                displayName = displayName,
                toolType = toolType,
                serverName = serverName,
                remoteTool = findRemoteTool(name, discoveredServers)
            )
            ChatCompletionTool(
                function = ChatCompletionFunction(
                    name = name,
                    description = description,
                    parameters = parameters
                )
            )
        }
    }

    fun runtimeDescriptor(toolName: String): RuntimeToolDescriptor {
        return runtimeDescriptors[toolName] ?: RuntimeToolDescriptor(
            name = toolName,
            displayName = toolName,
            toolType = "builtin"
        )
    }

    fun validateArguments(toolName: String, arguments: JsonObject) {
        val schema = toolSchemas[toolName] ?: return
        validateWithSchema(toolName, schema, arguments)
    }

    private fun validateWithSchema(
        toolName: String,
        schema: JsonObject,
        arguments: JsonObject
    ) {
        val type = schema["type"]?.jsonPrimitive?.contentOrNull?.trim().orEmpty()
        if (type.isNotBlank() && type != "object") {
            throw IllegalArgumentException("Tool $toolName schema type must be object")
        }
        val properties = (schema["properties"] as? JsonObject) ?: JsonObject(emptyMap())
        val requiredFields = (schema["required"] as? JsonArray)
            ?.mapNotNull { it.jsonPrimitive.contentOrNull?.trim() }
            ?.filter { it.isNotEmpty() }
            ?: emptyList()
        requiredFields.forEach { field ->
            if (arguments[field] == null || arguments[field] is JsonNull) {
                throw IllegalArgumentException("Tool $toolName missing required argument: $field")
            }
        }
        arguments.entries.forEach { (field, value) ->
            val propertySchema = properties[field] as? JsonObject ?: return@forEach
            validateFieldType(toolName, field, value, propertySchema)
        }
    }

    private fun validateFieldType(
        toolName: String,
        field: String,
        value: JsonElement,
        propertySchema: JsonObject
    ) {
        val expectedType = propertySchema["type"]?.jsonPrimitive?.contentOrNull?.trim()
        if (!expectedType.isNullOrBlank() && !matchesType(expectedType, value)) {
            throw IllegalArgumentException(
                "Tool $toolName argument $field expected $expectedType but got ${describeType(value)}"
            )
        }
        val enumValues = (propertySchema["enum"] as? JsonArray).orEmpty()
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

    private fun matchesType(expectedType: String, value: JsonElement): Boolean {
        return when (expectedType) {
            "string" -> value is JsonPrimitive && value.isString
            "integer" -> value is JsonPrimitive && !value.isString && value.intOrNull != null
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
                value.intOrNull != null -> "integer"
                value.doubleOrNull != null -> "number"
                else -> "primitive"
            }
        }
    }

    private fun findRemoteTool(
        toolName: String,
        discoveredServers: List<RemoteMcpDiscoveredServer>
    ): RemoteMcpToolDescriptor? {
        return discoveredServers.asSequence()
            .flatMap { it.tools.asSequence() }
            .firstOrNull { it.encodedToolName == toolName }
    }

    private fun toDynamicMcpToolDefinition(tool: RemoteMcpToolDescriptor): JsonObject {
        return buildJsonObject {
            put("type", JsonPrimitive("function"))
            put("function", buildJsonObject {
                put("name", JsonPrimitive(tool.encodedToolName))
                put("displayName", JsonPrimitive(tool.toolName))
                put("toolType", JsonPrimitive("mcp"))
                put("serverName", JsonPrimitive(tool.serverName))
                put(
                    "description",
                    JsonPrimitive(tool.description.ifBlank { "调用远端 MCP 工具。" })
                )
                put("parameters", mapToJsonElement(tool.inputSchema))
            })
        }
    }

    private fun mapToJsonElement(value: Any?): JsonElement {
        return when (value) {
            null -> JsonNull
            is JsonElement -> value
            is Map<*, *> -> JsonObject(
                value.entries.associate { (key, item) ->
                    key.toString() to mapToJsonElement(item)
                }
            )
            is List<*> -> JsonArray(value.map { mapToJsonElement(it) })
            is Boolean -> JsonPrimitive(value)
            is Number -> JsonPrimitive(value)
            else -> JsonPrimitive(value.toString())
        }
    }
}
