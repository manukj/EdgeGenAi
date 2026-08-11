import Flutter
import Foundation

#if canImport(FoundationModels)
  import FoundationModels

  /// A Foundation Models `Tool` whose implementation lives in Dart.
  ///
  /// The schema shown to the model is built at runtime from the tool's
  /// JSON Schema (authored with the Dart `EdgeGenAIToolSchema` factories)
  /// via `DynamicGenerationSchema`, so the framework itself enforces the
  /// argument types, string enums, numeric ranges, and array bounds. When
  /// the model calls the tool, the arguments are forwarded to the matching
  /// Dart executor through `EdgeGenAIToolExecutorApi` and its result is
  /// handed back to the model.
  @available(iOS 26.0, *)
  final class DartBackedTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema

    private let sessionId: String
    private let toolExecutorApi: EdgeGenAIToolExecutorApi

    /// Fails if `parametersSchemaJson` isn't a JSON object or can't be
    /// turned into a `GenerationSchema` (for example, duplicate property
    /// names).
    init?(
      definition: EdgeGenAIToolDefinition,
      sessionId: String,
      toolExecutorApi: EdgeGenAIToolExecutorApi
    ) {
      self.name = definition.name
      self.description = definition.descriptionText
      self.sessionId = sessionId
      self.toolExecutorApi = toolExecutorApi
      guard
        let data = definition.parametersSchemaJson.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data),
        let schemaJson = json as? [String: Any]
      else { return nil }
      let root = Self.dynamicSchema(
        named: definition.name, description: definition.descriptionText, json: schemaJson)
      guard let schema = try? GenerationSchema(root: root, dependencies: []) else {
        return nil
      }
      self.parameters = schema
    }

    /// Builds the `DynamicGenerationSchema` for one JSON Schema node.
    ///
    /// Unknown or missing `type`s fall back to a plain string so a schema
    /// authored with fields this plugin doesn't know still degrades
    /// gracefully instead of dropping the whole tool.
    private static func dynamicSchema(
      named name: String, description: String?, json: [String: Any]
    ) -> DynamicGenerationSchema {
      let description = json["description"] as? String ?? description
      switch json["type"] as? String {
      case "number":
        var guides: [GenerationGuide<Double>] = []
        if let minimum = json["minimum"] as? Double { guides.append(.minimum(minimum)) }
        if let maximum = json["maximum"] as? Double { guides.append(.maximum(maximum)) }
        return DynamicGenerationSchema(type: Double.self, guides: guides)
      case "integer":
        var guides: [GenerationGuide<Int>] = []
        if let minimum = json["minimum"] as? Int { guides.append(.minimum(minimum)) }
        if let maximum = json["maximum"] as? Int { guides.append(.maximum(maximum)) }
        return DynamicGenerationSchema(type: Int.self, guides: guides)
      case "boolean":
        return DynamicGenerationSchema(type: Bool.self, guides: [])
      case "array":
        let itemsJson = json["items"] as? [String: Any] ?? [:]
        return DynamicGenerationSchema(
          arrayOf: dynamicSchema(named: name + "Item", description: nil, json: itemsJson),
          minimumElements: json["minItems"] as? Int,
          maximumElements: json["maxItems"] as? Int)
      case "object":
        let propertiesJson = json["properties"] as? [String: Any] ?? [:]
        let required = json["required"] as? [String] ?? Array(propertiesJson.keys)
        let properties = propertiesJson.sorted { $0.key < $1.key }.map {
          (propertyName, value) -> DynamicGenerationSchema.Property in
          let propertyJson = value as? [String: Any] ?? [:]
          return DynamicGenerationSchema.Property(
            name: propertyName,
            description: propertyJson["description"] as? String,
            schema: dynamicSchema(named: propertyName, description: nil, json: propertyJson),
            isOptional: !required.contains(propertyName))
        }
        return DynamicGenerationSchema(name: name, description: description, properties: properties)
      default:
        if let choices = json["enum"] as? [String], !choices.isEmpty {
          return DynamicGenerationSchema(type: String.self, guides: [.anyOf(choices)])
        }
        return DynamicGenerationSchema(type: String.self, guides: [])
      }
    }

    func call(arguments: GeneratedContent) async throws -> String {
      let argumentsJson = arguments.jsonString


      return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.main.async {
          self.toolExecutorApi.callTool(
            sessionId: self.sessionId, toolName: self.name, argumentsJson: argumentsJson
          ) { result in
            continuation.resume(with: result)
          }
        }
      }
    }
  }
#endif
