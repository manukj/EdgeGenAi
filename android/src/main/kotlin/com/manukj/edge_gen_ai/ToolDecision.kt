package com.manukj.edge_gen_ai

import com.google.mlkit.genai.schema.annotations.Generable
import com.google.mlkit.genai.schema.annotations.Guide
import org.json.JSONObject
import org.json.JSONTokener

/**
 * ML Kit's typed envelope. Dart tools have runtime schemas, so arguments remain
 * JSON text and MUST pass ToolArgumentValidator before the callback executes.
 */
@Generable
data class ToolDecision(
    @Guide(description = "tool to request a function, or answer to respond to the user",
        enumValues = ["tool", "answer"])
    val action: String,
    @Guide(description = "Registered tool name when action is tool; otherwise empty")
    val tool: String,
    @Guide(description = "JSON object encoded as a string matching the selected tool schema; use {} for an answer")
    val argumentsJson: String,
    @Guide(description = "User-facing response when action is answer; otherwise empty")
    val answer: String,
) {
    fun toolCall(tools: List<EdgeGenAIToolDefinition>): ParsedToolCall? {
        require(action == "tool" || action == "answer") { "Unknown tool decision action." }
        if (action == "answer") {
            require(tool.isEmpty() && answer.isNotBlank()) { "Invalid final answer decision." }
            return null
        }
        require(answer.isEmpty()) { "A tool decision cannot also contain an answer." }
        val definition = tools.singleOrNull { it.name == tool }
        requireNotNull(definition) { "Unknown or duplicate tool name: $tool" }
        val arguments = parseArguments(argumentsJson)
        ToolArgumentValidator.validate(arguments, JSONObject(definition.parametersSchemaJson))
        val raw = JSONObject().put("tool", tool).put("arguments", arguments).toString()
        return ParsedToolCall(tool, arguments.toString(), raw)
    }
}

internal fun parseArguments(text: String): JSONObject {
    val tokenizer = JSONTokener(text)
    val value = tokenizer.nextValue()
    require(value is JSONObject && tokenizer.nextClean() == '\u0000') {
        "Tool arguments must be a single JSON object."
    }
    return value
}
