import UIKit

#if canImport(FoundationModels)
  import FoundationModels

  /// Bridges Apple's Foundation Models framework to the plugin.
  ///
  /// Everything that touches `FoundationModels` types lives here, gated once
  /// at the type level with `@available`, so callers elsewhere only need a
  /// single `if #available(iOS 26.0, *)` check to cross into this API
  /// instead of repeating framework-specific logic inline at every call site.
  @available(iOS 26.0, *)
  enum FoundationModelsBridge {
    /// Maps the system model's availability to the plugin's cross-platform enum.
    static func checkAvailability() -> EdgeGenAIAvailability {
      switch SystemLanguageModel.default.availability {
      case .available:
        return .available
      case .unavailable(.deviceNotEligible):
        return .unavailable
      case .unavailable(.appleIntelligenceNotEnabled):
        return .notYetReady
      case .unavailable(.modelNotReady):
        return .downloadable
      case .unavailable:
        return .unavailable
      }
    }

    /// Reuses `existing` if it's already a `LanguageModelSession`, otherwise
    /// creates a new one bound to `tools`.
    ///
    /// Reusing the same session across calls lets the model remember prior
    /// turns in the conversation, since the framework records every prompt
    /// and response into the session's transcript automatically. Tools are
    /// bound at session creation — the framework offers no way to change
    /// them later — which is why `EdgeGenAIPrompt` fixes tools per instance.
    static func getOrCreateSession(_ existing: Any?, tools: [any Tool]) -> LanguageModelSession {
      existing as? LanguageModelSession ?? LanguageModelSession(tools: tools)
    }

    /// Builds the native `Tool`s backing the Dart-defined tools, so the
    /// model can call back into the app through `toolExecutorApi`.
    static func makeTools(
      definitions: [EdgeGenAIToolDefinition],
      sessionId: String,
      toolExecutorApi: EdgeGenAIToolExecutorApi
    ) -> [any Tool] {
      definitions.compactMap { definition in
        DartBackedTool(
          definition: definition, sessionId: sessionId, toolExecutorApi: toolExecutorApi)
      }
    }

    /// Runs a one-shot, stateless generation of a response to `prompt` from
    /// a fresh session configured with the task-specific `instructions`.
    static func respondOneShot(instructions: String, prompt: String) async throws -> String {
      let session = LanguageModelSession(instructions: instructions)
      return try await session.respond(to: prompt).content
    }

    /// Streams a response to `prompt` (and, optionally, `image`) from
    /// `session`, invoking `onChunk` with the cumulative text generated so
    /// far on every update.
    static func streamResponse(
      session: LanguageModelSession,
      prompt: String,
      image: Data?,
      options: EdgeGenAIGenerationOptions?,
      onChunk: (String) -> Void
    ) async throws {
      let generationOptions = GenerationOptions(
        temperature: options?.temperature,
        maximumResponseTokens: options?.maxOutputTokens.map { Int($0) })
      if let image {
        #if compiler(>=6.4)
          if #available(iOS 27.0, *) {
            let attachedImage = try cgImage(from: image)
            let stream = session.streamResponse(options: generationOptions) {
              prompt
              Attachment(attachedImage)
            }
            for try await snapshot in stream {
              onChunk(snapshot.content)
            }
            return
          }
        #endif
        throw PigeonError(
          code: "unavailable",
          message: "Sending an image with a prompt requires iOS 27 or later.", details: nil)
      }
      let stream = session.streamResponse(to: prompt, options: generationOptions)
      for try await snapshot in stream {
        onChunk(snapshot.content)
      }
    }

    #if compiler(>=6.4)
      /// Describes the image encoded in `image` via a one-shot generation
      /// with the image attached to the prompt.
      @available(iOS 27.0, *)
      static func describeImage(_ image: Data) async throws -> String {
        let session = LanguageModelSession(
          instructions:
            "You describe images. Describe the image you are given concisely and "
            + "objectively. Respond with only the description.")
        let attachedImage = try cgImage(from: image)
        let response = try await session.respond {
          "Describe this image."
          Attachment(attachedImage)
        }
        return response.content
      }
    #endif

    /// Decodes encoded image bytes (for example PNG or JPEG) into a `CGImage`.
    private static func cgImage(from data: Data) throws -> CGImage {
      guard let cgImage = UIImage(data: data)?.cgImage else {
        throw PigeonError(
          code: "invalid_image", message: "The image bytes couldn't be decoded.", details: nil)
      }
      return cgImage
    }
  }
#endif
