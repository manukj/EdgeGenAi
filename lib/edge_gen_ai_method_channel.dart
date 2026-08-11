import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'edge_gen_ai_platform_interface.dart';
import 'edge_gen_ai_tool.dart';
import 'src/messages.g.dart';

class MethodChannelEdgeGenAI extends EdgeGenAIPlatform {
  @visibleForTesting
  final hostApi = EdgeGenAIHostApi();

  /// The tools registered by each `EdgeGenAIPrompt` instance's latest
  /// [generateContent] call, so [_ToolExecutor] can find the right Dart
  /// implementation when the platform side reports a tool call.
  final Map<String, Map<String, EdgeGenAITool>> _toolsBySession = {};

  /// Whether [_ToolExecutor] has been registered as the handler for
  /// platform-side tool calls. Registration happens lazily, on the first
  /// call that carries tools, because it needs the Flutter binding — which
  /// doesn't exist yet when this platform instance is created at static
  /// initialization time.
  bool _toolExecutorRegistered = false;

  @override
  Future<EdgeGenAIAvailability> checkAvailability(EdgeGenAIFeature feature) {
    return hostApi.checkAvailability(feature);
  }

  @override
  Stream<EdgeGenAIDownloadProgress> downloadModel(EdgeGenAIFeature feature) {
    switch (feature) {
      case EdgeGenAIFeature.prompt:
        return promptDownloadProgress();
      case EdgeGenAIFeature.summarization:
        return summarizationDownloadProgress();
      case EdgeGenAIFeature.proofreading:
        return proofreadingDownloadProgress();
      case EdgeGenAIFeature.rewriting:
        return rewritingDownloadProgress();
      case EdgeGenAIFeature.imageDescription:
        return imageDescriptionDownloadProgress();
    }
  }

  @override
  Stream<String> generateContent(
    String sessionId,
    String prompt, {
    EdgeGenAIGenerationOptions? options,
    bool useMemory = false,
    Uint8List? image,
    List<EdgeGenAITool> tools = const [],
  }) async* {
    if (tools.isEmpty) {
      _toolsBySession.remove(sessionId);
    } else {
      _toolsBySession[sessionId] = {for (final tool in tools) tool.name: tool};
      if (!_toolExecutorRegistered) {
        _toolExecutorRegistered = true;
        EdgeGenAIToolExecutorApi.setUp(_ToolExecutor(_toolsBySession));
      }
    }
    await hostApi.startGenerateContent(
      sessionId,
      prompt,
      options,
      useMemory,
      image,
      [for (final tool in tools) _toDefinition(tool)],
    );
    yield* generateContentChunk();
  }

  @override
  Future<void> resetConversation(String sessionId) {
    return hostApi.resetConversation(sessionId);
  }

  @override
  Future<String> summarize(String text) {
    return hostApi.summarize(text);
  }

  @override
  Future<String> proofread(String text) {
    return hostApi.proofread(text);
  }

  @override
  Future<String> rewrite(String text, {required EdgeGenAIRewriteStyle style}) {
    return hostApi.rewrite(text, style);
  }

  @override
  Future<String> describeImage(Uint8List imageBytes) {
    return hostApi.describeImage(imageBytes);
  }

  static EdgeGenAIToolDefinition _toDefinition(EdgeGenAITool tool) {
    return EdgeGenAIToolDefinition(
      name: tool.name,
      descriptionText: tool.description,
      parametersSchemaJson: jsonEncode(tool.argumentsJsonSchema()),
    );
  }
}

/// Receives tool calls from the platform side and runs the matching Dart
/// tool implementation.
class _ToolExecutor extends EdgeGenAIToolExecutorApi {
  _ToolExecutor(this._toolsBySession);

  final Map<String, Map<String, EdgeGenAITool>> _toolsBySession;

  @override
  Future<String> callTool(
    String sessionId,
    String toolName,
    String argumentsJson,
  ) async {
    final tool = _toolsBySession[sessionId]?[toolName];
    if (tool == null) {
      throw ArgumentError(
        'No tool named "$toolName" is registered for session "$sessionId".',
      );
    }
    return tool.onCall(_decodeArguments(argumentsJson));
  }

  static Map<String, Object?> _decodeArguments(String argumentsJson) {
    try {
      final decoded = jsonDecode(argumentsJson);
      if (decoded is Map<String, Object?>) return decoded;
    } on FormatException {
      // Fall through: the model produced arguments that aren't a JSON
      // object, so pass them along raw instead of failing the tool call.
    }
    return {'raw': argumentsJson};
  }
}
