package com.manukj.edge_gen_ai

import org.json.JSONArray
import org.json.JSONObject

/** Validates the schema subset produced by EdgeGenAIToolSchema in Dart. */
internal object ToolArgumentValidator {
    fun validate(value: Any?, schema: JSONObject, path: String = "arguments") {
        fun demand(condition: Boolean, message: String) {
            require(condition) { "$path: $message" }
        }
        when (schema.getString("type")) {
            "object" -> {
                demand(value is JSONObject, "expected object")
                val obj = value as JSONObject
                val properties = schema.optJSONObject("properties") ?: JSONObject()
                val required = schema.optJSONArray("required") ?: JSONArray()
                for (i in 0 until required.length()) {
                    demand(obj.has(required.getString(i)), "missing required field ${required.getString(i)}")
                }
                for (key in obj.keys()) {
                    demand(properties.has(key), "unknown field $key")
                    validate(obj.get(key), properties.getJSONObject(key), "$path.$key")
                }
            }
            "array" -> {
                demand(value is JSONArray, "expected array")
                val array = value as JSONArray
                if (schema.has("minItems")) demand(array.length() >= schema.getInt("minItems"), "too few items")
                if (schema.has("maxItems")) demand(array.length() <= schema.getInt("maxItems"), "too many items")
                for (i in 0 until array.length()) validate(array.get(i), schema.getJSONObject("items"), "$path[$i]")
            }
            "string" -> {
                demand(value is String, "expected string")
                schema.optJSONArray("enum")?.let { choices ->
                    demand((0 until choices.length()).any { choices.get(it) == value }, "value outside enum")
                }
            }
            "number", "integer" -> {
                demand(value is Number, "expected number")
                val number = (value as Number).toDouble()
                demand(number.isFinite(), "expected finite number")
                if (schema.getString("type") == "integer") demand(number % 1.0 == 0.0, "expected integer")
                if (schema.has("minimum")) demand(number >= schema.getDouble("minimum"), "below minimum")
                if (schema.has("maximum")) demand(number <= schema.getDouble("maximum"), "above maximum")
            }
            "boolean" -> demand(value is Boolean, "expected boolean")
            else -> error("$path: unsupported schema type")
        }
    }
}
