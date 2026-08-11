package com.manukj.edge_gen_ai

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class ToolPromptingTest {
    private val weatherTool =
        EdgeGenAIToolDefinition(
            name = "get_weather",
            descriptionText = "Gets the current weather for a city.",
            parametersSchemaJson =
                """{"type":"object","properties":{"city":{"type":"string",""" +
                    """"description":"The city to get the weather for."}},""" +
                    """"required":["city"]}""",
        )

    @Test
    fun buildToolPreamble_embedsToolSchema() {
        val preamble = ToolPrompting.buildToolPreamble(listOf(weatherTool))

        assertTrue(preamble.contains("get_weather"))
        assertTrue(preamble.contains("Gets the current weather for a city."))
        assertTrue(preamble.contains(weatherTool.parametersSchemaJson))
        assertTrue(preamble.contains("{\"tool\":"))
    }

    @Test
    fun parseToolCall_plainAnswer_returnsNull() {
        assertNull(
            ToolPrompting.parseToolCall("The weather is sunny.", listOf(weatherTool))
        )
    }

    @Test
    fun parseToolCall_unknownTool_returnsNull() {
        assertNull(
            ToolPrompting.parseToolCall(
                "{\"tool\": \"send_email\", \"arguments\": {}}",
                listOf(weatherTool),
            )
        )
    }

    @Test
    fun parseToolCall_validCall_returnsNameAndArguments() {
        val call =
            ToolPrompting.parseToolCall(
                "{\"tool\": \"get_weather\", \"arguments\": {\"city\": \"Oslo\"}}",
                listOf(weatherTool),
            )

        assertEquals("get_weather", call?.toolName)
        assertTrue(call!!.argumentsJson.contains("Oslo"))
    }

    @Test
    fun parseToolCall_toleratesCodeFenceAndTrailingText() {
        val call =
            ToolPrompting.parseToolCall(
                "```json\n{\"tool\": \"get_weather\", \"arguments\": " +
                    "{\"city\": \"Oslo\"}}\n```\nI'll check that for you.",
                listOf(weatherTool),
            )

        assertEquals("get_weather", call?.toolName)
    }

    @Test
    fun parseToolCall_toleratesLeadingAndTrailingText() {
        val call =
            ToolPrompting.parseToolCall(
                "I'll check that for you.\n" +
                    "{\"tool\": \"get_weather\", \"arguments\": {\"city\": \"Oslo\"}}\n" +
                    "One moment, please.",
                listOf(weatherTool),
            )

        assertEquals("get_weather", call?.toolName)
        assertTrue(call!!.argumentsJson.contains("Oslo"))
    }

    @Test
    fun parseToolCall_findsKnownToolAfterUnrelatedJson() {
        val call =
            ToolPrompting.parseToolCall(
                "Metadata: {\"status\": \"starting\"}\n" +
                    "Call: {\"tool\": \"get_weather\", \"arguments\": {\"city\": \"Oslo\"}}",
                listOf(weatherTool),
            )

        assertEquals("get_weather", call?.toolName)
    }

    @Test
    fun parseToolCall_toleratesTextBeforeCodeFence() {
        val call =
            ToolPrompting.parseToolCall(
                "Calling the weather tool:\n```json\n" +
                    "{\"tool\": \"get_weather\", \"arguments\": {\"city\": \"Oslo\"}}\n```",
                listOf(weatherTool),
            )

        assertEquals("get_weather", call?.toolName)
    }

    @Test
    fun parseToolCall_bracesInsideStrings_doNotConfuseParser() {
        val call =
            ToolPrompting.parseToolCall(
                "{\"tool\": \"get_weather\", \"arguments\": {\"city\": \"O{s}lo\"}} extra",
                listOf(weatherTool),
            )

        assertEquals("get_weather", call?.toolName)
        assertTrue(call!!.argumentsJson.contains("O{s}lo"))
    }

    @Test
    fun parseToolCall_missingArguments_defaultsToEmptyObject() {
        val call =
            ToolPrompting.parseToolCall(
                "{\"tool\": \"get_weather\"}",
                listOf(weatherTool),
            )

        assertEquals("{}", call?.argumentsJson)
    }
}
