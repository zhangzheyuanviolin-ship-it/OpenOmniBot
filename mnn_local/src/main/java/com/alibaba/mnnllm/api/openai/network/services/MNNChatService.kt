package com.alibaba.mnnllm.api.openai.network.services

import OpenAIChatRequest
import com.alibaba.mnnllm.android.MnnLlmApplication
import com.alibaba.mnnllm.android.llm.LlmSession
import com.alibaba.mnnllm.android.modelist.ModelListManager
import com.alibaba.mnnllm.android.modelsettings.ModelConfig
import com.alibaba.mnnllm.api.openai.di.ServiceLocator
import com.alibaba.mnnllm.api.openai.manager.ApiServiceManager
import com.alibaba.mnnllm.api.openai.manager.CurrentModelManager
import com.alibaba.mnnllm.api.openai.network.handlers.ResponseHandler
import com.alibaba.mnnllm.api.openai.network.logging.ChatLogger
import com.alibaba.mnnllm.api.openai.network.processors.MnnImageProcessor
import com.alibaba.mnnllm.api.openai.network.queue.RequestQueueManager
import com.alibaba.mnnllm.api.openai.network.utils.MessageTransformer
import com.alibaba.mnnllm.api.openai.network.validators.ChatRequestValidator
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.response.respond
import java.util.UUID

/** * chat service * responsible for coordinatingvarious components,processchatrequestcorebusinesslogic * nowallrequests throughqueuemanagerperformqueueprocess,ensuresame timeonlyoneLLM generationtaskrunning*/
class MNNChatService {

    private data class ThinkingStreamPolicy(
        val modelId: String?,
        val thinkingEnabled: Boolean,
        val streamLeadingReasoning: Boolean
    )

    private val messageTransformer = MessageTransformer()
    private val responseHandler = ResponseHandler()
    private val chatRequestValidator = ChatRequestValidator()
    private val logger = ChatLogger()
    private val requestQueueManager = RequestQueueManager.getInstance()

    //getdependency
    private val chatSessionProvider = ServiceLocator.getChatSessionProvider()
    private val imageProcessor = MnnImageProcessor.getInstance(MnnLlmApplication.getAppContext())
    
    /** * getLLMsessioninstance * @return LlmSessioninstance，if not availablethenthrowexception*/
    private fun getLlmSession(): LlmSession {
        return chatSessionProvider.getLlmSession() 
            ?: throw IllegalStateException("No active LLM session available")
    }

    /** * processchatcompleterequest * nowallrequests willbeen added toqueue,ensureaccording to orderprocess * @param call Ktorapplicationcallcontext * @param chatRequest chat request object * @param traceId traceID*/
    suspend fun processChatCompletion(
        call: ApplicationCall,
        chatRequest: OpenAIChatRequest,
        traceId: String
    ) {
        //generate uniquerequest ID
        val requestId = UUID.randomUUID().toString()
        
        //first performbasic verification,avoidinvalidrequest enteringqueue
        val validationResult = chatRequestValidator.validateChatRequest(chatRequest)
        if (!validationResult.isValid) {
            call.respond(
                HttpStatusCode.BadRequest,
                mapOf("error" to mapOf("message" to validationResult.errorMessage))
            )
            return
        }
        
        logger.logRequestBody(traceId, chatRequest)
        logger.logInfo(traceId, "请求已提交到队列，requestId=$requestId")
        
        //willrequesttoqueueperformqueueprocess,andwaitcomplete
        try {
            requestQueueManager.submitRequest(
                requestId = requestId,
                traceId = traceId,
                task = {
                    //here isactualLLM processinglogic
                    processLlmGeneration(call, chatRequest, traceId)
                },
                onComplete = {
                    logger.logInfo(traceId, "队列任务完成，requestId=$requestId")
                },
                onError = { exception ->
                    logger.logError(traceId, exception, "队列任务失败，requestId=$requestId")
                }
            )
        } catch (e: Exception) {
            logger.logError(traceId, e, "队列处理失败，requestId=$requestId")
            call.respond(
                HttpStatusCode.InternalServerError,
                mapOf(
                    "error" to mapOf(
                        "message" to "Queue processing failed",
                        "trace_id" to traceId
                    )
                )
            )
        }
    }
    
    /** * actualLLMgenerateprocesslogic * thismethodwillatqueueinaccording toorderexecute*/
    private suspend fun processLlmGeneration(
        call: ApplicationCall,
        chatRequest: OpenAIChatRequest,
        traceId: String
    ) {
        try {
            val requestedModelId = chatRequest.model?.trim().orEmpty()
            if (requestedModelId.isNotEmpty() && !ApiServiceManager.ensureModelReady(requestedModelId)) {
                call.respond(
                    HttpStatusCode.ServiceUnavailable,
                    mapOf(
                        "error" to mapOf(
                            "message" to "Failed to load requested model: $requestedModelId",
                            "trace_id" to traceId
                        )
                    )
                )
                return
            }
            val thinkingPolicy = resolveThinkingStreamPolicy(chatRequest, traceId)
            //willas MNNformatunifiedhistory message (containingsystem prompt)
            val unifiedHistory = messageTransformer.convertToUnifiedMnnHistory(
                chatRequest.messages,
                imageProcessor,
                getLlmSession()
            )

            //recordconvertafterhistorymessage
            logger.logTransformedHistory(traceId, unifiedHistory)

            //useunifiedcompletehistorymessageperforminference（APIservicemode）
            if (unifiedHistory.isNotEmpty()) {
                logger.logInferenceStart(traceId, unifiedHistory.size)

                if (chatRequest.stream == true) {
                    responseHandler.handleStreamResponseWithFullHistory(
                        call,
                        unifiedHistory,
                        traceId,
                        streamLeadingReasoning = thinkingPolicy.streamLeadingReasoning
                    )
                } else {
                    responseHandler.handleNonStreamResponseWithFullHistory(
                        call,
                        unifiedHistory,
                        streamLeadingReasoning = thinkingPolicy.streamLeadingReasoning
                    )
                }

                logger.logInferenceComplete(traceId)
            }
        } catch (e: Exception) {
            logger.logError(traceId, e, "LLM生成失败")
            call.respond(
                HttpStatusCode.InternalServerError,
                mapOf(
                    "error" to mapOf(
                        "message" to "Internal server error",
                        "trace_id" to traceId
                    )
                )
            )
        }
    }

    private fun resolveThinkingStreamPolicy(
        chatRequest: OpenAIChatRequest,
        traceId: String
    ): ThinkingStreamPolicy {
        val runtime = ServiceLocator.getLlmRuntimeController()
        val activeModelId = runtime.getActiveModelId()
            ?: CurrentModelManager.getCurrentModelId()
        val isThinkingModel = activeModelId?.let(ModelListManager::isThinkingModel) == true
        val defaultThinkingEnabled = activeModelId
            ?.let { modelId -> ModelConfig.loadConfig(modelId)?.jinja?.context?.enableThinking != false }
            ?: false
        val effectiveThinkingEnabled = chatRequest.enableThinking ?: defaultThinkingEnabled

        val applied = runtime.setThinkingEnabled(effectiveThinkingEnabled)
        logger.logInfo(
            traceId,
            "thinking policy modelId=$activeModelId thinkingModel=$isThinkingModel enableThinking=$effectiveThinkingEnabled applied=$applied"
        )

        return ThinkingStreamPolicy(
            modelId = activeModelId,
            thinkingEnabled = effectiveThinkingEnabled,
            streamLeadingReasoning = isThinkingModel && effectiveThinkingEnabled
        )
    }
    
    /** * getqueuestatisticsinfo*/
    fun getQueueStats() = requestQueueManager.getQueueStats()
}
