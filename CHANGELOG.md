## 0.3.1

- Fixes Android builds when the plugin is installed from pub.dev by removing
  its dependency on an unpublished, machine-local `android/local.properties`
  file.

## 0.3.0

- Adds tool (function) calling through `EdgeGenAITool`.

## 0.2.0

- Adds Swift Package Manager support for iOS (in addition to CocoaPods).
- Migrates the Android build to built-in Kotlin on Android Gradle Plugin
  9+, while still applying the `kotlin-android` plugin on older AGP
  versions, so the minimum supported Flutter/Dart version is unchanged.

## 0.1.1

- Fix README screenshots not rendering on pub.dev by using absolute GitHub
  raw URLs instead of relative paths.

## 0.1.0

**Breaking changes**

- Renamed the package from `edge_ai` to `edge_gen_ai`. Update your
  dependency and imports (e.g. `package:edge_gen_ai/edge_gen_ai.dart`).
- Renamed the public API from the `EdgeAi` prefix to `EdgeGenAI`:
  - `EdgeAi` is now `EdgeGenAIPrompt`.
  - `EdgeAiAvailability`, `EdgeAiDownloadProgress`, `EdgeAiDownloadStatus`,
    and `EdgeAiGenerationOptions` are now `EdgeGenAIAvailability`,
    `EdgeGenAIDownloadProgress`, `EdgeGenAIDownloadStatus`, and
    `EdgeGenAIGenerationOptions`.
  - The platform interface (`EdgeGenAIPlatform`) and method channel
    implementation (`MethodChannelEdgeGenAI`) were renamed accordingly, and
    `checkAvailability`/`downloadModel` now take the `EdgeGenAIFeature`
    they apply to.

**New features**

- `EdgeGenAISummarizer`, `EdgeGenAIProofreader`, `EdgeGenAIRewriter`, and
  `EdgeGenAIImageDescriber`: one-shot text summarization, proofreading,
  rewriting (in a chosen `EdgeGenAIRewriteStyle`), and image description.
  Backed by ML Kit GenAI's dedicated APIs on Android and task-specific
  Foundation Models prompts on iOS, each with its own independent
  availability check and model download.
- `EdgeGenAIPrompt.generateContent` accepts an optional single `image`
  (encoded bytes) alongside the prompt. On iOS this requires iOS 27+
  (Foundation Models `Attachment`, Beta) and building with Xcode 27+.
- Conversation memory is now isolated per `EdgeGenAIPrompt` instance
  instead of shared per app process.

## 0.0.1

- Initial release: on-device availability check, model download with
  progress, streaming text generation with optional generation options,
  and optional conversation memory, backed by Apple's Foundation Models
  on iOS and ML Kit GenAI (Gemini Nano) on Android.
