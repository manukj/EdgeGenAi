import 'dart:typed_data';

import 'package:edge_gen_ai/edge_gen_ai.dart';
import 'package:edge_gen_ai/edge_gen_ai_method_channel.dart';
import 'package:edge_gen_ai/edge_gen_ai_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockEdgeGenAIPlatform
    with MockPlatformInterfaceMixin
    implements EdgeGenAIPlatform {
  final List<String> generateContentSessionIds = [];
  final List<String> resetConversationSessionIds = [];
  final List<List<EdgeGenAITool>> generateContentTools = [];

  @override
  Future<EdgeGenAIAvailability> checkAvailability(EdgeGenAIFeature feature) =>
      Future.value(EdgeGenAIAvailability.available);

  @override
  Stream<EdgeGenAIDownloadProgress> downloadModel(EdgeGenAIFeature feature) =>
      Stream.value(
        EdgeGenAIDownloadProgress(status: EdgeGenAIDownloadStatus.completed),
      );

  @override
  Stream<String> generateContent(
    String sessionId,
    String prompt, {
    EdgeGenAIGenerationOptions? options,
    bool useMemory = false,
    Uint8List? image,
    List<EdgeGenAITool> tools = const [],
  }) {
    generateContentSessionIds.add(sessionId);
    generateContentTools.add(tools);
    return Stream.value('a generated response');
  }

  @override
  Future<void> resetConversation(String sessionId) {
    resetConversationSessionIds.add(sessionId);
    return Future.value();
  }

  @override
  Future<String> summarize(String text) => Future.value('a summary');

  @override
  Future<String> proofread(String text) => Future.value('a corrected text');

  @override
  Future<String> rewrite(String text, {required EdgeGenAIRewriteStyle style}) =>
      Future.value('a rewritten text');

  @override
  Future<String> describeImage(Uint8List imageBytes) =>
      Future.value('an image description');
}

void main() {
  final EdgeGenAIPlatform initialPlatform = EdgeGenAIPlatform.instance;

  test('$MethodChannelEdgeGenAI is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelEdgeGenAI>());
  });

  late MockEdgeGenAIPlatform fakePlatform;

  setUp(() {
    fakePlatform = MockEdgeGenAIPlatform();
    EdgeGenAIPlatform.instance = fakePlatform;
  });

  test('checkAvailability', () async {
    expect(
      await EdgeGenAIPrompt().checkAvailability(),
      EdgeGenAIAvailability.available,
    );
  });

  test('downloadModel', () async {
    await expectLater(
      EdgeGenAIPrompt().downloadModel(),
      emits(
        EdgeGenAIDownloadProgress(status: EdgeGenAIDownloadStatus.completed),
      ),
    );
  });

  test('generateContent', () async {
    await expectLater(
      EdgeGenAIPrompt().generateContent('a prompt'),
      emits('a generated response'),
    );
  });

  test('each EdgeGenAIPrompt instance has its own session', () async {
    final first = EdgeGenAIPrompt(useMemory: true);
    final second = EdgeGenAIPrompt(useMemory: true);

    await first.generateContent('a prompt').drain<void>();
    await second.generateContent('a prompt').drain<void>();
    await first.resetConversation();

    expect(fakePlatform.generateContentSessionIds, hasLength(2));
    expect(
      fakePlatform.generateContentSessionIds.toSet(),
      hasLength(2),
      reason: 'instances must not share a session id',
    );
    expect(fakePlatform.resetConversationSessionIds, [
      fakePlatform.generateContentSessionIds.first,
    ]);
  });

  test('generateContent passes the instance tools to the platform', () async {
    final tool = EdgeGenAITool(
      name: 'get_weather',
      description: 'Gets the weather.',
      parameters: [
        EdgeGenAIToolParameter(name: 'city', description: 'The city.'),
      ],
      onCall: (_) async => 'sunny',
    );

    await EdgeGenAIPrompt(
      tools: [tool],
    ).generateContent('a prompt').drain<void>();

    expect(fakePlatform.generateContentTools.single.single.name, 'get_weather');
  });

  test('EdgeGenAITool builds a full JSON Schema for its arguments', () {
    final tool = EdgeGenAITool(
      name: 'create_reminders',
      description: 'Creates reminders.',
      parameters: [
        EdgeGenAIToolParameter(
          name: 'reminders',
          description: 'The reminders to create.',
          schema: EdgeGenAIToolSchema.array(
            minItems: 1,
            items: EdgeGenAIToolSchema.object(
              properties: {
                'title': EdgeGenAIToolSchema.string(
                  description: 'The reminder title.',
                ),
                'priority': EdgeGenAIToolSchema.string(
                  enumValues: ['low', 'medium', 'high'],
                ),
                'minutesFromNow': EdgeGenAIToolSchema.integer(minimum: 1),
              },
              optionalProperties: ['priority'],
            ),
          ),
        ),
        EdgeGenAIToolParameter(
          name: 'note',
          description: 'An optional note.',
          isRequired: false,
        ),
      ],
      onCall: (_) async => 'done',
    );

    expect(tool.argumentsJsonSchema(), {
      'type': 'object',
      'properties': {
        'reminders': {
          'type': 'array',
          'minItems': 1,
          'items': {
            'type': 'object',
            'properties': {
              'title': {'type': 'string', 'description': 'The reminder title.'},
              'priority': {
                'type': 'string',
                'enum': ['low', 'medium', 'high'],
              },
              'minutesFromNow': {'type': 'integer', 'minimum': 1},
            },
            'required': ['title', 'minutesFromNow'],
          },
          'description': 'The reminders to create.',
        },
        'note': {'type': 'string', 'description': 'An optional note.'},
      },
      'required': ['reminders'],
    });
  });

  test('summarize', () async {
    expect(await EdgeGenAISummarizer().summarize('a text'), 'a summary');
  });

  test('proofread', () async {
    expect(
      await EdgeGenAIProofreader().proofread('a text'),
      'a corrected text',
    );
  });

  test('rewrite', () async {
    expect(
      await EdgeGenAIRewriter().rewrite(
        'a text',
        style: EdgeGenAIRewriteStyle.professional,
      ),
      'a rewritten text',
    );
  });

  test('describeImage', () async {
    expect(
      await EdgeGenAIImageDescriber().describeImage(Uint8List.fromList([1])),
      'an image description',
    );
  });
}
