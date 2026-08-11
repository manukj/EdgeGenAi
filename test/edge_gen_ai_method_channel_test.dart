import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:edge_gen_ai/edge_gen_ai_method_channel.dart';
import 'package:edge_gen_ai/edge_gen_ai_tool.dart';
import 'package:edge_gen_ai/src/messages.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  MethodChannelEdgeGenAI platform = MethodChannelEdgeGenAI();

  void mockChannel(String method, Object? response) {
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.edge_gen_ai.EdgeGenAIHostApi.$method',
      (ByteData? message) async {
        return EdgeGenAIHostApi.pigeonChannelCodec.encodeMessage(<Object?>[
          response,
        ]);
      },
    );
  }

  void unmockChannel(String method) {
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.edge_gen_ai.EdgeGenAIHostApi.$method',
      null,
    );
  }

  test('checkAvailability', () async {
    mockChannel('checkAvailability', EdgeGenAIAvailability.available);

    expect(
      await platform.checkAvailability(EdgeGenAIFeature.prompt),
      EdgeGenAIAvailability.available,
    );

    unmockChannel('checkAvailability');
  });

  test('downloadModel listens to the feature-specific channel', () async {
    const channelName =
        'dev.flutter.pigeon.edge_gen_ai.EdgeGenAIEventApi.summarizationDownloadProgress';
    final progress = EdgeGenAIDownloadProgress(
      status: EdgeGenAIDownloadStatus.completed,
    );

    messenger.setMockMessageHandler(channelName, (ByteData? message) async {
      final call = pigeonMethodCodec.decodeMethodCall(message);
      if (call.method == 'listen') {
        final envelope = pigeonMethodCodec.encodeSuccessEnvelope(progress);
        await messenger.handlePlatformMessage(channelName, envelope, (_) {});
      }
      return null;
    });

    await expectLater(
      platform.downloadModel(EdgeGenAIFeature.summarization),
      emits(progress),
    );

    messenger.setMockMessageHandler(channelName, null);
  });

  test('generateContent', () async {
    const hostChannel =
        'dev.flutter.pigeon.edge_gen_ai.EdgeGenAIHostApi.startGenerateContent';
    const eventChannel =
        'dev.flutter.pigeon.edge_gen_ai.EdgeGenAIEventApi.generateContentChunk';

    messenger.setMockMessageHandler(hostChannel, (ByteData? message) async {
      return EdgeGenAIHostApi.pigeonChannelCodec.encodeMessage(<Object?>[null]);
    });
    messenger.setMockMessageHandler(eventChannel, (ByteData? message) async {
      final call = pigeonMethodCodec.decodeMethodCall(message);
      if (call.method == 'listen') {
        final envelope = pigeonMethodCodec.encodeSuccessEnvelope(
          'a generated response',
        );
        await messenger.handlePlatformMessage(eventChannel, envelope, (_) {});
      }
      return null;
    });

    await expectLater(
      platform.generateContent('a-session-id', 'a prompt'),
      emits('a generated response'),
    );

    messenger.setMockMessageHandler(hostChannel, null);
    messenger.setMockMessageHandler(eventChannel, null);
  });

  test('a platform tool call runs the registered Dart executor', () async {
    const hostChannel =
        'dev.flutter.pigeon.edge_gen_ai.EdgeGenAIHostApi.startGenerateContent';
    const eventChannel =
        'dev.flutter.pigeon.edge_gen_ai.EdgeGenAIEventApi.generateContentChunk';
    const toolChannel =
        'dev.flutter.pigeon.edge_gen_ai.EdgeGenAIToolExecutorApi.callTool';

    Map<String, Object?>? receivedArguments;
    final tool = EdgeGenAITool(
      name: 'get_weather',
      description: 'Gets the weather.',
      parameters: [
        EdgeGenAIToolParameter(name: 'city', description: 'The city.'),
      ],
      onCall: (arguments) async {
        receivedArguments = arguments;
        return 'sunny';
      },
    );

    List<Object?>? sentToolDefinitions;
    messenger.setMockMessageHandler(hostChannel, (ByteData? message) async {
      final args =
          EdgeGenAIHostApi.pigeonChannelCodec.decodeMessage(message)
              as List<Object?>;
      sentToolDefinitions = args[5] as List<Object?>?;
      return EdgeGenAIHostApi.pigeonChannelCodec.encodeMessage(<Object?>[null]);
    });
    messenger.setMockMessageHandler(eventChannel, (ByteData? message) async {
      final call = pigeonMethodCodec.decodeMethodCall(message);
      if (call.method == 'listen') {
        final envelope = pigeonMethodCodec.encodeSuccessEnvelope('an answer');
        await messenger.handlePlatformMessage(eventChannel, envelope, (_) {});
        // A null message closes the event stream.
        await messenger.handlePlatformMessage(eventChannel, null, (_) {});
      }
      return null;
    });

    await platform
        .generateContent('a-session-id', 'a prompt', tools: [tool])
        .drain<void>();

    // The tool's schema crossed to the platform side...
    final definition = sentToolDefinitions!.single as EdgeGenAIToolDefinition;
    expect(definition.name, 'get_weather');
    expect(jsonDecode(definition.parametersSchemaJson), {
      'type': 'object',
      'properties': {
        'city': {'type': 'string', 'description': 'The city.'},
      },
      'required': ['city'],
    });

    // ...and a platform-side tool call reaches the Dart executor.
    final replyCompleter = Completer<ByteData?>();
    await messenger.handlePlatformMessage(
      toolChannel,
      EdgeGenAIToolExecutorApi.pigeonChannelCodec.encodeMessage(<Object?>[
        'a-session-id',
        'get_weather',
        '{"city": "Oslo"}',
      ]),
      replyCompleter.complete,
    );
    final reply = await replyCompleter.future;
    final decodedReply =
        EdgeGenAIToolExecutorApi.pigeonChannelCodec.decodeMessage(reply)
            as List<Object?>;

    expect(decodedReply, ['sunny']);
    expect(receivedArguments, {'city': 'Oslo'});

    messenger.setMockMessageHandler(hostChannel, null);
    messenger.setMockMessageHandler(eventChannel, null);
  });

  test('summarize', () async {
    mockChannel('summarize', 'a summary');

    expect(await platform.summarize('a text'), 'a summary');

    unmockChannel('summarize');
  });

  test('proofread', () async {
    mockChannel('proofread', 'a corrected text');

    expect(await platform.proofread('a text'), 'a corrected text');

    unmockChannel('proofread');
  });

  test('rewrite', () async {
    mockChannel('rewrite', 'a rewritten text');

    expect(
      await platform.rewrite('a text', style: EdgeGenAIRewriteStyle.friendly),
      'a rewritten text',
    );

    unmockChannel('rewrite');
  });

  test('describeImage', () async {
    mockChannel('describeImage', 'an image description');

    expect(
      await platform.describeImage(Uint8List.fromList([1, 2, 3])),
      'an image description',
    );

    unmockChannel('describeImage');
  });
}
