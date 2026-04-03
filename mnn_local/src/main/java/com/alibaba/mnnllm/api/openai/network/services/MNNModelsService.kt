package com.alibaba.mnnllm.api.openai.network.services

import com.alibaba.mnnllm.api.openai.network.logging.ChatLogger
import com.alibaba.mnnllm.api.openai.network.models.ModelData
import com.alibaba.mnnllm.api.openai.network.models.ModelPermission
import com.alibaba.mnnllm.api.openai.network.models.ModelsResponse
import com.alibaba.mnnllm.android.modelist.ModelListManager
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.call
import io.ktor.server.response.respond
import timber.log.Timber

/** * MNN modelservice * responsible forprocessmodelrelatedbusinesslogic*/
class MNNModelsService {
    private val logger = ChatLogger()

    suspend fun getAvailableModels(call: io.ktor.server.application.ApplicationCall, traceId: String) {
        try {
            logger.logRequestStart(traceId, call)

            val availableModels = ModelListManager.getCurrentModels().orEmpty()
                .mapNotNull { wrapper -> wrapper.modelItem.modelId?.trim()?.takeIf { it.isNotEmpty() } }
                .distinct()
                .sorted()
            if (availableModels.isEmpty()) {
                Timber.tag("MNNModelsService").w("No installed local model available")
                logger.logError(traceId, Exception("No installed local model available"), "No installed local model available")
                call.respond(HttpStatusCode.ServiceUnavailable, mapOf("error" to "No installed local model available"))
                return
            }

            val createdAt = System.currentTimeMillis() / 1000
            val modelDataList = availableModels.map { modelId ->
                ModelData(
                    id = modelId,
                    created = System.currentTimeMillis() / 1000, // Unix timestamp
                    permission = listOf(
                        ModelPermission(
                            id = "modelperm-$modelId",
                            created = createdAt
                        )
                    )
                )
            }

            val response = ModelsResponse(data = modelDataList)

            call.respond(response)
            logger.logInfo(traceId, "Installed local models returned successfully: count=${modelDataList.size}")

        } catch (e: Exception) {
            Timber.tag("MNNModelsService").e(e, "Error getting installed local models")
            logger.logError(traceId, e, "Failed to get installed local models")
            call.respond(HttpStatusCode.InternalServerError, mapOf("error" to "Failed to get installed local models"))
        }
    }
}
