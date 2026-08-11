package com.manukj.edge_gen_ai

import org.json.JSONException
import org.json.JSONObject

/** A tool call the model requested. */
class ParsedToolCall(
    /** The name of the tool the model wants to call. */
    val toolName: String,
    /** The JSON-encoded arguments object the model provided. */
    val argumentsJson: String,
    /** The tool-call JSON exactly as the model wrote it. */
    val rawJson: String
)

/**
 * Emulates tool (function) calling on top of ML Kit's GenAI Prompt API,
 * which has no native support for it: the prompt is prefixed with a
 * description of the available tools and an instruction to reply with a
 * tool-call JSON object, and each response is checked for such an object.
 *
 * Best-effort by design — the small on-device model may ignore the tools
 * and answer directly.
 */
object ToolPrompting {
    /**
     * Builds the instructions prepended to the user's prompt that describe
     * [tools] and how the model should call them. Each tool's arguments are
     * described by the JSON Schema built on the Dart side, embedded as-is.
     */
    fun buildToolPreamble(tools: List<EdgeGenAIToolDefinition>): String =
        buildString {
            appendLine("You can use the following tools:")
            for (tool in tools) {
                appendLine(
                    "- ${tool.name}: ${tool.descriptionText} " +
                        "Arguments JSON schema: ${tool.parametersSchemaJson}"
                )
            }
            appendLine(
                "To use a tool, reply with ONLY a JSON object of the form " +
                    "{\"tool\": \"<tool name>\", \"arguments\": <arguments object " +
                    "matching the tool's schema>} and nothing else."
            )
            append(
                "If no tool is needed, answer the user directly without JSON."
            )
        }

    /**
     * Returns the extension of the round's prompt after the model called a
     * tool and the app returned [toolResult], instructing the model to
     * continue.
     */
    fun buildToolResultContinuation(
        toolCall: ParsedToolCall,
        toolResult: String
    ): String =
        "\n\nYou replied with the tool call: ${toolCall.rawJson}\n" +
            "Tool \"${toolCall.toolName}\" returned: $toolResult\n" +
            "Continue: answer the user using this result, or reply with only " +
            "another tool-call JSON if you need a different tool."

    /**
     * Parses [responseText] as a tool call against [tools], returning null
     * when the response is a regular answer (no known tool call).
     *
     * Tolerates prose or a Markdown code fence around the JSON, both of
     * which small models commonly emit. Every balanced JSON object in the
     * response is checked so an unrelated object before the tool call does
     * not hide it.
     */
    fun parseToolCall(
        responseText: String,
        tools: List<EdgeGenAIToolDefinition>
    ): ParsedToolCall? {
        for (rawJson in extractJsonObjects(responseText)) {
            val json =
                try {
                    JSONObject(rawJson)
                } catch (e: JSONException) {
                    continue
                }
            val toolName = json.optString("tool")
            if (toolName.isEmpty() || tools.none { it.name == toolName }) continue
            val argumentsJson = json.optJSONObject("arguments")?.toString() ?: "{}"
            return ParsedToolCall(toolName, argumentsJson, rawJson)
        }
        return null
    }

    /**
     * Returns every top-level balanced `{...}` candidate in [text]. If an
     * opening brace never balances, scanning resumes at the next one. Brace
     * counting skips braces inside JSON string literals.
     */
    private fun extractJsonObjects(text: String): Sequence<String> = sequence {
        var searchIndex = 0
        while (searchIndex < text.length) {
            val startIndex = text.indexOf('{', searchIndex)
            if (startIndex == -1) break
            val candidate = extractJsonObjectAt(text, startIndex)
            if (candidate == null) {
                searchIndex = startIndex + 1
            } else {
                yield(candidate)
                searchIndex = startIndex + candidate.length
            }
        }
    }

    /** Returns the balanced JSON object beginning at [startIndex], if any. */
    private fun extractJsonObjectAt(text: String, startIndex: Int): String? {
        var depth = 0
        var inString = false
        var escaped = false
        for (index in startIndex until text.length) {
            val char = text[index]
            when {
                escaped -> escaped = false
                char == '\\' && inString -> escaped = true
                char == '"' -> inString = !inString
                inString -> {}
                char == '{' -> depth++
                char == '}' -> {
                    depth--
                    if (depth == 0) return text.substring(startIndex, index + 1)
                }
            }
        }
        return null
    }
}
