import Flutter
#if canImport(FoundationModels)
  import FoundationModels
#endif

/// Starts generation for the request stashed via `startGenerateContent` when Flutter
/// starts listening, and streams the cumulative response text as it's generated.
class GenerateContentStreamHandler: GenerateContentChunkStreamHandler {
  private let takePendingRequest: () -> PendingGenerateContentRequest?
  private let takeSession: (String, Bool, [EdgeGenAIToolDefinition]) -> Any?
  private let onCancellationChanged: (@escaping () -> Void) -> Void
  private var generationTask: Task<Void, Never>?
  private var activeSink: PigeonEventSink<String>?

  init(
    takePendingRequest: @escaping () -> PendingGenerateContentRequest?,
    takeSession: @escaping (String, Bool, [EdgeGenAIToolDefinition]) -> Any?
    , onCancellationChanged: @escaping (@escaping () -> Void) -> Void
  ) {
    self.takePendingRequest = takePendingRequest
    self.takeSession = takeSession
    self.onCancellationChanged = onCancellationChanged
    super.init()
  }

  override func onCancel(withArguments arguments: Any?) {
    stop()
  }

  func stop() {
    activeSink?.endOfStream()
    generationTask?.cancel()
    activeSink = nil
    onCancellationChanged({})
  }

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<String>) {
    guard let request = takePendingRequest() else {
      sink.error(
        code: "no_prompt", message: "startGenerateContent must be called before listening.",
        details: nil)
      return
    }
    #if canImport(FoundationModels)
      if #available(iOS 26.0, *) {
        activeSink = sink
        guard
          let session = takeSession(request.sessionId, request.useMemory, request.tools)
            as? LanguageModelSession
        else {
          sink.error(
            code: "unavailable", message: "The on-device model isn't available.", details: nil)
          return
        }
        generationTask = Task {
          do {
            try await FoundationModelsBridge.streamResponse(
              session: session, prompt: request.prompt, image: request.image,
              options: request.options
            ) { chunk in
              DispatchQueue.main.async { sink.success(chunk) }
            }
            DispatchQueue.main.async { sink.endOfStream() }
          } catch {
            if Task.isCancelled { return }
            let wrapped = PigeonError.wrapping(error, fallbackCode: "generate_content_failed")
            DispatchQueue.main.async {
              sink.error(code: wrapped.code, message: wrapped.message, details: wrapped.details)
            }
          }
          self.generationTask = nil
          self.activeSink = nil
          self.onCancellationChanged({})
        }
        onCancellationChanged({ [weak self] in self?.stop() })
        return
      }
    #endif
    sink.error(
      code: "unavailable", message: "The on-device model isn't available.", details: nil)
  }
}
