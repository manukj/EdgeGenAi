package com.manukj.edge_gen_ai

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
 * Builds the prompt text used to drive ML Kit's structured-output tool calling: a description of
 * the available tools plus an instruction to reply with a [ToolDecision].
 */
object ToolPrompting {
    /**
     * Builds the instructions prepended to the user's prompt that describe [tools] and how the
     * model should call them. Each tool's arguments are described by the JSON Schema built on the
     * Dart side, embedded as-is.
     */
    fun buildToolPreamble(tools: List<EdgeGenAIToolDefinition>): String = buildString {
        appendLine("You can use the following tools:")
        for (tool in tools) {
            appendLine(
                    "- ${tool.name}: ${tool.descriptionText} " +
                            "Arguments JSON schema: ${tool.parametersSchemaJson}"
            )
        }
        append(
                "Return a ToolDecision. To call a tool, set action to tool, tool to its name, " +
                        "argumentsJson to a JSON object encoded as a string matching its schema, and answer to empty. " +
                        "Otherwise set action to answer, answer to your response, tool to empty, and argumentsJson to {}."
        )
    }

    /**
     * Returns the extension of the round's prompt after the model called a tool and the app
     * returned [toolResult], instructing the model to continue.
     */
    fun buildToolResultContinuation(toolCall: ParsedToolCall, toolResult: String): String =
            "\n\nYou replied with the tool call: ${toolCall.rawJson}\n" +
                    "Tool \"${toolCall.toolName}\" returned: $toolResult\n" +
                    "Continue: return another ToolDecision using this result."
}
