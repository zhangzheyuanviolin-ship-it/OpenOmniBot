package com.alibaba.mnnllm.api.openai.network.handlers

import com.alibaba.mnnllm.android.llm.GenerateProgressListener
import com.alibaba.mnnllm.android.llm.LlmSession
import com.alibaba.mnnllm.api.openai.di.ServiceLocator
import com.alibaba.mnnllm.api.openai.network.logging.ChatLogger
import com.alibaba.mnnllm.api.openai.network.utils.ChatResponseFormatter
import com.alibaba.mnnllm.api.openai.network.utils.ThinkingContentStreamParser
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.response.respond
import io.ktor.server.response.respondText
import io.ktor.server.sse.SSEServerContent
import io.ktor.server.sse.heartbeat
import io.ktor.sse.ServerSentEvent
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlin.time.Duration.Companion.seconds

/** * response processoror * responsible for processingstreamingand non-streaming responsegenerateand sending * * mainfunctionality： * - streaming response processor（SSE） * - non-streaming response processor * - unifiederrorprocessand logrecording * - LLM sessionmanaging*/
class ResponseHandler {
    
    private val chatResponseFormatter = ChatResponseFormatter()
    private val logger = ChatLogger()
    private val chatSessionProvider = ServiceLocator.getChatSessionProvider()
    
    companion object {
        private const val HEARTBEAT_PERIOD_SECONDS = 3L
        private const val DONE_DELAY_MS = 100L
        private const val MODEL_NAME = "mnn-llm"
        private const val COMPLETION_CHUNK_OBJECT = "chat.completion.chunk"
        private const val COMPLETION_OBJECT = "chat.completion"
    }

    /** * processwithhistorymessagestreamingresponse * * @param call Ktorapplicationcallcontext * @param history historymessagelist * @param traceId traceID*/
    suspend fun handleStreamResponseWithFullHistory(
        call: ApplicationCall,
        history: List<android.util.Pair<String, String>>,
        traceId: String,
        streamLeadingReasoning: Boolean = false
    ) {
        val responseMetadata = createResponseMetadata()
        val parser = ThinkingContentStreamParser(
            streamLeadingReasoning = streamLeadingReasoning
        )
        
        call.respond(SSEServerContent(call) {
            //set heartbeenat
            heartbeat {
                period = HEARTBEAT_PERIOD_SECONDS.seconds
                event = ServerSentEvent(comments = "keep-alive")
            }

            // Use an unlimited channel to decouple generation (producer) from network sending (consumer).
            // This avoids using runBlocking inside the coroutine and allows the generator to run at full speed
            // without being blocked by network latency, unless we run out of memory (unlikely for text).
            val channel = kotlinx.coroutines.channels.Channel<ServerSentEvent>(kotlinx.coroutines.channels.Channel.UNLIMITED)

            // Producer Coroutine: Runs the LLM inference on IO thread
            launch(kotlinx.coroutines.Dispatchers.IO) {
                var isFinished = false
                try {
                    val llmSession = getLlmSession()
                    if (llmSession != null) {
                        // Process streaming generation
                        val result = llmSession.submitFullHistory(history, object : GenerateProgressListener {
                            override fun onProgress(progress: String?): Boolean {
                                return try {
                                    when {
                                        progress != null -> {
                                            // Send progress token
                                            logger.logStreamDelta(traceId, progress)
                                            val deltas = parser.append(progress)
                                            for (delta in deltas) {
                                                val json = chatResponseFormatter.createDeltaResponse(
                                                    responseMetadata.responseId,
                                                    responseMetadata.created,
                                                    content = delta.content,
                                                    reasoningContent = delta.reasoningContent,
                                                )
                                                val sendResult = channel.trySend(ServerSentEvent(data = json))
                                                if (sendResult.isClosed) {
                                                    logger.logWarning(traceId, "Channel closed, stopping generation")
                                                    return true
                                                }
                                            }
                                            false // Continue generation
                                        }
                                        else -> {
                                            // Generation complete (callback signal)
                                            isFinished = true
                                            logger.logStreamEnd(traceId)
                                            false
                                        }
                                    }
                                } catch (e: Exception) {
                                    logger.logError(traceId, e, "Error in onProgress")
                                    true // Stop generation
                                }
                            }
                        })
                        
                        // Generation complete, send final chunk with usage
                        if (isFinished) {
                            parser.finish().forEach { delta ->
                                channel.send(
                                    ServerSentEvent(
                                        data = chatResponseFormatter.createDeltaResponse(
                                            responseMetadata.responseId,
                                            responseMetadata.created,
                                            content = delta.content,
                                            reasoningContent = delta.reasoningContent,
                                        )
                                    )
                                )
                            }
                            val usage = chatResponseFormatter.createUsageFromMetrics(result)
                            val finalJson = chatResponseFormatter.createDeltaResponse(
                                responseMetadata.responseId,
                                responseMetadata.created,
                                isLast = true,
                                usage = usage
                            )
                            channel.send(ServerSentEvent(data = finalJson))
                            
                            // Send [DONE] marker
                            delay(DONE_DELAY_MS)
                            channel.send(ServerSentEvent(data = "[DONE]"))
                        }
                        logger.logInferenceComplete(traceId)
                    } else {
                        // Process LLM session error
                        logger.logLlmSessionError(traceId)
                        val errorJson = chatResponseFormatter.createDeltaResponse(
                            responseMetadata.responseId,
                            responseMetadata.created,
                            content = "LlmSession not available",
                            isLast = true
                        )
                        channel.send(ServerSentEvent(data = errorJson))
                    }
                } catch (e: Exception) {
                     logger.logError(traceId, e, "Error during generation")
                     if (!isFinished) {
                         // Try to send error finish if possible
                         try {
                             val finalJson = chatResponseFormatter.createDeltaResponse(
                                 responseMetadata.responseId,
                                  responseMetadata.created,
                                 isLast = true
                             )
                             channel.send(ServerSentEvent(data = finalJson))
                             delay(DONE_DELAY_MS)
                             channel.send(ServerSentEvent(data = "[DONE]"))
                         } catch (ignore: Exception) {}
                     }
                } finally {
                    channel.close()
                }
            }

            // Consumer: Read from channel and send via SSE
            // This runs in the context of the SSEServerContent (Netty thread usually)
            try {
                for (event in channel) {
                    send(event)
                }
            } catch (e: Exception) {
                // Check if it's a connection closed exception
                val isConnectionClosed = e is io.ktor.utils.io.ClosedWriteChannelException ||
                        e.cause is io.ktor.utils.io.ClosedWriteChannelException ||
                        e.cause is io.ktor.util.cio.ChannelWriteException ||
                        e.message?.contains("Cannot write to channel") == true ||
                        e.message?.contains("ClosedChannelException") == true
                
                if (isConnectionClosed) {
                    logger.logWarning(traceId, "Client connection closed during send", e)
                } else {
                    logger.logError(traceId, e, "Error sending SSE event")
                }
                // Closing the consumer will cancel the producer (since it's a child job if structured concurrency holds, 
                // but we launched producer with launch(Dispatchers.IO) inside this scope, so yes).
                // Just in case, the channel close in producer's finally block handles cleanup.
            }
        })
    }

    /** * processwithhistorymessagenon-streamingresponse * * @param call Ktorapplicationcallcontext * @param history historymessagelist*/
    suspend fun handleNonStreamResponseWithFullHistory(
        call: ApplicationCall,
        history: List<android.util.Pair<String, String>>,
        streamLeadingReasoning: Boolean = false
    ) {
        val parser = ThinkingContentStreamParser(
            streamLeadingReasoning = streamLeadingReasoning
        )
        val responseMetadata = createResponseMetadata()
        
        var result = HashMap<String, Any>()
        try {
            val llmSession = getLlmSession()
            if (llmSession != null) {
                result = processNonStreamGeneration(llmSession, history, parser)
            } else {
                parser.append("Error: LlmSession not available")
            }
        } catch (e: Exception) {
            parser.append("Error: ${e.message}")
        }
        parser.finish()
        val parsedResult = parser.result()

        val response = createNonStreamResponse(
            responseMetadata,
            content = parsedResult.content,
            reasoningContent = parsedResult.reasoningContent.ifBlank { null },
            metrics = result
        )
        //set correctContent-Typeas application/json
        call.response.headers.append("Content-Type", "application/json")
        call.respondText(response, io.ktor.http.ContentType.Application.Json)
    }
    
    // ========================
    //private helpermethod
    // ========================
    
    /** * response metadata*/
    private data class ResponseMetadata(
        val responseId: String,
        val created: Long
    )
    
    /** * createresponse metadata*/
    private fun createResponseMetadata(): ResponseMetadata {
        val timestamp = System.currentTimeMillis()
        return ResponseMetadata(
            responseId = "chatcmpl-$timestamp",
            created = timestamp / 1000
        )
    }
    
    /**
     * getLLMsession*/
    private fun getLlmSession(): LlmSession? {
        return chatSessionProvider.getLlmSession()
    }
    

    
    /** * processnon-streaminggenerate*/
    private fun processNonStreamGeneration(
        llmSession: LlmSession,
        history: List<android.util.Pair<String, String>>,
        parser: ThinkingContentStreamParser
    ): HashMap<String, Any> {
        return llmSession.submitFullHistory(history, object : GenerateProgressListener {
            override fun onProgress(progress: String?): Boolean {
                progress?.let { parser.append(it) }
                return false //continuegenerate
            }
        })
    }
    
    /** * createnon-streamingresponse*/
    private fun createNonStreamResponse(
        responseMetadata: ResponseMetadata,
        content: String,
        reasoningContent: String?,
        metrics: HashMap<String, Any>
    ): String {
        val usage = chatResponseFormatter.createUsageFromMetrics(metrics)
        return chatResponseFormatter.createChatCompletionResponse(
            responseMetadata.responseId,
            responseMetadata.created,
            content,
            reasoningContent,
            usage
        )
    }
}
