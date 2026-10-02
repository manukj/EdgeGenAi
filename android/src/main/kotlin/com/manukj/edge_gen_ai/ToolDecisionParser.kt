package com.manukj.edge_gen_ai

import org.json.JSONObject
import org.json.JSONTokener

/** Parses a model's fallback response while accepting common JSON fences and lead-in text. */
internal object ToolDecisionParser {
    fun parse(response: String): ToolDecision {
        val text = response.trim()
        val candidates = jsonObjects(text)
        for (json in candidates) {
            val parsed = runCatching { parseEnvelope(json) }.getOrNull()
            if (parsed != null) return parsed
        }

        // Models sometimes ignore the envelope for ordinary answers. Never treat prose as a
        // function call; a tool only runs after a valid JSON envelope and schema validation.
        require(candidates.isEmpty() && text.isNotBlank()) {
            "The model returned an invalid tool decision. No tool was executed."
        }
        return ToolDecision("answer", "", "{}", text)
    }

    private fun parseEnvelope(json: String): ToolDecision {
        val tokenizer = JSONTokener(json)
        val value = tokenizer.nextValue()
        require(value is JSONObject && tokenizer.nextClean() == '\u0000') {
            "Tool decision must be a JSON object."
        }
        val action = value.getString("action")
        val tool = value.optString("tool", "")
        val answer = value.optString("answer", "")
        val argumentsValue = value.opt("arguments")
        val arguments = when (argumentsValue) {
            null, JSONObject.NULL -> JSONObject()
            is JSONObject -> argumentsValue
            // Also accept the earlier documented envelope where arguments were JSON-encoded.
            is String -> parseArguments(argumentsValue)
            else -> throw IllegalArgumentException("Tool arguments must be an object.")
        }
        return ToolDecision(action, tool, arguments.toString(), answer)
    }

    /** Finds balanced object candidates without mistaking braces inside JSON strings for syntax. */
    private fun jsonObjects(text: String): List<String> = buildList {
        var start = 0
        while (start < text.length) {
            if (text[start] != '{') {
                start++
                continue
            }
            var depth = 0
            var quoted = false
            var escaped = false
            var end = -1
            for (index in start until text.length) {
                val char = text[index]
                if (quoted) {
                    when {
                        escaped -> escaped = false
                        char == '\\' -> escaped = true
                        char == '"' -> quoted = false
                    }
                    continue
                }
                when (char) {
                    '"' -> quoted = true
                    '{' -> depth++
                    '}' -> {
                        depth--
                        if (depth == 0) {
                            end = index
                            break
                        }
                    }
                }
            }
            if (end >= start) {
                add(text.substring(start, end + 1))
                // Don't separately consider objects nested inside an invalid outer envelope.
                start = end + 1
            } else {
                start++
            }
        }
    }
}
