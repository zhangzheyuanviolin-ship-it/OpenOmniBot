package cn.com.omnimind.bot.mcp

import android.content.Context
import android.util.Base64
import cn.com.omnimind.baselib.util.OmniLog
import cn.com.omnimind.bot.utg.UtgBridge
import cn.com.omnimind.bot.util.AssistsUtil
import com.tencent.mmkv.MMKV
import io.ktor.http.ContentDisposition
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.serialization.gson.gson
import io.ktor.server.application.call
import io.ktor.server.application.install
import io.ktor.server.auth.Authentication
import io.ktor.server.auth.UserIdPrincipal
import io.ktor.server.auth.bearer
import io.ktor.server.auth.authenticate
import io.ktor.server.cio.CIO
import io.ktor.server.cio.CIOApplicationEngine
import io.ktor.server.engine.EmbeddedServer
import io.ktor.server.engine.embeddedServer
import io.ktor.server.plugins.calllogging.CallLogging
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.request.receive
import io.ktor.server.request.host
import io.ktor.server.response.header
import io.ktor.server.response.respond
import io.ktor.server.response.respondFile
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.routing
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.io.File
import java.security.SecureRandom
import java.util.UUID

/**
 * 简单的局域网 MCP 服务管理器，负责启动、鉴权、停止与状态查询。
 */
object McpServerManager {
    private const val TAG = "[McpServerManager]"
    private const val LOCALHOST_HOST = "127.0.0.1"
    private const val PREF_ENABLE = "mcp_server_enabled"
    private const val PREF_HOST = "mcp_server_host"
    private const val PREF_TOKEN = "mcp_server_token"
    private const val PREF_PORT = "mcp_server_port"
    private const val DEFAULT_PORT = 8899

    private val mmkv by lazy { MMKV.defaultMMKV() }
    private val serverScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val serverLock = Any()

    @Volatile
    private var server: EmbeddedServer<CIOApplicationEngine, CIOApplicationEngine.Configuration>? = null

    @Volatile
    private var isRunning: Boolean = false

    @Volatile
    private var activeHost: String? = null

    // ==================== 公共 API ====================

    fun restoreIfEnabled(context: Context) {
        if (!mmkv.decodeBool(PREF_ENABLE, false)) return
        val port = mmkv.decodeInt(PREF_PORT, DEFAULT_PORT).takeIf { it > 0 } ?: DEFAULT_PORT
        serverScope.launch {
            runCatching { startServer(context, port) }
                .onFailure { OmniLog.e(TAG, "restoreIfEnabled failed: ${it.message}") }
        }
    }

    fun setEnabled(context: Context, enable: Boolean, port: Int? = null): McpServerState {
        if (enable) {
            val targetPort = port ?: mmkv.decodeInt(PREF_PORT, DEFAULT_PORT).takeIf { it > 0 } ?: DEFAULT_PORT
            return startServer(context, targetPort)
        } else {
            stopServer()
            mmkv.encode(PREF_ENABLE, false)
        }
        return currentState()
    }

    fun refreshToken(context: Context): McpServerState {
        val newToken = generateToken()
        mmkv.encode(PREF_TOKEN, newToken)
        if (isRunning || mmkv.decodeBool(PREF_ENABLE, false)) {
            return restart(context)
        }
        return currentState()
    }

    fun currentState(): McpServerState {
        val resolvedHost = resolveAdvertisedHost()
        return McpServerState(
            enabled = mmkv.decodeBool(PREF_ENABLE, false) && isRunning,
            running = isRunning,
            host = resolvedHost,
            port = mmkv.decodeInt(PREF_PORT, DEFAULT_PORT).takeIf { it > 0 } ?: DEFAULT_PORT,
            token = ensureToken(),
        )
    }

    fun ensureRunning(context: Context): McpServerState {
        if (isRunning) {
            return currentState()
        }
        val port = mmkv.decodeInt(PREF_PORT, DEFAULT_PORT).takeIf { it > 0 } ?: DEFAULT_PORT
        return startServer(context, port)
    }

    fun stopServer() {
        synchronized(serverLock) {
            stopServerLocked()
        }
    }

    fun getActiveTasks(): List<Map<String, Any?>> = McpTaskManager.getActiveTasks()

    fun cleanupExpiredTasks(maxAgeMs: Long = 600_000) = McpTaskManager.cleanupExpiredTasks(maxAgeMs)

    // ==================== 私有方法 ====================

    private fun restart(context: Context): McpServerState {
        val port = mmkv.decodeInt(PREF_PORT, DEFAULT_PORT).takeIf { it > 0 } ?: DEFAULT_PORT
        synchronized(serverLock) {
            stopServerLocked()
        }
        return startServer(context, port)
    }

    private fun startServer(context: Context, port: Int): McpServerState {
        synchronized(serverLock) {
            try {
                val lanIp = resolveLanIp() ?: LOCALHOST_HOST
                if (isRunning) {
                    val currentPort = mmkv.decodeInt(PREF_PORT, DEFAULT_PORT).takeIf { it > 0 } ?: DEFAULT_PORT
                    if (currentPort == port) {
                        activeHost = lanIp
                        mmkv.encode(PREF_HOST, lanIp)
                        return currentState()
                    }
                    stopServerLocked()
                }
                val engine = buildServer(context, port)
                engine.start(wait = false)

                server = engine
                isRunning = true
                activeHost = lanIp
                mmkv.encode(PREF_ENABLE, true)
                mmkv.encode(PREF_PORT, port)
                mmkv.encode(PREF_HOST, lanIp)
                OmniLog.i(TAG, "MCP server started at http://$lanIp:$port")
                return currentState()
            } catch (t: Throwable) {
                server = null
                isRunning = false
                activeHost = null
                OmniLog.e(TAG, "startServer failed: ${t.message}")
                throw t
            }
        }
    }

    private fun buildServer(
        context: Context,
        port: Int
    ): EmbeddedServer<CIOApplicationEngine, CIOApplicationEngine.Configuration> {
        val token = ensureToken()
        return embeddedServer(CIO, host = "0.0.0.0", port = port) {
            install(CallLogging)
            install(ContentNegotiation) { gson() }
            install(Authentication) {
                bearer("bearer-auth") {
                    authenticate { credential ->
                        if (credential.token == token) UserIdPrincipal("mcp-client") else null
                    }
                }
            }
            routing {
                // 健康检查（无需认证）
                get("/mcp/health") {
                    call.respond(mapOf("status" to "ok"))
                }
                // 文件下载（使用文件token或Bearer token）
                get("/mcp/file/{fileId}") { handleFileDownload(call) }
                
                authenticate("bearer-auth") {
                    // 服务状态
                    get("/mcp/state") {
                        call.respond(currentState().toMap())
                    }

                    post("/utg/observe") {
                        val params = call.receive<Map<String, Any?>>() ?: emptyMap()
                        val result = UtgBridge.captureObservation(
                            UtgBridge.ObservationRequest(
                                xml = params["xml"] == true,
                                appInfo = params["app_info"] == true,
                                screenshot = params["screenshot"] == true,
                                waitToStabilize = params["wait_to_stabilize"] == true,
                            )
                        )
                        call.respond(result)
                    }

                    post("/utg/act") {
                        val params = call.receive<Map<String, Any?>>() ?: emptyMap()
                        val action = params["action"] as? Map<String, Any?> ?: emptyMap()
                        val result = UtgBridge.executeAction(
                            UtgBridge.ActRequest(
                                action = UtgBridge.ActionEnvelope(
                                    type = action["type"]?.toString().orEmpty(),
                                    params = (action["params"] as? Map<String, Any?>) ?: emptyMap(),
                                )
                            )
                        )
                        call.respond(result)
                    }

                    post("/utg/confirm") {
                        val params = call.receive<Map<String, Any?>>() ?: emptyMap()
                        val prompt = params["prompt"]?.toString().orEmpty()
                        val result = UtgBridge.requestConfirmation(prompt)
                        call.respond(result)
                    }
                    
                    // MCP JSON-RPC 端点
                    post("/mcp") { handleJsonRpc(call, context) }
                    
                    // 工具发现
                    get("/mcp/list_tools") { call.respond(mapOf("tools" to McpToolDefinitions.allTools)) }
                    post("/mcp/list_tools") { call.respond(mapOf("tools" to McpToolDefinitions.allTools)) }
                    
                    // REST 风格工具调用
                    post("/mcp/call_tool") {
                        val params = call.receive<Map<String, Any?>>()
                        val result = executeTool(context, params["name"] as? String, params["arguments"] as? Map<String, Any?>)
                        call.respond(result)
                    }
                    
                    // 传统 VLM 任务端点（保持兼容）
                    post("/mcp/v1/task/vlm") { handleLegacyVlmTask(call, context) }
                    
                    // 任务状态查询
                    get("/mcp/v1/task/{taskId}/status") {
                        val taskId = call.parameters["taskId"]
                        val state = taskId?.let { McpTaskManager.getTask(it) }
                        if (state == null) {
                            call.respond(HttpStatusCode.NotFound, mapOf("error" to "Task not found"))
                        } else {
                            call.respond(state.toResponseMap())
                        }
                    }
                    
                    // 任务回复
                    post("/mcp/v1/task/{taskId}/reply") { handleLegacyTaskReply(call) }
                }
            }
        }
    }

    private fun stopServerLocked() {
        runCatching {
            server?.stop(500, 1_500)
        }.onFailure {
            OmniLog.e(TAG, "stopServer error: ${it.message}")
        }
        server = null
        isRunning = false
        activeHost = null
    }

    private fun resolveLanIp(): String? {
        return runCatching { McpNetworkUtils.currentLanIp() }
            .onFailure { OmniLog.e(TAG, "resolveLanIp failed: ${it.message}") }
            .getOrNull()
    }

    private fun resolveAdvertisedHost(): String? {
        val currentHost = resolveLanIp()
        if (currentHost != null && isRunning) {
            synchronized(serverLock) {
                if (isRunning && activeHost != currentHost) {
                    activeHost = currentHost
                    mmkv.encode(PREF_HOST, currentHost)
                }
            }
        }
        if (currentHost != null) return currentHost
        return if (isRunning) {
            activeHost ?: mmkv.decodeString(PREF_HOST)
        } else {
            null
        }
    }

    // ==================== JSON-RPC 处理 ====================

    private suspend fun handleJsonRpc(call: io.ktor.server.application.ApplicationCall, context: Context) {
        val request = runCatching { call.receive<Map<String, Any?>>() }.getOrNull()
        if (request == null) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Invalid JSON"))
            return
        }
        val id = request["id"]
        val method = request["method"] as? String

        val response = when (method) {
            "initialize" -> mapOf(
                "jsonrpc" to "2.0",
                "id" to id,
                "result" to mapOf(
                    "protocolVersion" to "2024-11-05",
                    "capabilities" to mapOf("tools" to mapOf<String, Any>()),
                    "serverInfo" to mapOf("name" to "小万Mcp", "version" to "1.0")
                )
            )
            "notifications/initialized" -> null
            "tools/list" -> mapOf(
                "jsonrpc" to "2.0",
                "id" to id,
                "result" to mapOf("tools" to McpToolDefinitions.allTools)
            )
            "tools/call" -> {
                val params = request["params"] as? Map<String, Any?>
                val name = params?.get("name") as? String
                val args = params?.get("arguments") as? Map<String, Any?>
                val execResult = executeTool(context, name, args)
                mapOf("jsonrpc" to "2.0", "id" to id, "result" to execResult)
            }
            else -> {
                if (method?.startsWith("$/") == true || method?.startsWith("notifications/") == true) null
                else mapOf(
                    "jsonrpc" to "2.0",
                    "id" to id,
                    "error" to mapOf("code" to -32601, "message" to "Method not found: $method")
                )
            }
        }
        
        if (response != null) {
            call.respond(response)
        } else {
            call.respond(HttpStatusCode.OK)
        }
    }

    // ==================== 文件下载 ====================

    private suspend fun handleFileDownload(call: io.ktor.server.application.ApplicationCall) {
        val fileId = call.parameters["fileId"]
        if (fileId.isNullOrBlank()) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Missing fileId"))
            return
        }

        val record = McpFileInbox.getFile(fileId)
        if (record == null) {
            call.respond(HttpStatusCode.NotFound, mapOf("error" to "File not found"))
            return
        }

        val token = call.request.queryParameters["token"]
        val authHeader = call.request.headers["Authorization"]
        val bearerToken = authHeader?.removePrefix("Bearer ")?.trim()
        val bearerOk = bearerToken == currentState().token
        val tokenOk = McpFileInbox.isTokenValid(record, token)

        if (!tokenOk && !bearerOk) {
            call.respond(HttpStatusCode.Forbidden, mapOf("error" to "Invalid token"))
            return
        }

        val file = File(record.path)
        if (!file.exists()) {
            McpFileInbox.removeFile(fileId)
            call.respond(HttpStatusCode.Gone, mapOf("error" to "File expired"))
            return
        }

        call.response.header(
            HttpHeaders.ContentDisposition,
            ContentDisposition.Attachment.withParameter(ContentDisposition.Parameters.FileName, record.fileName).toString()
        )
        call.response.header(HttpHeaders.CacheControl, "no-store")
        call.respondFile(file)
    }

    // ==================== 工具执行 ====================

    private suspend fun executeTool(context: Context, name: String?, args: Map<String, Any?>?): Map<String, Any?> {
        return when (name) {
            "vlm_task" -> McpToolExecutors.executeVlmTask(context, args, serverScope)
            "task_status" -> McpToolExecutors.executeTaskStatus(args)
            "task_reply" -> McpToolExecutors.executeTaskReply(args)
            "task_wait_unlock" -> McpToolExecutors.executeTaskWaitUnlock(context, args, serverScope)
            "file_transfer" -> McpToolExecutors.executeFileTransfer(args)
            else -> McpResponseBuilder.buildErrorText("Unknown tool: $name")
        }
    }

    // ==================== 传统端点处理（保持兼容） ====================

    private suspend fun handleLegacyVlmTask(call: io.ktor.server.application.ApplicationCall, context: Context) {
        val remoteHost = call.request.headers["X-Forwarded-For"]
            ?.split(",")
            ?.firstOrNull()
            ?.trim()
            ?: call.request.headers["X-Real-IP"]
            ?: call.request.host()
            
        if (!McpNetworkUtils.isLanAddress(remoteHost)) {
            call.respond(HttpStatusCode.Forbidden, mapOf("error" to "LAN_ONLY"))
            return
        }
        
        val payload = runCatching { call.receive<VlmTaskRequest>() }
            .getOrElse {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "INVALID_BODY"))
                return
            }
            
        if (payload.goal.isBlank()) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "EMPTY_GOAL"))
            return
        }
        
        val taskId = UUID.randomUUID().toString()
        val args = mapOf(
            "goal" to payload.goal,
            "model" to payload.model,
            "packageName" to payload.packageName,
            "needSummary" to payload.needSummary
        )
        
        val result = McpToolExecutors.executeVlmTask(context, args, serverScope)
        call.respond(HttpStatusCode.OK, result)
    }

    private suspend fun handleLegacyTaskReply(call: io.ktor.server.application.ApplicationCall) {
        val taskId = call.parameters["taskId"]
        val body = call.receive<Map<String, Any?>>()
        val reply = body["reply"] as? String ?: body["input"] as? String
        
        if (taskId == null || reply == null) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Missing taskId or reply"))
            return
        }
        
        val state = McpTaskManager.getTask(taskId)
        if (state == null) {
            call.respond(HttpStatusCode.NotFound, mapOf("error" to "Task not found"))
            return
        }
        
        if (state.status != TaskStatus.WAITING_INPUT) {
            call.respond(HttpStatusCode.Conflict, mapOf("error" to "Task is not waiting for input", "status" to state.status.name))
            return
        }
        
        val success = AssistsUtil.Core.provideUserInputToVLMTask(reply)
        if (success) {
            state.status = TaskStatus.RUNNING
            state.waitingQuestion = null
            call.respond(mapOf("success" to true, "taskId" to taskId, "status" to "RUNNING"))
        } else {
            call.respond(HttpStatusCode.InternalServerError, mapOf("error" to "Failed to provide input"))
        }
    }

    // ==================== Token 管理 ====================

    private fun ensureToken(): String {
        val saved = mmkv.decodeString(PREF_TOKEN)
        if (!saved.isNullOrBlank()) return saved
        val token = generateToken()
        mmkv.encode(PREF_TOKEN, token)
        return token
    }

    private fun generateToken(): String {
        val random = SecureRandom()
        val buffer = ByteArray(32)
        random.nextBytes(buffer)
        return Base64.encodeToString(buffer, Base64.NO_WRAP or Base64.URL_SAFE)
    }
}
