import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'edge_gen_ai_availability.dart';
import 'edge_gen_ai_download_progress.dart';
import 'edge_gen_ai_generation_options.dart';
import 'edge_gen_ai_method_channel.dart';
import 'edge_gen_ai_rewrite_style.dart';
import 'edge_gen_ai_tool.dart';

abstract class EdgeGenAIPlatform extends PlatformInterface {
  /// Constructs a EdgeGenAIPlatform.
  EdgeGenAIPlatform() : super(token: _token);

  static final Object _token = Object();

  static EdgeGenAIPlatform _instance = MethodChannelEdgeGenAI();

  /// The default instance of [EdgeGenAIPlatform] to use.
  ///
  /// Defaults to [MethodChannelEdgeGenAI].
  static EdgeGenAIPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [EdgeGenAIPlatform] when
  /// they register themselves.
  static set instance(EdgeGenAIPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Checks whether the on-device [feature] is available.
  Future<EdgeGenAIAvailability> checkAvailability(EdgeGenAIFeature feature) {
    throw UnimplementedError('checkAvailability() has not been implemented.');
  }

  /// Triggers the on-device model download for [feature] (if one is needed)
  /// and streams progress updates until it completes or fails.
  Stream<EdgeGenAIDownloadProgress> downloadModel(EdgeGenAIFeature feature) {
    throw UnimplementedError('downloadModel() has not been implemented.');
  }

  /// Sends [prompt] (and, optionally, [image]) to the on-device model and
  /// streams its generated text.
  ///
  /// Each event is the full response text generated so far, not just the
  /// newly-added chunk.
  ///
  /// [sessionId] identifies the calling `EdgeGenAIPrompt` instance so each
  /// instance keeps its own isolated conversation. By default, this is a
  /// stateless one-off call. Pass [useMemory] as true to remember (and
  /// build on) prior [useMemory] calls from the same [sessionId]; use
  /// [resetConversation] to start that remembered conversation over.
  ///
  /// [tools] are functions the model may call while generating; their Dart
  /// implementations run in this isolate when it does.
  Stream<String> generateContent(
    String sessionId,
    String prompt, {
    EdgeGenAIGenerationOptions? options,
    bool useMemory = false,
    Uint8List? image,
    List<EdgeGenAITool> tools = const [],
  }) {
    throw UnimplementedError('generateContent() has not been implemented.');
  }

  /// Clears the conversation history remembered for [sessionId] so that
  /// instance's next [generateContent] call starts a fresh conversation.
  ///
  /// On platforms without conversation memory, this is a no-op.
  Future<void> resetConversation(String sessionId) {
    throw UnimplementedError('resetConversation() has not been implemented.');
  }

  /// Summarizes [text] and returns the summary.
  Future<String> summarize(String text) {
    throw UnimplementedError('summarize() has not been implemented.');
  }

  /// Proofreads [text] and returns the corrected text.
  Future<String> proofread(String text) {
    throw UnimplementedError('proofread() has not been implemented.');
  }

  /// Rewrites [text] in the given [style] and returns the rewritten text.
  Future<String> rewrite(String text, {required EdgeGenAIRewriteStyle style}) {
    throw UnimplementedError('rewrite() has not been implemented.');
  }

  /// Describes the image encoded in [imageBytes] (for example PNG or JPEG
  /// bytes) and returns the description.
  Future<String> describeImage(Uint8List imageBytes) {
    throw UnimplementedError('describeImage() has not been implemented.');
  }
}
