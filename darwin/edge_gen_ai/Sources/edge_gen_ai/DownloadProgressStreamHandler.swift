#if os(macOS)
  import FlutterMacOS
#else
  import Flutter
#endif

/// There's nothing for the app to download on iOS — Apple Intelligence is
/// enabled system-wide in Settings — so every feature's download stream
/// immediately reports completion.
///
/// Pigeon generates a separate stream handler base class per feature, with
/// no common ancestor, so the identical behavior is repeated per subclass.
private func reportImmediateCompletion(_ sink: PigeonEventSink<EdgeGenAIDownloadProgress>) {
  sink.success(EdgeGenAIDownloadProgress(status: .completed, bytesDownloaded: nil))
  sink.endOfStream()
}

class ImmediatePromptDownloadStreamHandler: PromptDownloadProgressStreamHandler {
  override func onListen(
    withArguments arguments: Any?, sink: PigeonEventSink<EdgeGenAIDownloadProgress>
  ) {
    reportImmediateCompletion(sink)
  }
}

class ImmediateSummarizationDownloadStreamHandler: SummarizationDownloadProgressStreamHandler {
  override func onListen(
    withArguments arguments: Any?, sink: PigeonEventSink<EdgeGenAIDownloadProgress>
  ) {
    reportImmediateCompletion(sink)
  }
}

class ImmediateProofreadingDownloadStreamHandler: ProofreadingDownloadProgressStreamHandler {
  override func onListen(
    withArguments arguments: Any?, sink: PigeonEventSink<EdgeGenAIDownloadProgress>
  ) {
    reportImmediateCompletion(sink)
  }
}

class ImmediateRewritingDownloadStreamHandler: RewritingDownloadProgressStreamHandler {
  override func onListen(
    withArguments arguments: Any?, sink: PigeonEventSink<EdgeGenAIDownloadProgress>
  ) {
    reportImmediateCompletion(sink)
  }
}

class ImmediateImageDescriptionDownloadStreamHandler: ImageDescriptionDownloadProgressStreamHandler {
  override func onListen(
    withArguments arguments: Any?, sink: PigeonEventSink<EdgeGenAIDownloadProgress>
  ) {
    reportImmediateCompletion(sink)
  }
}
