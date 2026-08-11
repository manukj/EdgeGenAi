import Flutter
#if canImport(FoundationModels)
  import FoundationModels
#endif

/// Starts generation for the request stashed via `startGenerateContent` when Flutter
/// starts listening, and streams the cumulative response text as it's generated.
class GenerateContentStreamHandler: GenerateContentChunkStreamHandler {
  private let takePendingRequest: () -> PendingGenerateContentRequest?
  private let takeSession: (String, Bool, [EdgeGenAIToolDefinition]) -> Any?

  init(
    takePendingRequest: @escaping () -> PendingGenerateContentRequest?,
    takeSession: @escaping (String, Bool, [EdgeGenAIToolDefinition]) -> Any?
  ) {
    self.takePendingRequest = takePendingRequest
    self.takeSession = takeSession
    super.init()
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
        guard
          let session = takeSession(request.sessionId, request.useMemory, request.tools)
            as? LanguageModelSession
        else {
          sink.error(
            code: "unavailable", message: "The on-device model isn't available.", details: nil)
          return
        }
        Task {
          do {
            try await FoundationModelsBridge.streamResponse(
              session: session, prompt: request.prompt, image: request.image,
              options: request.options
            ) { chunk in
              sink.success(chunk)
            }
            sink.endOfStream()
          } catch {
            let wrapped = PigeonError.wrapping(error, fallbackCode: "generate_content_failed")
            sink.error(code: wrapped.code, message: wrapped.message, details: wrapped.details)
          }
        }
        return
      }
    #endif
    sink.error(
      code: "unavailable", message: "The on-device model isn't available.", details: nil)
  }
}
