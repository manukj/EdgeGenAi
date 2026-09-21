import Flutter
import UIKit
#if canImport(FoundationModels)
  import FoundationModels
#endif

/// The request stashed by `startGenerateContent` for the next
/// `generateContentChunk` listener.
struct PendingGenerateContentRequest {
  let sessionId: String
  let prompt: String
  let options: EdgeGenAIGenerationOptions?
  let useMemory: Bool
  let image: Data?
  let tools: [EdgeGenAIToolDefinition]
}

extension PigeonError {
  /// Wraps `error` as a `PigeonError`, preserving its own `code`/`message`
  /// if it's already one (for example the "requires iOS 27" guards below),
  /// instead of losing that message behind Swift's generic
  /// `localizedDescription` bridging for non-`NSError` types.
  static func wrapping(_ error: Error, fallbackCode: String) -> PigeonError {
    if let pigeonError = error as? PigeonError {
      return pigeonError
    }
    let errorDescription: String
    if let localizedError = error as? LocalizedError,
      let description = localizedError.errorDescription
    {
      errorDescription = description
    } else {
      errorDescription = String(describing: error)
    }
    if errorDescription.contains("ModelManagerServices")
      || errorDescription.contains("SensitiveContentAnalysisML")
    {
      return PigeonError(
        code: "unavailable",
        message: "Apple's Foundation Models runtime isn't ready in this simulator. Try recreating the simulator or test on a device with Apple Intelligence enabled.",
        details: nil)
    }
    return PigeonError(code: fallbackCode, message: errorDescription, details: nil)
  }
}

public class EdgeGenAIPlugin: NSObject, FlutterPlugin, EdgeGenAIHostApi {
  private var pendingRequest: PendingGenerateContentRequest?
  private var cancelGeneration: (() -> Void)?

  /// In-progress conversations keyed by the Dart-side `EdgeGenAIPrompt`
  /// instance's session id, reused across `generateContent` calls that opt
  /// into memory, so the model remembers prior turns per instance. Holds
  /// `LanguageModelSession`s (iOS 26+); type-erased so this property can
  /// exist on OS versions where that type isn't available.
  private var sessions: [String: Any] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = EdgeGenAIPlugin()
    EdgeGenAIHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    let toolExecutorApi = EdgeGenAIToolExecutorApi(binaryMessenger: registrar.messenger())

    // NOT NEEDED: downloads are only relevant on Android — Apple Intelligence is enabled
    // system-wide in Settings — but we still register every download stream so that the
    // Flutter side can listen without crashing; each immediately reports completion.
    PromptDownloadProgressStreamHandler.register(
      with: registrar.messenger(), streamHandler: ImmediatePromptDownloadStreamHandler())
    SummarizationDownloadProgressStreamHandler.register(
      with: registrar.messenger(), streamHandler: ImmediateSummarizationDownloadStreamHandler())
    ProofreadingDownloadProgressStreamHandler.register(
      with: registrar.messenger(), streamHandler: ImmediateProofreadingDownloadStreamHandler())
    RewritingDownloadProgressStreamHandler.register(
      with: registrar.messenger(), streamHandler: ImmediateRewritingDownloadStreamHandler())
    ImageDescriptionDownloadProgressStreamHandler.register(
      with: registrar.messenger(), streamHandler: ImmediateImageDescriptionDownloadStreamHandler())

    // The generate content stream is used to stream the model's response back to Flutter as it's generated.
    let generateContentStreamHandler = GenerateContentStreamHandler(
      takePendingRequest: { [weak instance] in
        let request = instance?.pendingRequest
        instance?.pendingRequest = nil
        return request
      },
      takeSession: { [weak instance] sessionId, useMemory, toolDefinitions in
        #if canImport(FoundationModels)
          if #available(iOS 26.0, *) {
            let tools = FoundationModelsBridge.makeTools(
              definitions: toolDefinitions, sessionId: sessionId,
              toolExecutorApi: toolExecutorApi)
            guard useMemory else { return LanguageModelSession(tools: tools) }
            let session = FoundationModelsBridge.getOrCreateSession(
              instance?.sessions[sessionId], tools: tools)
            instance?.sessions[sessionId] = session
            return session
          }
        #endif
        return nil
      },
      onCancellationChanged: { [weak instance] cancel in
        instance?.cancelGeneration = cancel
      })
    GenerateContentChunkStreamHandler.register(
      with: registrar.messenger(),
      streamHandler: generateContentStreamHandler)
  }

  func stopGeneration(sessionId: String) throws {
    cancelGeneration?()
  }

  /// Whether the SDK this plugin was compiled against, and the current OS,
  /// support image input (Foundation Models' `Attachment`, iOS 27+ — Beta).
  private var supportsImageInput: Bool {
    #if compiler(>=6.4)
      if #available(iOS 27.0, *) {
        return true
      }
    #endif
    return false
  }

  func checkAvailability(
    feature: EdgeGenAIFeature, completion: @escaping (Result<EdgeGenAIAvailability, Error>) -> Void
  ) {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, *) {
        // Every feature is backed by the one system model, so they share its
        // availability — except image description, which additionally needs
        // image input support.
        if feature == .imageDescription && !supportsImageInput {
          completion(.success(.unavailable))
          return
        }
        completion(.success(FoundationModelsBridge.checkAvailability()))
        return
      }
    #endif
    completion(.success(.unavailable))
  }

  func startGenerateContent(
    sessionId: String, prompt: String, options: EdgeGenAIGenerationOptions?, useMemory: Bool,
    image: FlutterStandardTypedData?, tools: [EdgeGenAIToolDefinition]
  ) throws {
    pendingRequest = PendingGenerateContentRequest(
      sessionId: sessionId, prompt: prompt, options: options, useMemory: useMemory,
      image: image?.data, tools: tools)
  }

  func resetConversation(sessionId: String) throws {
    sessions.removeValue(forKey: sessionId)
  }

  func summarize(text: String, completion: @escaping (Result<String, Error>) -> Void) {
    respondOneShot(
      instructions:
        "You are a summarizer. Summarize the text you are given in at most three short "
        + "bullet points. Respond with only the summary.",
      prompt: text,
      completion: completion)
  }

  func proofread(text: String, completion: @escaping (Result<String, Error>) -> Void) {
    respondOneShot(
      instructions:
        "You are a proofreader. Correct grammar, spelling, and punctuation mistakes in the "
        + "text you are given without changing its meaning or tone. Respond with only the "
        + "corrected text.",
      prompt: text,
      completion: completion)
  }

  func rewrite(
    text: String, style: EdgeGenAIRewriteStyle,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    let styleInstruction: String
    switch style {
    case .rephrase:
      styleInstruction = "rephrasing it while keeping its meaning and roughly its length"
    case .elaborate:
      styleInstruction = "expanding on it with more detail"
    case .emojify:
      styleInstruction = "adding fitting emoji"
    case .shorten:
      styleInstruction = "making it shorter while keeping its meaning"
    case .friendly:
      styleInstruction = "giving it a casual, friendly tone"
    case .professional:
      styleInstruction = "giving it a formal, professional tone"
    }
    respondOneShot(
      instructions:
        "You rewrite text. Rewrite the text you are given, \(styleInstruction). "
        + "Respond with only the rewritten text.",
      prompt: text,
      completion: completion)
  }

  func describeImage(
    imageBytes: FlutterStandardTypedData, completion: @escaping (Result<String, Error>) -> Void
  ) {
    #if canImport(FoundationModels) && compiler(>=6.4)
      if #available(iOS 27.0, *) {
        Task {
          do {
            let description = try await FoundationModelsBridge.describeImage(
              imageBytes.data)
            DispatchQueue.main.async { completion(.success(description)) }
          } catch {
            let wrapped = PigeonError.wrapping(error, fallbackCode: "describe_image_failed")
            DispatchQueue.main.async { completion(.failure(wrapped)) }
          }
        }
        return
      }
    #endif
    completion(
      .failure(
        PigeonError(
          code: "unavailable",
          message: "Image description requires iOS 27 or later.", details: nil)))
  }

  /// Runs a one-shot, stateless generation with a task-specific instruction,
  /// which is how the task-specific features (summarize, proofread, rewrite)
  /// are implemented on iOS — there are no dedicated system APIs for them.
  private func respondOneShot(
    instructions: String, prompt: String,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, *) {
        Task {
          do {
            let response = try await FoundationModelsBridge.respondOneShot(
              instructions: instructions, prompt: prompt)
            DispatchQueue.main.async { completion(.success(response)) }
          } catch {
            let wrapped = PigeonError.wrapping(error, fallbackCode: "generate_content_failed")
            DispatchQueue.main.async { completion(.failure(wrapped)) }
          }
        }
        return
      }
    #endif
    completion(
      .failure(
        PigeonError(
          code: "unavailable", message: "The on-device model isn't available.", details: nil)))
  }
}
