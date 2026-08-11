import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    kotlinOut: 'android/src/main/kotlin/com/manukj/edge_gen_ai/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.manukj.edge_gen_ai'),
    swiftOut: 'ios/edge_gen_ai/Sources/edge_gen_ai/Messages.g.swift',
    dartPackageName: 'edge_gen_ai',
  ),
)
/// The availability of an on-device generative AI feature.
enum EdgeGenAIAvailability {
  /// The feature is available and ready to use.
  available,

  /// The device supports the feature, but it still needs to download (for
  /// example, Android's Gemini Nano feature is downloadable/downloading).
  downloadable,

  /// The device supports the feature, but the user hasn't enabled the
  /// OS-level AI feature yet (for example, Apple Intelligence is turned
  /// off).
  notYetReady,

  /// The device or OS version doesn't support the on-device feature.
  unavailable,
}

/// The on-device generative AI features exposed by this plugin.
///
/// On Android each feature is a distinct ML Kit GenAI client with its own
/// independent availability/download lifecycle; on iOS they all map to the
/// single system Foundation Models availability.
enum EdgeGenAIFeature {
  /// The general-purpose prompt feature (`EdgeGenAIPrompt`).
  prompt,

  /// The text summarization feature (`EdgeGenAISummarizer`).
  summarization,

  /// The proofreading feature (`EdgeGenAIProofreader`).
  proofreading,

  /// The text rewriting feature (`EdgeGenAIRewriter`).
  rewriting,

  /// The image description feature (`EdgeGenAIImageDescriber`).
  imageDescription,
}

/// The style `EdgeGenAIRewriter` rewrites text into.
///
/// Matches the output types of Android's ML Kit GenAI Rewriting API; on iOS
/// each style becomes a task-specific instruction to the system model.
enum EdgeGenAIRewriteStyle {
  /// Rephrases the text while keeping its meaning and length.
  rephrase,

  /// Expands on the text with more detail.
  elaborate,

  /// Adds fitting emoji to the text.
  emojify,

  /// Shortens the text while keeping its meaning.
  shorten,

  /// Rewrites the text in a casual, friendly tone.
  friendly,

  /// Rewrites the text in a formal, professional tone.
  professional,
}

/// The model-facing description of a tool the app exposes to the model.
///
/// The tool's implementation stays in Dart (see `EdgeGenAITool.onCall`);
/// only this schema crosses to the platform side, which calls back into
/// Dart via `EdgeGenAIToolExecutorApi` when the model invokes the tool.
///
/// The description field is named `descriptionText` (not `description`)
/// because Pigeon reserves `description` for Swift's NSObject property.
class EdgeGenAIToolDefinition {
  EdgeGenAIToolDefinition({
    required this.name,
    required this.descriptionText,
    required this.parametersSchemaJson,
  });

  /// The tool's unique name.
  final String name;

  /// What the tool does, so the model knows when to call it.
  final String descriptionText;

  /// A JSON Schema document (as JSON text) describing the tool's arguments
  /// object: `{"type": "object", "properties": {...}, "required": [...]}`.
  ///
  /// It's carried as JSON text rather than typed Pigeon classes because
  /// schemas are recursive (objects nest objects, arrays have item
  /// schemas), which Pigeon data classes can't express. The supported
  /// subset — mirroring what Foundation Models' `DynamicGenerationSchema`
  /// can enforce — is: `type` (string/number/integer/boolean/array/object),
  /// `description`, `enum` (strings), `minimum`/`maximum` (numbers),
  /// `items`/`minItems`/`maxItems` (arrays), and `properties`/`required`
  /// (objects). The `EdgeGenAIToolSchema` factories in Dart only build
  /// this subset.
  final String parametersSchemaJson;
}

/// Optional parameters controlling how the model generates its response.
///
/// Only fields supported by both Android and iOS are exposed here.
class EdgeGenAIGenerationOptions {
  EdgeGenAIGenerationOptions({this.temperature, this.maxOutputTokens});

  /// Controls the randomness of the output. Higher values produce more
  /// creative (less predictable) responses.
  final double? temperature;

  /// The maximum number of tokens the model may generate in its response.
  final int? maxOutputTokens;
}

@HostApi()
abstract class EdgeGenAIHostApi {
  @async
  EdgeGenAIAvailability checkAvailability(EdgeGenAIFeature feature);

  /// Stores the request for the next `generateContentChunk` event channel
  /// subscription to use.
  ///
  /// [sessionId] identifies the `EdgeGenAIPrompt` instance making the call,
  /// so each instance gets its own isolated conversation when [useMemory]
  /// is true; when false, it's a stateless, one-off call that neither reads
  /// nor updates that instance's remembered conversation. [image] is an
  /// optional encoded image (for example PNG or JPEG bytes) sent to the
  /// model alongside [prompt]. [tools] describes the tools the model may
  /// call during generation; when it does, the platform side invokes the
  /// matching Dart executor through `EdgeGenAIToolExecutorApi.callTool`.
  ///
  /// Event channels can't carry parameters, so callers must invoke this
  /// immediately before listening to the `generateContentChunk` stream.
  void startGenerateContent(
    String sessionId,
    String prompt,
    EdgeGenAIGenerationOptions? options,
    bool useMemory,
    Uint8List? image,
    List<EdgeGenAIToolDefinition> tools,
  );

  /// Clears the conversation history remembered for [sessionId] so that
  /// instance's next `generateContent` call starts a fresh conversation.
  void resetConversation(String sessionId);

  /// Summarizes [text] and returns the summary.
  @async
  String summarize(String text);

  /// Proofreads [text] and returns the corrected text.
  @async
  String proofread(String text);

  /// Rewrites [text] in the given [style] and returns the rewritten text.
  @async
  String rewrite(String text, EdgeGenAIRewriteStyle style);

  /// Describes the image encoded in [imageBytes] (for example PNG or JPEG
  /// bytes) and returns the description.
  @async
  String describeImage(Uint8List imageBytes);
}

/// Calls from the platform side back into Dart, where tool implementations
/// live.
@FlutterApi()
abstract class EdgeGenAIToolExecutorApi {
  /// Runs the Dart executor of the tool named [toolName] (registered by the
  /// `EdgeGenAIPrompt` instance identified by [sessionId]) with the
  /// JSON-encoded [argumentsJson] the model provided, and returns the
  /// tool's result for the model to continue generating with.
  @async
  String callTool(String sessionId, String toolName, String argumentsJson);
}

/// The status of an on-device model download.
enum EdgeGenAIDownloadStatus {
  /// The download has started.
  started,

  /// The download is in progress.
  inProgress,

  /// The download finished and the model is ready to use.
  completed,
}

/// A single download progress update.
class EdgeGenAIDownloadProgress {
  EdgeGenAIDownloadProgress({required this.status, this.bytesDownloaded});

  /// The current status of the download.
  final EdgeGenAIDownloadStatus status;

  /// The total number of bytes downloaded so far. Only populated when
  /// [status] is [EdgeGenAIDownloadStatus.inProgress].
  final int? bytesDownloaded;
}

/// Each method below is a separate event channel, so downloads of different
/// features can run (and report progress) independently.
///
/// On iOS there's nothing for the app to download — Apple Intelligence is
/// enabled system-wide in Settings — so every download stream immediately
/// emits a single `completed` event.
@EventChannelApi()
abstract class EdgeGenAIEventApi {
  /// Triggers the prompt feature's model download (if one is needed) and
  /// streams progress updates until it completes or fails.
  EdgeGenAIDownloadProgress promptDownloadProgress();

  /// Same as [promptDownloadProgress], for the summarization feature.
  EdgeGenAIDownloadProgress summarizationDownloadProgress();

  /// Same as [promptDownloadProgress], for the proofreading feature.
  EdgeGenAIDownloadProgress proofreadingDownloadProgress();

  /// Same as [promptDownloadProgress], for the rewriting feature.
  EdgeGenAIDownloadProgress rewritingDownloadProgress();

  /// Same as [promptDownloadProgress], for the image description feature.
  EdgeGenAIDownloadProgress imageDescriptionDownloadProgress();

  /// Streams the response set up via `startGenerateContent`.
  ///
  /// Each event is the full response text generated so far (not just the
  /// newly-added chunk), so UI code can simply display the latest event.
  String generateContentChunk();
}
