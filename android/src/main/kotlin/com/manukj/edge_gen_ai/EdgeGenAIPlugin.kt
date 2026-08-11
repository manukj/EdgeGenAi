package com.manukj.edge_gen_ai

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.google.mlkit.genai.common.DownloadCallback
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.imagedescription.ImageDescriber
import com.google.mlkit.genai.imagedescription.ImageDescriberOptions
import com.google.mlkit.genai.imagedescription.ImageDescription
import com.google.mlkit.genai.imagedescription.ImageDescriptionRequest
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.ImagePart
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import com.google.mlkit.genai.proofreading.Proofreader
import com.google.mlkit.genai.proofreading.ProofreaderOptions
import com.google.mlkit.genai.proofreading.Proofreading
import com.google.mlkit.genai.proofreading.ProofreadingRequest
import com.google.mlkit.genai.rewriting.Rewriter
import com.google.mlkit.genai.rewriting.RewriterOptions
import com.google.mlkit.genai.rewriting.Rewriting
import com.google.mlkit.genai.rewriting.RewritingRequest
import com.google.mlkit.genai.summarization.Summarization
import com.google.mlkit.genai.summarization.SummarizationRequest
import com.google.mlkit.genai.summarization.Summarizer
import com.google.mlkit.genai.summarization.SummarizerOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.guava.await
import kotlinx.coroutines.launch

/** The request stashed by `startGenerateContent` for the next `generateContentChunk` listener. */
private class PendingGenerateContentRequest(
    val sessionId: String,
    val prompt: String,
    val options: EdgeGenAIGenerationOptions?,
    val useMemory: Boolean,
    val image: ByteArray?,
    val tools: List<EdgeGenAIToolDefinition>
)

/** Runs a suspending operation and forwards its success or failure to Pigeon. */
private fun <T> CoroutineScope.launchWithResult(
    callback: (Result<T>) -> Unit,
    operation: suspend () -> T
) {
    launch {
        try {
            callback(Result.success(operation()))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }
}

/** Emits one consistently shaped download-progress event. */
private fun PigeonEventSink<EdgeGenAIDownloadProgress>.sendProgress(
    status: EdgeGenAIDownloadStatus,
    bytesDownloaded: Long? = null
) {
    success(EdgeGenAIDownloadProgress(status, bytesDownloaded))
}

/** EdgeGenAIPlugin */
class EdgeGenAIPlugin :
    FlutterPlugin,
    EdgeGenAIHostApi {
    private var pluginBinding: FlutterPlugin.FlutterPluginBinding? = null
    private val scope = CoroutineScope(Dispatchers.Main)
    private val context: Context
        get() = requireNotNull(pluginBinding).applicationContext
    private val generativeModel by lazy { Generation.getClient() }
    private val summarizer: Summarizer by lazy {
        Summarization.getClient(
            SummarizerOptions.builder(context)
                .setInputType(SummarizerOptions.InputType.ARTICLE)
                .setOutputType(SummarizerOptions.OutputType.THREE_BULLETS)
                .build()
        )
    }
    private val proofreader: Proofreader by lazy {
        Proofreading.getClient(
            ProofreaderOptions.builder(context)
                .setInputType(ProofreaderOptions.InputType.KEYBOARD)
                .build()
        )
    }
    private val imageDescriber: ImageDescriber by lazy {
        ImageDescription.getClient(ImageDescriberOptions.builder(context).build())
    }

    // The rewriting feature's model is shared across styles, so any style
    // works for availability checks and downloads; inference clients are
    // created per call with the requested style (see `rewrite`).
    private val rewriterForLifecycle: Rewriter by lazy {
        Rewriting.getClient(
            RewriterOptions.builder(context)
                .setOutputType(RewriterOptions.OutputType.REPHRASE)
                .build()
        )
    }

    private var pendingRequest: PendingGenerateContentRequest? = null

    // Prompt-to-response pairs for prior turns, keyed by the Dart-side
    // `EdgeGenAIPrompt` instance's session id. The ML Kit GenAI Prompt API
    // has no native session, so this is manually prepended to each new
    // prompt (see ConversationHistory) to fake conversation memory.
    private val histories = mutableMapOf<String, MutableList<Pair<String, String>>>()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        pluginBinding = flutterPluginBinding
        EdgeGenAIHostApi.setUp(flutterPluginBinding.binaryMessenger, this)
        PromptDownloadProgressStreamHandler.register(
            flutterPluginBinding.binaryMessenger,
            PromptDownloadStreamHandler(scope, generativeModel),
        )
        SummarizationDownloadProgressStreamHandler.register(
            flutterPluginBinding.binaryMessenger,
            SummarizationDownloadStreamHandler(scope) { summarizer },
        )
        ProofreadingDownloadProgressStreamHandler.register(
            flutterPluginBinding.binaryMessenger,
            ProofreadingDownloadStreamHandler(scope) { proofreader },
        )
        RewritingDownloadProgressStreamHandler.register(
            flutterPluginBinding.binaryMessenger,
            RewritingDownloadStreamHandler(scope) { rewriterForLifecycle },
        )
        ImageDescriptionDownloadProgressStreamHandler.register(
            flutterPluginBinding.binaryMessenger,
            ImageDescriptionDownloadStreamHandler(scope) { imageDescriber },
        )
        GenerateContentChunkStreamHandler.register(
            flutterPluginBinding.binaryMessenger,
            EdgeGenAIGenerateContentStreamHandler(
                scope,
                generativeModel,
                histories,
                EdgeGenAIToolExecutorApi(flutterPluginBinding.binaryMessenger),
            ) {
                pendingRequest.also { pendingRequest = null }
            },
        )
    }

    override fun checkAvailability(
        feature: EdgeGenAIFeature,
        callback: (Result<EdgeGenAIAvailability>) -> Unit
    ) {
        scope.launchWithResult(callback) {
            val status =
                when (feature) {
                    EdgeGenAIFeature.PROMPT -> generativeModel.checkStatus()
                    EdgeGenAIFeature.SUMMARIZATION -> summarizer.checkFeatureStatus().await()
                    EdgeGenAIFeature.PROOFREADING -> proofreader.checkFeatureStatus().await()
                    EdgeGenAIFeature.REWRITING ->
                        rewriterForLifecycle.checkFeatureStatus().await()
                    EdgeGenAIFeature.IMAGE_DESCRIPTION ->
                        imageDescriber.checkFeatureStatus().await()
                }
            when (status) {
                FeatureStatus.AVAILABLE -> EdgeGenAIAvailability.AVAILABLE
                FeatureStatus.DOWNLOADABLE, FeatureStatus.DOWNLOADING ->
                    EdgeGenAIAvailability.DOWNLOADABLE
                else -> EdgeGenAIAvailability.UNAVAILABLE
            }
        }
    }

    override fun startGenerateContent(
        sessionId: String,
        prompt: String,
        options: EdgeGenAIGenerationOptions?,
        useMemory: Boolean,
        image: ByteArray?,
        tools: List<EdgeGenAIToolDefinition>
    ) {
        pendingRequest =
            PendingGenerateContentRequest(sessionId, prompt, options, useMemory, image, tools)
    }

    override fun resetConversation(sessionId: String) {
        histories.remove(sessionId)
    }

    override fun summarize(
        text: String,
        callback: (Result<String>) -> Unit
    ) {
        scope.launchWithResult(callback) {
            summarizer
                .runInference(SummarizationRequest.builder(text).build())
                .await()
                .summary
        }
    }

    override fun proofread(
        text: String,
        callback: (Result<String>) -> Unit
    ) {
        scope.launchWithResult(callback) {
            val result =
                proofreader
                    .runInference(ProofreadingRequest.builder(text).build())
                    .await()
            // No suggestions means the model found nothing to fix.
            result.results.firstOrNull()?.text ?: text
        }
    }

    override fun rewrite(
        text: String,
        style: EdgeGenAIRewriteStyle,
        callback: (Result<String>) -> Unit
    ) {
        val outputType =
            when (style) {
                EdgeGenAIRewriteStyle.REPHRASE -> RewriterOptions.OutputType.REPHRASE
                EdgeGenAIRewriteStyle.ELABORATE -> RewriterOptions.OutputType.ELABORATE
                EdgeGenAIRewriteStyle.EMOJIFY -> RewriterOptions.OutputType.EMOJIFY
                EdgeGenAIRewriteStyle.SHORTEN -> RewriterOptions.OutputType.SHORTEN
                EdgeGenAIRewriteStyle.FRIENDLY -> RewriterOptions.OutputType.FRIENDLY
                EdgeGenAIRewriteStyle.PROFESSIONAL -> RewriterOptions.OutputType.PROFESSIONAL
            }
        scope.launchWithResult(callback) {
            val rewriter =
                Rewriting.getClient(
                    RewriterOptions.builder(context).setOutputType(outputType).build()
                )
            try {
                val result =
                    rewriter
                        .runInference(RewritingRequest.builder(text).build())
                        .await()
                result.results.firstOrNull()?.text ?: text
            } finally {
                rewriter.close()
            }
        }
    }

    override fun describeImage(
        imageBytes: ByteArray,
        callback: (Result<String>) -> Unit
    ) {
        val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
        if (bitmap == null) {
            callback(
                Result.failure(
                    FlutterError("invalid_image", "The image bytes couldn't be decoded.", null)
                )
            )
            return
        }
        scope.launchWithResult(callback) {
            imageDescriber
                .runInference(ImageDescriptionRequest.builder(bitmap).build())
                .await()
                .description
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        pluginBinding?.let { EdgeGenAIHostApi.setUp(it.binaryMessenger, null) }
        pluginBinding = null
    }
}

/** Triggers the Gemini Nano download when Flutter starts listening, and streams its progress. */
private class PromptDownloadStreamHandler(
    private val scope: CoroutineScope,
    private val generativeModel: GenerativeModel
) : PromptDownloadProgressStreamHandler() {
    override fun onListen(
        p0: Any?,
        sink: PigeonEventSink<EdgeGenAIDownloadProgress>
    ) {
        scope.launch {
            generativeModel.download().collect { status ->
                when (status) {
                    is DownloadStatus.DownloadStarted ->
                        sink.sendProgress(EdgeGenAIDownloadStatus.STARTED)
                    is DownloadStatus.DownloadProgress ->
                        sink.sendProgress(
                            EdgeGenAIDownloadStatus.IN_PROGRESS,
                            status.totalBytesDownloaded,
                        )
                    is DownloadStatus.DownloadCompleted -> {
                        sink.sendProgress(EdgeGenAIDownloadStatus.COMPLETED)
                        sink.endOfStream()
                    }
                    is DownloadStatus.DownloadFailed ->
                        sink.error("download_failed", status.e.message, null)
                }
            }
        }
    }
}

/**
 * Checks the feature's status when Flutter starts listening and, if a download is needed,
 * triggers it via [download] and streams its progress into [sink].
 *
 * Shared by the download stream handlers of all four task-specific ML Kit GenAI features,
 * which expose the same `checkFeatureStatus()`/`downloadFeature()` shape but no common
 * Kotlin supertype — hence the lambdas.
 */
private fun downloadFeatureInto(
    scope: CoroutineScope,
    sink: PigeonEventSink<EdgeGenAIDownloadProgress>,
    checkStatus: suspend () -> Int,
    download: (DownloadCallback) -> Unit
) {
    scope.launch {
        try {
            if (checkStatus() == FeatureStatus.AVAILABLE) {
                sink.sendProgress(EdgeGenAIDownloadStatus.COMPLETED)
                sink.endOfStream()
                return@launch
            }
        } catch (e: Exception) {
            sink.error("download_failed", e.message, null)
            return@launch
        }
        // DownloadCallback may be invoked off the main thread, but Pigeon
        // sinks must be called on it — hence the scope.launch per event.
        download(
            object : DownloadCallback {
                override fun onDownloadStarted(bytesToDownload: Long) {
                    scope.launch {
                        sink.sendProgress(EdgeGenAIDownloadStatus.STARTED)
                    }
                }

                override fun onDownloadProgress(totalBytesDownloaded: Long) {
                    scope.launch {
                        sink.sendProgress(
                            EdgeGenAIDownloadStatus.IN_PROGRESS,
                            totalBytesDownloaded,
                        )
                    }
                }

                override fun onDownloadCompleted() {
                    scope.launch {
                        sink.sendProgress(EdgeGenAIDownloadStatus.COMPLETED)
                        sink.endOfStream()
                    }
                }

                override fun onDownloadFailed(e: GenAiException) {
                    scope.launch { sink.error("download_failed", e.message, null) }
                }
            }
        )
    }
}

private class SummarizationDownloadStreamHandler(
    private val scope: CoroutineScope,
    private val summarizer: () -> Summarizer
) : SummarizationDownloadProgressStreamHandler() {
    override fun onListen(
        p0: Any?,
        sink: PigeonEventSink<EdgeGenAIDownloadProgress>
    ) {
        downloadFeatureInto(
            scope,
            sink,
            { summarizer().checkFeatureStatus().await() },
            { callback -> summarizer().downloadFeature(callback) },
        )
    }
}

private class ProofreadingDownloadStreamHandler(
    private val scope: CoroutineScope,
    private val proofreader: () -> Proofreader
) : ProofreadingDownloadProgressStreamHandler() {
    override fun onListen(
        p0: Any?,
        sink: PigeonEventSink<EdgeGenAIDownloadProgress>
    ) {
        downloadFeatureInto(
            scope,
            sink,
            { proofreader().checkFeatureStatus().await() },
            { callback -> proofreader().downloadFeature(callback) },
        )
    }
}

private class RewritingDownloadStreamHandler(
    private val scope: CoroutineScope,
    private val rewriter: () -> Rewriter
) : RewritingDownloadProgressStreamHandler() {
    override fun onListen(
        p0: Any?,
        sink: PigeonEventSink<EdgeGenAIDownloadProgress>
    ) {
        downloadFeatureInto(
            scope,
            sink,
            { rewriter().checkFeatureStatus().await() },
            { callback -> rewriter().downloadFeature(callback) },
        )
    }
}

private class ImageDescriptionDownloadStreamHandler(
    private val scope: CoroutineScope,
    private val imageDescriber: () -> ImageDescriber
) : ImageDescriptionDownloadProgressStreamHandler() {
    override fun onListen(
        p0: Any?,
        sink: PigeonEventSink<EdgeGenAIDownloadProgress>
    ) {
        downloadFeatureInto(
            scope,
            sink,
            { imageDescriber().checkFeatureStatus().await() },
            { callback -> imageDescriber().downloadFeature(callback) },
        )
    }
}

/**
 * Starts generation for the request stashed via `startGenerateContent` when Flutter
 * starts listening, and streams the cumulative response text as it's generated.
 *
 * When the request carries tools, generation runs as a multi-round loop instead
 * (see ToolPrompting): each round's full response is checked for a tool-call
 * JSON object; on a match the matching Dart executor runs via
 * [EdgeGenAIToolExecutorApi] and its result is fed into the next round. Only
 * the final answer is emitted, as a single event, since intermediate rounds
 * are tool-call JSON the caller shouldn't see.
 */
private class EdgeGenAIGenerateContentStreamHandler(
    private val scope: CoroutineScope,
    private val generativeModel: GenerativeModel,
    private val histories: MutableMap<String, MutableList<Pair<String, String>>>,
    private val toolExecutorApi: EdgeGenAIToolExecutorApi,
    private val takePendingRequest: () -> PendingGenerateContentRequest?
) : GenerateContentChunkStreamHandler() {
    private companion object {
        /** Bounds the tool-call loop so a confused model can't spin forever. */
        const val MAX_TOOL_ROUNDS = 4
    }

    override fun onListen(
        p0: Any?,
        sink: PigeonEventSink<String>
    ) {
        val request =
            takePendingRequest() ?: run {
                sink.error(
                    "no_prompt",
                    "startGenerateContent must be called before listening.",
                    null
                )
                return
            }
        val history =
            if (request.useMemory) {
                histories.getOrPut(request.sessionId) { mutableListOf() }
            } else {
                null
            }
        val promptWithHistory =
            history?.let { ConversationHistory.buildPrompt(it, request.prompt) }
                ?: request.prompt
        val bitmap =
            request.image?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        if (request.image != null && bitmap == null) {
            sink.error("invalid_image", "The image bytes couldn't be decoded.", null)
            return
        }
        scope.launch {
            try {
                val finalText =
                    if (request.tools.isEmpty()) {
                        generateText(request, promptWithHistory, bitmap) { text ->
                            sink.success(text)
                        }
                    } else {
                        runToolLoop(request, promptWithHistory, bitmap, sink)
                    }
                history?.add(request.prompt to finalText)
                sink.endOfStream()
            } catch (e: Exception) {
                sink.error("generate_content_failed", e.message, null)
            }
        }
    }

    /** Generates one complete response, optionally reporting cumulative text. */
    private suspend fun generateText(
        request: PendingGenerateContentRequest,
        prompt: String,
        bitmap: Bitmap?,
        onUpdate: (String) -> Unit = {}
    ): String {
        val cumulativeText = StringBuilder()
        generativeModel
            .generateContentStream(buildGenerateRequest(prompt, bitmap, request.options))
            .collect { response ->
                cumulativeText.append(response.candidates.first().text)
                onUpdate(cumulativeText.toString())
            }
        return cumulativeText.toString()
    }

    /** The tool-emulation path: loops rounds until the model stops calling tools. */
    private suspend fun runToolLoop(
        request: PendingGenerateContentRequest,
        prompt: String,
        bitmap: Bitmap?,
        sink: PigeonEventSink<String>
    ): String {
        var roundPrompt =
            ToolPrompting.buildToolPreamble(request.tools) + "\n\nUser request: " + prompt
        var rounds = 0
        while (true) {
            val responseText = generateText(request, roundPrompt, bitmap)
            val toolCall =
                if (rounds < MAX_TOOL_ROUNDS) {
                    ToolPrompting.parseToolCall(responseText, request.tools)
                } else {
                    null
                }
            if (toolCall == null) {
                sink.success(responseText)
                return responseText
            }
            rounds++
            val toolResult =
                callDartTool(request.sessionId, toolCall.toolName, toolCall.argumentsJson)
            roundPrompt += ToolPrompting.buildToolResultContinuation(toolCall, toolResult)
        }
    }

    /**
     * Runs the tool's Dart implementation and returns its result. Executor
     * failures come back as text for the model to react to, rather than
     * aborting the whole generation.
     */
    private suspend fun callDartTool(
        sessionId: String,
        toolName: String,
        argumentsJson: String
    ): String =
        suspendCoroutine { continuation ->
            toolExecutorApi.callTool(sessionId, toolName, argumentsJson) { result ->
                continuation.resume(
                    result.getOrElse { e -> "The tool failed with an error: ${e.message}" }
                )
            }
        }

    private fun buildGenerateRequest(
        prompt: String,
        bitmap: Bitmap?,
        options: EdgeGenAIGenerationOptions?
    ) = if (bitmap != null) {
        generateContentRequest(ImagePart(bitmap), TextPart(prompt)) {
            options?.temperature?.let { temperature = it.toFloat() }
            options?.maxOutputTokens?.let { maxOutputTokens = it.toInt() }
        }
    } else {
        generateContentRequest(TextPart(prompt)) {
            options?.temperature?.let { temperature = it.toFloat() }
            options?.maxOutputTokens?.let { maxOutputTokens = it.toInt() }
        }
    }
}
