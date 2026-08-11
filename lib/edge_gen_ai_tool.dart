/// The type of a single tool parameter value.
enum EdgeGenAIToolParameterType {
  /// A text value.
  string,

  /// A floating-point number.
  number,

  /// A whole number.
  integer,

  /// A true/false value.
  boolean,
}

/// The schema of one value the model generates when calling a tool,
/// mirroring what Foundation Models' `DynamicGenerationSchema` can enforce
/// natively on iOS: primitive types, string enums, numeric ranges, arrays
/// with item schemas and length bounds, and nested objects.
///
/// On Android the same schema is rendered into the tool-calling prompt as
/// JSON Schema text, which the model is asked to follow.
class EdgeGenAIToolSchema {
  EdgeGenAIToolSchema._(this._json);

  /// A text value, optionally restricted to [enumValues].
  factory EdgeGenAIToolSchema.string({
    String? description,
    List<String>? enumValues,
  }) {
    return EdgeGenAIToolSchema._({
      'type': 'string',
      'description': ?description,
      if (enumValues != null && enumValues.isNotEmpty) 'enum': enumValues,
    });
  }

  /// A floating-point number, optionally bounded to [minimum]/[maximum].
  factory EdgeGenAIToolSchema.number({
    String? description,
    double? minimum,
    double? maximum,
  }) {
    return EdgeGenAIToolSchema._({
      'type': 'number',
      'description': ?description,
      'minimum': ?minimum,
      'maximum': ?maximum,
    });
  }

  /// A whole number, optionally bounded to [minimum]/[maximum].
  factory EdgeGenAIToolSchema.integer({
    String? description,
    int? minimum,
    int? maximum,
  }) {
    return EdgeGenAIToolSchema._({
      'type': 'integer',
      'description': ?description,
      'minimum': ?minimum,
      'maximum': ?maximum,
    });
  }

  /// A true/false value.
  factory EdgeGenAIToolSchema.boolean({String? description}) {
    return EdgeGenAIToolSchema._({
      'type': 'boolean',
      'description': ?description,
    });
  }

  /// A list whose elements each match [items], optionally with
  /// [minItems]/[maxItems] length bounds.
  factory EdgeGenAIToolSchema.array({
    required EdgeGenAIToolSchema items,
    String? description,
    int? minItems,
    int? maxItems,
  }) {
    return EdgeGenAIToolSchema._({
      'type': 'array',
      'description': ?description,
      'items': items._json,
      'minItems': ?minItems,
      'maxItems': ?maxItems,
    });
  }

  /// A nested object with named [properties].
  ///
  /// Every property is required unless its name is listed in
  /// [optionalProperties].
  factory EdgeGenAIToolSchema.object({
    required Map<String, EdgeGenAIToolSchema> properties,
    String? description,
    List<String> optionalProperties = const [],
  }) {
    return EdgeGenAIToolSchema._({
      'type': 'object',
      'description': ?description,
      'properties': {
        for (final entry in properties.entries) entry.key: entry.value._json,
      },
      'required': [
        for (final name in properties.keys)
          if (!optionalProperties.contains(name)) name,
      ],
    });
  }

  /// The schema of a primitive [EdgeGenAIToolParameterType].
  factory EdgeGenAIToolSchema.ofType(
    EdgeGenAIToolParameterType type, {
    String? description,
  }) {
    switch (type) {
      case EdgeGenAIToolParameterType.string:
        return EdgeGenAIToolSchema.string(description: description);
      case EdgeGenAIToolParameterType.number:
        return EdgeGenAIToolSchema.number(description: description);
      case EdgeGenAIToolParameterType.integer:
        return EdgeGenAIToolSchema.integer(description: description);
      case EdgeGenAIToolParameterType.boolean:
        return EdgeGenAIToolSchema.boolean(description: description);
    }
  }

  final Map<String, Object?> _json;

  /// This schema as a JSON Schema document (a plain JSON-encodable map).
  Map<String, Object?> toJsonSchema() => _json;
}

/// A single named parameter of an [EdgeGenAITool].
class EdgeGenAIToolParameter {
  EdgeGenAIToolParameter({
    required this.name,
    required this.description,
    this.type = EdgeGenAIToolParameterType.string,
    EdgeGenAIToolSchema? schema,
    this.isRequired = true,
  }) : schema = schema ?? EdgeGenAIToolSchema.ofType(type);

  /// The parameter's name, as it appears in the arguments map.
  final String name;

  /// What the parameter means, so the model knows what to pass.
  final String description;

  /// The parameter's primitive value type. Ignored when [schema] is
  /// provided, which supersedes it with a full value schema (enums,
  /// ranges, arrays, nested objects).
  final EdgeGenAIToolParameterType type;

  /// The parameter's value schema.
  final EdgeGenAIToolSchema schema;

  /// Whether the model must always provide this parameter.
  final bool isRequired;
}

/// A tool (function) the on-device model may call while generating a
/// response to an `EdgeGenAIPrompt.generateContent` call.
///
/// The [name], [description], and [parameters] are shown to the model so it
/// knows when and how to call the tool; [onCall] is the Dart implementation
/// that runs when it does.
///
/// On iOS this uses Foundation Models' native `Tool` support. Android's
/// ML Kit GenAI Prompt API has no native tool calling, so the plugin
/// emulates it there by instructing the model to reply with a tool-call
/// JSON object — treat tool calling on Android as best-effort: the small
/// on-device model may answer directly instead of calling a tool.
class EdgeGenAITool {
  EdgeGenAITool({
    required this.name,
    required this.description,
    this.parameters = const [],
    required this.onCall,
  });

  /// The tool's unique name (unique within one `EdgeGenAIPrompt` instance).
  final String name;

  /// What the tool does, so the model knows when to call it.
  final String description;

  /// The parameters the model should pass when calling the tool.
  final List<EdgeGenAIToolParameter> parameters;

  /// Runs the tool with the [arguments] the model provided (decoded from
  /// JSON) and returns the result text the model continues generating with.
  final Future<String> Function(Map<String, Object?> arguments) onCall;

  /// This tool's arguments as one JSON Schema object: each parameter is a
  /// property (its `description` merged into its value schema), and every
  /// [EdgeGenAIToolParameter.isRequired] parameter is listed in `required`.
  Map<String, Object?> argumentsJsonSchema() {
    return {
      'type': 'object',
      'properties': {
        for (final parameter in parameters)
          parameter.name: {
            ...parameter.schema.toJsonSchema(),
            'description': parameter.description,
          },
      },
      'required': [
        for (final parameter in parameters)
          if (parameter.isRequired) parameter.name,
      ],
    };
  }
}
