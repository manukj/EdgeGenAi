package com.manukj.edge_gen_ai

import com.google.mlkit.genai.schema.guided.GenerableProvider
import java.util.ServiceLoader
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.json.JSONObject

internal class ToolDecisionTest {
    private val definition =
            EdgeGenAIToolDefinition(
                    "remind",
                    "Create reminders",
                    """{"type":"object","properties":{
            "items":{"type":"array","minItems":1,"maxItems":2,"items":{
                "type":"object","properties":{
                    "title":{"type":"string"},
                    "priority":{"type":"string","enum":["low","high"]},
                    "minutes":{"type":"integer","minimum":1,"maximum":60},
                    "enabled":{"type":"boolean"}
                },"required":["title","priority","minutes","enabled"]
            }}
        },"required":["items"]}""",
            )
    private fun decision(arguments: String) = ToolDecision("tool", "remind", arguments, "")

    @Test
    fun generatedSchemaIsDiscoverableAtRuntime() {
        val providers = ServiceLoader.load(GenerableProvider::class.java).toList()
        assertTrue(providers.any { it.targetClass == ToolDecision::class })
    }

    @Test
    fun validNestedArgumentsProduceToolCall() {
        val call =
                decision(
                                """{"items":[{"title":"Walk","priority":"high","minutes":5,"enabled":true}]}"""
                        )
                        .toolCall(listOf(definition))
        assertNotNull(call)
        assertEquals("remind", call.toolName)
        assertEquals(
                5,
                JSONObject(call.argumentsJson)
                        .getJSONArray("items")
                        .getJSONObject(0)
                        .getInt("minutes")
        )
    }

    @Test
    fun invalidArgumentsAreRejectedBeforeExecution() {
        val invalid =
                listOf(
                        "{}",
                        """{"items":[]}""",
                        """{"items":[{"title":"Walk","priority":"urgent","minutes":5,"enabled":true}]}""",
                        """{"items":[{"title":"Walk","priority":"high","minutes":"5","enabled":true}]}""",
                        """{"items":[{"title":"Walk","priority":"high","minutes":0,"enabled":true}]}""",
                        """{"items":[{"title":"Walk","priority":"high","minutes":61,"enabled":true}]}""",
                        """{"items":[{"title":"Walk","priority":"high","minutes":1.5,"enabled":true}]}""",
                        """{"items":[{"title":null,"priority":"high","minutes":5,"enabled":true}]}""",
                        """{"items":[{"title":"Walk","priority":"high","minutes":5,"enabled":"true"}]}""",
                        """{"items":[{"title":"Walk","priority":"high","minutes":5,"enabled":true,"extra":1}]}""",
                        "[]",
                        "{} trailing text",
                )
        invalid.forEach { arguments ->
            assertFailsWith<IllegalArgumentException>(arguments) {
                decision(arguments).toolCall(listOf(definition))
            }
        }
    }

    @Test
    fun answerAndUnknownToolDecisions() {
        assertNull(ToolDecision("answer", "", "{}", "Hello").toolCall(listOf(definition)))
        assertFailsWith<IllegalArgumentException> {
            ToolDecision("tool", "unknown", "{}", "").toolCall(listOf(definition))
        }
        assertFailsWith<IllegalArgumentException> {
            ToolDecision("other", "", "{}", "").toolCall(listOf(definition))
        }
        assertFailsWith<IllegalArgumentException> {
            ToolDecision("answer", "remind", "{}", "Hello").toolCall(listOf(definition))
        }
    }

    @Test
    fun noArgumentToolsAcceptEmptyObject() {
        val noArgs =
                EdgeGenAIToolDefinition(
                        "battery",
                        "Read battery",
                        """{"type":"object","properties":{},"required":[]}"""
                )
        assertNotNull(ToolDecision("tool", "battery", "{}", "").toolCall(listOf(noArgs)))
    }

    @Test
    fun toolPreambleAndContinuationUseTypedEnvelope() {
        val call = ParsedToolCall("remind", "{}", """{"tool":"remind","arguments":{}}""")
        val preamble = ToolPrompting.buildToolPreamble(listOf(definition))
        assertTrue(preamble.contains("ToolDecision"))
        val continuation = ToolPrompting.buildToolResultContinuation(call, "Created")
        assertTrue(continuation.contains("Created"))
        assertTrue(continuation.contains("ToolDecision"))
    }
}
