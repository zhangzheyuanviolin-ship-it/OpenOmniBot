package com.ai.assistance.operit.terminal

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.io.InterruptedIOException

class TerminalManagerTest {
    @Test
    fun `reader close interruption is treated as expected termination`() {
        assertTrue(
            isExpectedHiddenExecReaderTermination(
                InterruptedIOException("read interrupted by close() on another thread")
            )
        )
    }

    @Test
    fun `wrapped closed stream io exception is treated as expected termination`() {
        assertTrue(
            isExpectedHiddenExecReaderTermination(
                IllegalStateException("wrapper", IOException("stream closed"))
            )
        )
    }

    @Test
    fun `ordinary io exception is not treated as expected termination`() {
        assertFalse(
            isExpectedHiddenExecReaderTermination(
                IOException("permission denied")
            )
        )
    }
}
