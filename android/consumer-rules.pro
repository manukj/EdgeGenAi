# ML Kit deserializes the typed envelope and discovers KSP-generated metadata at runtime.
-keep class com.manukj.edge_gen_ai.ToolDecision { *; }
-keep class * implements com.google.mlkit.genai.schema.guided.GenerableProvider { *; }
