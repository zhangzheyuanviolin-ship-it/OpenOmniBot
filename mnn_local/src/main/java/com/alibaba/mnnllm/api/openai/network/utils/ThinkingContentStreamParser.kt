package com.alibaba.mnnllm.api.openai.network.utils

/**
 * Converts local-model raw output that may contain inline think markers into
 * standard reasoning/content channels for the OpenAI-compatible API.
 *
 * We intentionally keep the prefix before the first `</think>` buffered until it
 * can be classified, because local models may omit the opening `<think>` tag.
 */
class ThinkingContentStreamParser(
    private val streamLeadingReasoning: Boolean = false
) {

    data class DeltaPayload(
        val content: String? = null,
        val reasoningContent: String? = null
    )

    data class ParsedResult(
        val content: String,
        val reasoningContent: String
    )

    companion object {
        private const val THINK_OPEN_TAG = "<think>"
        private const val THINK_CLOSE_TAG = "</think>"
        private val INLINE_THINK_TAGS = listOf(THINK_OPEN_TAG, THINK_CLOSE_TAG)
    }

    private val pendingBuffer = StringBuilder()
    private val contentBuffer = StringBuilder()
    private val reasoningBuffer = StringBuilder()
    private var thinkSectionOpen = false
    private var inlineThinkTagObserved = false

    fun append(text: String): List<DeltaPayload> {
        if (text.isEmpty()) {
            return emptyList()
        }
        pendingBuffer.append(text)
        return flush(final = false)
    }

    fun finish(): List<DeltaPayload> = flush(final = true)

    fun result(): ParsedResult {
        return ParsedResult(
            content = contentBuffer.toString(),
            reasoningContent = reasoningBuffer.toString()
        )
    }

    private fun flush(final: Boolean): List<DeltaPayload> {
        val emitted = mutableListOf<DeltaPayload>()
        while (pendingBuffer.isNotEmpty()) {
            val bufferText = pendingBuffer.toString()
            if (thinkSectionOpen) {
                val closeIndex = bufferText.indexOf(THINK_CLOSE_TAG)
                if (closeIndex >= 0) {
                    emitReasoning(bufferText.substring(0, closeIndex), emitted)
                    pendingBuffer.delete(0, closeIndex + THINK_CLOSE_TAG.length)
                    thinkSectionOpen = false
                    inlineThinkTagObserved = true
                    continue
                }

                if (final) {
                    emitReasoning(bufferText, emitted)
                    pendingBuffer.setLength(0)
                    return emitted
                }

                val retainedLength = partialInlineTagSuffixLength(bufferText)
                val safeLength = pendingBuffer.length - retainedLength
                if (safeLength <= 0) {
                    return emitted
                }
                emitReasoning(bufferText.substring(0, safeLength), emitted)
                pendingBuffer.delete(0, safeLength)
                return emitted
            }

            val openIndex = bufferText.indexOf(THINK_OPEN_TAG)
            val closeIndex = bufferText.indexOf(THINK_CLOSE_TAG)

            if (openIndex >= 0 && (closeIndex < 0 || openIndex < closeIndex)) {
                emitContent(bufferText.substring(0, openIndex), emitted)
                pendingBuffer.delete(0, openIndex + THINK_OPEN_TAG.length)
                thinkSectionOpen = true
                inlineThinkTagObserved = true
                continue
            }

            if (closeIndex >= 0) {
                if (contentBuffer.isEmpty()) {
                    emitReasoning(bufferText.substring(0, closeIndex), emitted)
                } else {
                    emitContent(bufferText.substring(0, closeIndex), emitted)
                }
                pendingBuffer.delete(0, closeIndex + THINK_CLOSE_TAG.length)
                inlineThinkTagObserved = true
                continue
            }

            if (final) {
                if (streamLeadingReasoning && !inlineThinkTagObserved && contentBuffer.isEmpty()) {
                    emitReasoning(bufferText, emitted)
                } else {
                    emitContent(bufferText, emitted)
                }
                pendingBuffer.setLength(0)
                return emitted
            }

            if (!inlineThinkTagObserved && contentBuffer.isEmpty()) {
                if (!streamLeadingReasoning) {
                    return emitted
                }
                val retainedLength = partialInlineTagSuffixLength(bufferText)
                val safeLength = pendingBuffer.length - retainedLength
                if (safeLength <= 0) {
                    return emitted
                }
                emitReasoning(bufferText.substring(0, safeLength), emitted)
                pendingBuffer.delete(0, safeLength)
                return emitted
            }

            val retainedLength = partialInlineTagSuffixLength(bufferText)
            val safeLength = pendingBuffer.length - retainedLength
            if (safeLength <= 0) {
                return emitted
            }
            emitContent(bufferText.substring(0, safeLength), emitted)
            pendingBuffer.delete(0, safeLength)
            return emitted
        }
        return emitted
    }

    private fun emitContent(text: String, emitted: MutableList<DeltaPayload>) {
        if (text.isEmpty()) {
            return
        }
        contentBuffer.append(text)
        emitted += DeltaPayload(content = text)
    }

    private fun emitReasoning(text: String, emitted: MutableList<DeltaPayload>) {
        if (text.isEmpty()) {
            return
        }
        reasoningBuffer.append(text)
        emitted += DeltaPayload(reasoningContent = text)
    }

    private fun partialInlineTagSuffixLength(text: String): Int {
        var longest = 0
        INLINE_THINK_TAGS.forEach { tag ->
            val upperBound = minOf(text.length, tag.length - 1)
            for (candidate in upperBound downTo 1) {
                if (text.endsWith(tag.substring(0, candidate))) {
                    longest = maxOf(longest, candidate)
                    break
                }
            }
        }
        return longest
    }
}
