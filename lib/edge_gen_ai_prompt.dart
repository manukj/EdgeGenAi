import 'dart:typed_data';

import 'edge_gen_ai_availability.dart';
import 'edge_gen_ai_download_progress.dart';
import 'edge_gen_ai_generation_options.dart';
import 'edge_gen_ai_platform_interface.dart';
import 'edge_gen_ai_tool.dart';

/// The general-purpose on-device prompt feature: send free-form prompts
/// (optionally with an image) and stream the model's response.
///
/// Backed by ML Kit GenAI's Prompt API (Gemini Nano) on Android and by
/// Apple's Foundation Models on iOS.
class EdgeGenAIPrompt {
  /// Creates an [EdgeGenAIPrompt] instance.
  ///
  /// Pass [useMemory] as true to have [generateContent] remember (and
  /// build on) prior turns; use [resetConversation] to start over. By
  /// default, calls are stateless. Each instance keeps its own isolated
  /// conversation.
  ///
  /// Pass [tools] to let the model call back into the app while
  /// generating. Tools are fixed per instance (not per call) because iOS
  /// binds them to the native session that carries the conversation.
  EdgeGenAIPrompt({this.useMemory = false, this.tools = const []})
    : _sessionId = 'prompt-${_nextSessionId++}';

  /// Backs the per-instance session ids; a simple incrementing counter is
  /// enough because ids only need to be unique within this app process.
  static int _nextSessionId = 0;

  /// Identifies this instance's conversation on the platform side.
  final String _sessionId;

  /// Whether [generateContent] remembers prior turns. See [resetConversation].
  final bool useMemory;

  /// The tools (functions) the model may call while generating. See
  /// [EdgeGenAITool] for how tool calling differs per platform.
  final List<EdgeGenAITool> tools;

  /// Checks whether the on-device prompt feature is available.
  ///
  /// This does not download or enable the model — it only reports the
  /// current state so the app can decide what UI to show.
  Future<EdgeGenAIAvailability> checkAvailability() {
    return EdgeGenAIPlatform.instance.checkAvailability(
      EdgeGenAIFeature.prompt,
    );
  }

  /// Triggers the on-device model download (if one is needed) and streams
  /// progress updates until it completes or fails.
  ///
  /// On iOS, Apple Intelligence must be enabled by the person in Settings —
  /// there's nothing for the app to trigger, so this immediately completes.
  Stream<EdgeGenAIDownloadProgress> downloadModel() {
    return EdgeGenAIPlatform.instance.downloadModel(EdgeGenAIFeature.prompt);
  }

  /// Sends [prompt] to the on-device model and streams its generated text.
  ///
  /// Pass [image] (encoded image bytes, for example PNG or JPEG) to include
  /// a single image alongside the prompt. Both platforms support at most
  /// one image per call.
  ///
  /// Each event is the full response text generated so far, not just the
  /// newly-added chunk, so UI code can simply display the latest event.
  Stream<String> generateContent(
    String prompt, {
    EdgeGenAIGenerationOptions? options,
    Uint8List? image,
  }) {
    return EdgeGenAIPlatform.instance.generateContent(
      _sessionId,
      prompt,
      options: options,
      useMemory: useMemory,
      image: image,
      tools: tools,
    );
  }

  /// Clears this instance's remembered conversation history so the next
  /// [generateContent] call starts a fresh conversation.
  ///
  /// On platforms without conversation memory, this is a no-op.
  Future<void> resetConversation() {
    return EdgeGenAIPlatform.instance.resetConversation(_sessionId);
  }
}
