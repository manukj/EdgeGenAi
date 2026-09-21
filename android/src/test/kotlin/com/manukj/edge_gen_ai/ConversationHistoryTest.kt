package com.manukj.edge_gen_ai

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.assertFalse
import kotlin.test.assertFailsWith
import kotlin.test.assertSame
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking

internal class ConversationHistoryTest {
    @Test
    fun firstAndSecondMessages() = runBlocking {
        val empty = ConversationHistory()
        assertEquals("Hi", empty.buildPrompt("Hi"))
        val history = empty.append("Hi", "Hello")
        val prepared = history.prepare("Next", { true }, { _, _ -> error("Unexpected summary") })
        assertSame(history, prepared)
        assertEquals("User: Hi\nModel: Hello\nUser: Next", prepared.buildPrompt("Next"))
        assertEquals(emptyList(), empty.turns)
    }

    @Test
    fun overflowSummarizesOldMessagesAndKeepsTwoRecentTurns() = runBlocking {
        val history = ConversationHistory()
            .append("old".repeat(100), "old answer")
            .append("recent1", "answer1").append("recent2", "answer2")
        var calls = 0
        val compacted = history.prepare("next", { it.length < 200 }, { previous, older ->
            calls++
            assertEquals("", previous)
            assertTrue(older.contains("old answer"))
            assertFalse(older.contains("recent1"))
            "Remember old facts"
        })
        assertEquals(1, calls)
        assertEquals(2, compacted.turns.size)
        assertTrue(compacted.buildPrompt("next").contains("Remember old facts"))
        assertEquals(3, history.turns.size)
        assertEquals("", history.summary)
    }

    @Test
    fun nextMessageReusesSummaryWithoutAnotherInference() = runBlocking {
        val history = ConversationHistory("Old facts").append("recent", "reply")
        val prepared = history.prepare("next", { true }, { _, _ -> error("Unexpected summary") })
        assertSame(history, prepared)
        assertTrue(prepared.buildPrompt("next").contains("Old facts"))
    }

    @Test
    fun repeatedOverflowFoldsExistingSummaryIntoNewSummary() = runBlocking {
        val history = ConversationHistory("Previous facts")
            .append("older".repeat(100), "answer")
            .append("recent1", "answer1").append("recent2", "answer2")
        val compacted = history.prepare("next", { it.length < 200 }, { previous, older ->
            assertEquals("Previous facts", previous)
            assertTrue(older.contains("older"))
            "Previous facts plus newer facts"
        })
        assertEquals("Previous facts plus newer facts", compacted.summary)
        assertEquals(2, compacted.turns.size)
    }

    @Test
    fun oversizedRecentTurnIsSummarizedToo() = runBlocking {
        val history = ConversationHistory().append("huge".repeat(100), "reply")
        val compacted = history.prepare("next", { it.length < 100 }, { _, _ -> "Facts" })
        assertEquals("Facts", compacted.summary)
        assertTrue(compacted.turns.isEmpty())
    }

    @Test
    fun oversizedNewMessageFailsWithoutSummarizing() = runBlocking {
        val history = ConversationHistory().append("hello", "reply")
        assertFailsWith<IllegalArgumentException> {
            history.prepare("x".repeat(300), { it.length < 100 }, { _, _ -> error("Unexpected summary") })
        }
        assertEquals(1, history.turns.size)
    }

    @Test
    fun failedEmptyOrCancelledSummaryPreservesOriginalHistory() = runBlocking {
        val history = ConversationHistory("original").append("x".repeat(300), "reply")
        assertFailsWith<IllegalStateException> {
            history.prepare("next", { it.length < 100 }, { _, _ -> error("inference failed") })
        }
        assertFailsWith<IllegalStateException> {
            history.prepare("next", { it.length < 100 }, { _, _ -> " " })
        }
        assertFailsWith<CancellationException> {
            history.prepare("next", { it.length < 100 }, { _, _ -> throw CancellationException() })
        }
        assertEquals("original", history.summary)
        assertEquals(1, history.turns.size)
    }

    @Test
    fun unfitSummaryFailsWithoutInfiniteRetriesOrDroppingFacts() = runBlocking {
        val history = ConversationHistory().append("x".repeat(300), "reply")
        var calls = 0
        assertFailsWith<IllegalStateException> {
            history.prepare("next", { it.length < 100 }, { _, _ ->
                calls++
                "summary".repeat(100)
            })
        }
        assertEquals(1, calls)
        assertEquals(1, history.turns.size)
    }

    @Test
    fun summaryChunksFitAndCarryForwardEarlierSummary() = runBlocking {
        val inputs = mutableListOf<String>()
        val summarizer = ConversationSummarizer(
            fits = { it.length <= 800 },
            generate = { prompt ->
                assertTrue(prompt.length <= 800)
                inputs.add(prompt)
                "summary-${inputs.size}"
            },
        )
        val result = summarizer.summarize("original facts", "z".repeat(1500))
        assertTrue(inputs.size > 1)
        assertTrue(inputs.first().contains("original facts"))
        inputs.drop(1).forEachIndexed { index, prompt ->
            assertTrue(prompt.contains("summary-${index + 1}"))
        }
        // Every character of the older transcript was included in exactly one chunk.
        assertEquals(1500, inputs.sumOf { it.substringAfter("Older messages (may be a portion of a long message):").count { c -> c == 'z' } })
        assertEquals("summary-${inputs.size}", result)
    }

    @Test
    fun summaryInstructionTooLargeFailsBeforeInference() = runBlocking {
        val summarizer = ConversationSummarizer(
            fits = { false },
            generate = { error("Unexpected inference") },
        )
        assertFailsWith<IllegalStateException> { summarizer.summarize("", "old") }
        Unit
    }

    @Test
    fun newSessionContainsNeitherSummaryNorPreviousTurns() {
        val first = ConversationHistory("private facts").append("hello", "reply")
        val second = ConversationHistory()
        assertEquals("new", second.buildPrompt("new"))
        assertTrue(first.buildPrompt("next").contains("private facts"))
    }
}
