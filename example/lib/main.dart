import 'dart:async';

import 'package:edge_gen_ai/edge_gen_ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image_picker/image_picker.dart';

import 'function_calling_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static ThemeData _theme(Brightness brightness, Color primaryColor) {
    final colorScheme = ThemeData(
      brightness: brightness,
    ).colorScheme.copyWith(primary: primaryColor, secondary: primaryColor);
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;
  Color _themeColor = Colors.blue;

  void _setTheme({required ThemeMode mode, required Color color}) {
    setState(() {
      _themeMode = mode;
      _themeColor = color;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EdgeGenAi',
      themeMode: _themeMode,
      theme: MyApp._theme(Brightness.light, _themeColor),
      darkTheme: MyApp._theme(Brightness.dark, _themeColor),
      home: DefaultTabController(
        length: 6,
        child: Scaffold(
          appBar: AppBar(
            title: const Text(
              'EdgeGenAi',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            bottom: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Chat'),
                Tab(icon: Icon(Icons.call_outlined), text: 'Function calling'),
                Tab(icon: Icon(Icons.summarize_outlined), text: 'Summarize'),
                Tab(icon: Icon(Icons.spellcheck), text: 'Proofread'),
                Tab(icon: Icon(Icons.auto_fix_high), text: 'Rewrite'),
                Tab(icon: Icon(Icons.image_outlined), text: 'Describe image'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              const ChatPage(),
              FunctionCallingPage(onThemeChanged: _setTheme),
              const SummarizePage(),
              const ProofreadPage(),
              const RewritePage(),
              const ImageDescriptionPage(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A card that displays a one-shot tool's result, used by the summarize,
/// proofread, rewrite, and image description tabs.
class _ResultCard extends StatelessWidget {
  const _ResultCard(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Result',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            MarkdownBody(data: text),
          ],
        ),
      ),
    );
  }
}

/// A single message in the conversation transcript shown in the example UI.
class _ChatMessage {
  _ChatMessage({required this.isUser, required this.text, this.image});

  final bool isUser;
  String text;
  final Uint8List? image;
}

/// Chat demo built on [EdgeGenAIPrompt] with conversation memory.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with AutomaticKeepAliveClientMixin {
  EdgeGenAIAvailability? _availability;
  EdgeGenAIDownloadProgress? _downloadProgress;
  final List<_ChatMessage> _messages = [];
  bool _isGenerating = false;
  var _prompt = _buildPrompt(useMemory: true);

  /// Builds a chat prompt with the selected memory behavior.
  static EdgeGenAIPrompt _buildPrompt({required bool useMemory}) {
    return EdgeGenAIPrompt(useMemory: useMemory);
  }

  final _promptController = TextEditingController();
  Uint8List? _pendingImage;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> initPlatformState() async {
    EdgeGenAIAvailability availability;
    try {
      availability = await _prompt.checkAvailability();
    } on PlatformException {
      availability = EdgeGenAIAvailability.unavailable;
    }

    if (!mounted) return;

    setState(() {
      _availability = availability;
    });
  }

  void _downloadModel() {
    _prompt.downloadModel().listen(
      (progress) {
        if (!mounted) return;
        setState(() => _downloadProgress = progress);
      },
      onError: (Object error) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $error')));
      },
    );
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => _pendingImage = bytes);
  }

  void _generateContent() {
    final prompt = _promptController.text;
    if (prompt.trim().isEmpty) return;
    final image = _pendingImage;
    FocusManager.instance.primaryFocus?.unfocus();

    final modelMessage = _ChatMessage(isUser: false, text: '');
    setState(() {
      _isGenerating = true;
      _messages.add(_ChatMessage(isUser: true, text: prompt, image: image));
      _messages.add(modelMessage);
      _pendingImage = null;
    });
    _promptController.clear();

    _prompt
        .generateContent(prompt, image: image)
        .listen(
          (chunk) {
            if (!mounted) return;
            setState(() => modelMessage.text = chunk);
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _isGenerating = false;
              modelMessage.text = 'Failed to generate content: $error';
            });
          },
          onDone: () {
            if (!mounted) return;
            setState(() => _isGenerating = false);
          },
        );
  }

  Future<void> _resetConversation() async {
    await _prompt.resetConversation();
    if (!mounted) return;
    setState(() => _messages.clear());
  }

  void _setUseMemory(bool useMemory) {
    if (useMemory == _prompt.useMemory) return;
    // useMemory is fixed per EdgeGenAIPrompt instance, so switching it means
    // starting a fresh conversation on a new instance.
    setState(() {
      _prompt = _buildPrompt(useMemory: useMemory);
      _messages.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final canDownload = _availability == EdgeGenAIAvailability.downloadable;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Icon(
                switch (_availability) {
                  EdgeGenAIAvailability.available => Icons.check_circle,
                  EdgeGenAIAvailability.downloadable => Icons.cloud_download,
                  null => Icons.hourglass_empty,
                  _ => Icons.error_outline,
                },
                size: 18,
                color: colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Availability: ${_availability?.name ?? 'Checking...'}'
                  '${_downloadProgress != null ? ' — ${_downloadProgress!.status.name}'
                            '${_downloadProgress!.bytesDownloaded != null ? ' (${_downloadProgress!.bytesDownloaded} bytes)' : ''}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (canDownload)
                TextButton(
                  onPressed: _downloadModel,
                  child: const Text('Download'),
                ),
              Tooltip(
                message: 'Conversation memory',
                child: Icon(
                  Icons.memory,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Switch(value: _prompt.useMemory, onChanged: _setUseMemory),
              IconButton(
                onPressed: _messages.isEmpty ? null : _resetConversation,
                icon: const Icon(Icons.refresh),
                tooltip: 'New conversation',
              ),
            ],
          ),
        ),
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 40,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Say hello to get started.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    return Align(
                      alignment: message.isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.78,
                        ),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: message.isUser
                                ? colorScheme.primaryContainer
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(
                                message.isUser ? 18 : 4,
                              ),
                              bottomRight: Radius.circular(
                                message.isUser ? 4 : 18,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (message.image != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.memory(
                                      message.image!,
                                      height: 150,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              MarkdownBody(data: message.text),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_pendingImage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            _pendingImage!,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.black54,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              iconSize: 16,
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                              ),
                              onPressed: () =>
                                  setState(() => _pendingImage = null),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    IconButton(
                      onPressed: _isGenerating ? null : _pickImage,
                      icon: const Icon(Icons.image_outlined),
                      tooltip: 'Attach image',
                    ),
                    Expanded(
                      child: TextField(
                        controller: _promptController,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Message',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _isGenerating ? null : _generateContent,
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A one-shot text tool demo page: enter text, run [action], show the
/// result. Shared by the summarize and proofread tabs, which only differ
/// in their initial text, button label, and action.
class _TextToolPage extends StatefulWidget {
  const _TextToolPage({
    required this.initialText,
    required this.buttonLabel,
    required this.icon,
    required this.action,
  });

  final String initialText;
  final String buttonLabel;
  final IconData icon;
  final Future<String> Function(String text) action;

  @override
  State<_TextToolPage> createState() => _TextToolPageState();
}

class _TextToolPageState extends State<_TextToolPage>
    with AutomaticKeepAliveClientMixin {
  late final _controller = TextEditingController(text: widget.initialText);
  String? _result;
  bool _isRunning = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    setState(() {
      _isRunning = true;
      _result = null;
    });
    String result;
    try {
      result = await widget.action(text);
      /*

  /// Demonstrates the ways a tool can receive arguments from the model.
  class FunctionCallingPage extends StatefulWidget {
    const FunctionCallingPage({super.key});

    @override
    State<FunctionCallingPage> createState() => _FunctionCallingPageState();
  }

  class _FunctionCallingPageState extends State<FunctionCallingPage>
      with AutomaticKeepAliveClientMixin {
    late final EdgeGenAIPrompt _prompt = EdgeGenAIPrompt(
      tools: [
        EdgeGenAITool(
          name: 'get_battery_percentage',
          description: 'Gets the current device battery percentage.',
          onCall: (_) async => '${await Battery().batteryLevel}%',
        ),
        EdgeGenAITool(
          name: 'get_device_status',
          description:
              'Gets the default device status. Both parameters are optional '
              'and default to false when omitted.',
          parameters: [
            EdgeGenAIToolParameter(
              name: 'includeBattery',
              description: 'Whether to include the battery percentage.',
              type: EdgeGenAIToolParameterType.boolean,
              isRequired: false,
            ),
            EdgeGenAIToolParameter(
              name: 'verbose',
              description: 'Whether to include extra status detail.',
              type: EdgeGenAIToolParameterType.boolean,
              isRequired: false,
            ),
          ],
          onCall: _getDeviceStatus,
        ),
        EdgeGenAITool(
          name: 'create_reminder',
          description: 'Creates a reminder after a specified number of minutes.',
          parameters: [
            EdgeGenAIToolParameter(
              name: 'title',
              description: 'What the reminder is about.',
            ),
            EdgeGenAIToolParameter(
              name: 'minutesFromNow',
              description: 'How many minutes from now it should fire.',
              type: EdgeGenAIToolParameterType.integer,
            ),
          ],
          onCall: _createReminder,
        ),
      ],
    );
    final _controller = TextEditingController();
    String? _result;
    bool _isGenerating = false;

    @override
    bool get wantKeepAlive => true;

    @override
    void dispose() {
      _controller.dispose();
      super.dispose();
    }

    static Future<String> _getDeviceStatus(
      Map<String, Object?> arguments,
    ) async {
      final includeBattery = arguments['includeBattery'] as bool? ?? false;
      final verbose = arguments['verbose'] as bool? ?? false;
      final details = <String>['Device is ready.'];
      if (includeBattery) details.add('Battery: ${await Battery().batteryLevel}%');
      if (verbose) details.add('Using default status checks.');
      return details.join(' ');
    }

    static Future<String> _createReminder(
      Map<String, Object?> arguments,
    ) async {
      final title = arguments['title'] as String? ?? 'Untitled reminder';
      final minutes = arguments['minutesFromNow'] as int? ?? 0;
      return 'Reminder "$title" created for $minutes minutes from now.';
    }

    void _useExample(String prompt) {
      setState(() => _controller.text = prompt);
    }

    void _generate() {
      final prompt = _controller.text.trim();
      if (prompt.isEmpty) return;
      setState(() {
        _isGenerating = true;
        _result = null;
      });
      _prompt.generateContent(prompt).listen(
        (chunk) {
          if (!mounted) return;
          setState(() => _result = chunk);
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _isGenerating = false;
            _result = 'Failed to generate content: $error';
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() => _isGenerating = false);
        },
      );
    }

    @override
    Widget build(BuildContext context) {
      super.build(context);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose an example, then ask the model to run it.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _FunctionExample(
              title: 'No parameters, no arguments',
              detail: 'get_battery_percentage() returns the battery level.',
              prompt: 'What is my battery percentage?',
              onTap: _useExample,
            ),
            const SizedBox(height: 8),
            _FunctionExample(
              title: 'Few parameters, no arguments',
              detail: 'get_device_status has two optional values and uses defaults.',
              prompt: 'Give me the default device status.',
              onTap: _useExample,
            ),
            const SizedBox(height: 8),
            _FunctionExample(
              title: 'Few parameters, few arguments',
              detail: 'create_reminder receives a title and a number of minutes.',
              prompt: 'Remind me to stretch in 15 minutes.',
              onTap: _useExample,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Prompt',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _generate(),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _isGenerating ? null : _generate,
              icon: _isGenerating
                  ? const SizedBox(
      */
    } catch (error) {
      result = 'Failed: $error';
    }
    if (!mounted) return;
    setState(() {
      _isRunning = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    /*
  }

  class _FunctionExample extends StatelessWidget {
    const _FunctionExample({
      required this.title,
      required this.detail,
      required this.prompt,
      required this.onTap,
    });

    final String title;
    final String detail;
    final String prompt;
    final ValueChanged<String> onTap;

    @override
    Widget build(BuildContext context) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(title),
        subtitle: Text(detail),
        trailing: const Icon(Icons.arrow_forward),
        onTap: () => onTap(prompt),
      );
    }
  */
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Text',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _isRunning ? null : _run,
            icon: _isRunning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(widget.icon),
            label: Text(widget.buttonLabel),
          ),
          const SizedBox(height: 16),
          if (_result != null) _ResultCard(_result!),
        ],
      ),
    );
  }
}

/// Demo of [EdgeGenAISummarizer].
class SummarizePage extends StatelessWidget {
  const SummarizePage({super.key});

  @override
  Widget build(BuildContext context) {
    return _TextToolPage(
      // Android's summarizer requires at least 400 characters of input for
      // its default ARTICLE input type, so this needs to be a real
      // paragraph rather than a couple of short sentences.
      initialText:
          'The quick brown fox jumps over the lazy dog. It was a sunny day '
          'and everyone in the neighborhood was outside enjoying the '
          'weather, playing games, and having picnics in the park. Children '
          'rode their bicycles up and down the street while their parents '
          'set up folding chairs and coolers on the front lawns. Someone '
          'brought a portable speaker and played music that could be heard '
          'from several houses away. By the time the sun began to set, '
          'everyone agreed it had been one of the best days of the summer '
          'so far, and several neighbors started planning another '
          'get-together for the following weekend.',
      buttonLabel: 'Summarize',
      icon: Icons.summarize_outlined,
      action: EdgeGenAISummarizer().summarize,
    );
  }
}

/// Demo of [EdgeGenAIProofreader].
class ProofreadPage extends StatelessWidget {
  const ProofreadPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _TextToolPage(
      initialText:
          'the quick brown fox jumsp over the lazy dog it was a sunny day '
          'and everyone was outside enjoying the wether',
      buttonLabel: 'Proofread',
      icon: Icons.spellcheck,
      action: EdgeGenAIProofreader().proofread,
    );
  }
}

/// Demo of [EdgeGenAIRewriter], which additionally needs a style picker.
class RewritePage extends StatefulWidget {
  const RewritePage({super.key});

  @override
  State<RewritePage> createState() => _RewritePageState();
}

class _RewritePageState extends State<RewritePage>
    with AutomaticKeepAliveClientMixin {
  final _rewriter = EdgeGenAIRewriter();
  final _controller = TextEditingController(
    text:
        'Hey, can you send me the report when you get a chance? Thanks a '
        'lot!',
  );
  EdgeGenAIRewriteStyle _style = EdgeGenAIRewriteStyle.professional;
  String? _result;
  bool _isRunning = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    setState(() {
      _isRunning = true;
      _result = null;
    });
    String result;
    try {
      result = await _rewriter.rewrite(text, style: _style);
    } catch (error) {
      result = 'Failed: $error';
    }
    if (!mounted) return;
    setState(() {
      _isRunning = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Text',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _isRunning ? null : _run,
                icon: _isRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_fix_high),
                label: const Text('Rewrite'),
              ),
              DropdownButton<EdgeGenAIRewriteStyle>(
                value: _style,
                items: [
                  for (final style in EdgeGenAIRewriteStyle.values)
                    DropdownMenuItem(value: style, child: Text(style.name)),
                ],
                onChanged: (style) {
                  if (style != null) setState(() => _style = style);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_result != null) _ResultCard(_result!),
        ],
      ),
    );
  }
}

/// Demo of [EdgeGenAIImageDescriber]: pick a photo, then describe it.
class ImageDescriptionPage extends StatefulWidget {
  const ImageDescriptionPage({super.key});

  @override
  State<ImageDescriptionPage> createState() => _ImageDescriptionPageState();
}

class _ImageDescriptionPageState extends State<ImageDescriptionPage>
    with AutomaticKeepAliveClientMixin {
  final _describer = EdgeGenAIImageDescriber();
  Uint8List? _imageBytes;
  String? _result;
  bool _isRunning = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _imageBytes = bytes;
      _result = null;
    });
  }

  Future<void> _describe() async {
    final bytes = _imageBytes;
    if (bytes == null) return;
    setState(() {
      _isRunning = true;
      _result = null;
    });
    String result;
    try {
      result = await _describer.describeImage(bytes);
    } catch (error) {
      result = 'Failed: $error';
    }
    if (!mounted) return;
    setState(() {
      _isRunning = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final imageBytes = _imageBytes;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (imageBytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(imageBytes, height: 200, fit: BoxFit.cover),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Pick image'),
              ),
              FilledButton.icon(
                onPressed: (imageBytes == null || _isRunning)
                    ? null
                    : _describe,
                icon: _isRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_search),
                label: const Text('Describe'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_result != null) _ResultCard(_result!),
        ],
      ),
    );
  }
}
