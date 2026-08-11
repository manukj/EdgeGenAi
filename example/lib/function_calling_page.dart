import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:edge_gen_ai/edge_gen_ai.dart';
import 'package:flutter/material.dart';

/// Demonstrates theme-changing tools with no, optional, and explicit arguments.
class FunctionCallingPage extends StatefulWidget {
  const FunctionCallingPage({super.key, required this.onThemeChanged});

  final void Function({required ThemeMode mode, required Color color})
  onThemeChanged;

  @override
  State<FunctionCallingPage> createState() => _FunctionCallingPageState();
}

class _FunctionCallingPageState extends State<FunctionCallingPage>
    with AutomaticKeepAliveClientMixin {
  static const _examples = <({String name, String prompt})>[
    (name: 'toggle_theme', prompt: 'Toggle the app theme.'),
    (name: 'set_theme', prompt: 'Use dark mode with a red accent.'),
    (name: 'get_current_time', prompt: 'What time is it?'),
    (name: 'get_current_date', prompt: 'What is today\'s date?'),
    (name: 'get_weekday', prompt: 'What day of the week is it?'),
    (name: 'get_greeting', prompt: 'Greet Alex.'),
    (name: 'calculate_sum', prompt: 'Add 12 and 30.'),
    (
      name: 'convert_celsius_to_fahrenheit',
      prompt: 'Convert 24 degrees Celsius to Fahrenheit.',
    ),
    (name: 'roll_dice', prompt: 'Roll a 12-sided die.'),
    (name: 'flip_coin', prompt: 'Flip a coin.'),
    (name: 'get_random_number', prompt: 'Give me a random number up to 50.'),
    (name: 'reverse_text', prompt: 'Reverse the text Flutter.'),
    (name: 'count_words', prompt: 'Count the words in: Edge AI is local.'),
    (name: 'format_name', prompt: 'Format the name ada lovelace.'),
    (name: 'get_battery_level', prompt: 'What is the battery level?'),
  ];

  late final EdgeGenAIPrompt _prompt = EdgeGenAIPrompt(
    tools: [
      EdgeGenAITool(
        name: 'toggle_theme',
        description: 'Toggles between the light and dark app themes.',
        onCall: _toggleTheme,
      ),
      EdgeGenAITool(
        name: 'set_theme',
        description: 'Sets the app theme.',
        parameters: [
          EdgeGenAIToolParameter(
            name: 'darkMode',
            description: 'Whether the app should use dark mode.',
            type: EdgeGenAIToolParameterType.boolean,
            isRequired: false,
          ),
          EdgeGenAIToolParameter(
            name: 'accentColor',
            description:
                'The requested accent color as a six-digit hexadecimal value '
                'in #RRGGBB format.',
          ),
        ],
        onCall: _setTheme,
      ),
      EdgeGenAITool(
        name: 'get_current_time',
        description: 'Gets the current local time.',
        onCall: _getCurrentTime,
      ),
      EdgeGenAITool(
        name: 'get_current_date',
        description: 'Gets today\'s local date.',
        onCall: _getCurrentDate,
      ),
      EdgeGenAITool(
        name: 'get_weekday',
        description: 'Gets the current day of the week.',
        onCall: _getWeekday,
      ),
      EdgeGenAITool(
        name: 'get_greeting',
        description: 'Creates a short greeting for a person.',
        parameters: [
          EdgeGenAIToolParameter(
            name: 'name',
            description: 'The person to greet.',
            isRequired: false,
          ),
        ],
        onCall: _getGreeting,
      ),
      EdgeGenAITool(
        name: 'calculate_sum',
        description: 'Adds two numbers.',
        parameters: [
          EdgeGenAIToolParameter(
            name: 'firstNumber',
            description: 'The first number.',
            type: EdgeGenAIToolParameterType.number,
          ),
          EdgeGenAIToolParameter(
            name: 'secondNumber',
            description: 'The second number.',
            type: EdgeGenAIToolParameterType.number,
          ),
        ],
        onCall: _calculateSum,
      ),
      EdgeGenAITool(
        name: 'convert_celsius_to_fahrenheit',
        description: 'Converts a Celsius temperature to Fahrenheit.',
        parameters: [
          EdgeGenAIToolParameter(
            name: 'celsius',
            description: 'The temperature in degrees Celsius.',
            type: EdgeGenAIToolParameterType.number,
          ),
        ],
        onCall: _convertCelsiusToFahrenheit,
      ),
      EdgeGenAITool(
        name: 'roll_dice',
        description: 'Rolls a die with the requested number of sides.',
        parameters: [
          EdgeGenAIToolParameter(
            name: 'sides',
            description: 'The number of sides, from 2 to 20.',
            type: EdgeGenAIToolParameterType.integer,
            isRequired: false,
          ),
        ],
        onCall: _rollDice,
      ),
      EdgeGenAITool(
        name: 'flip_coin',
        description: 'Flips a coin and returns heads or tails.',
        onCall: _flipCoin,
      ),
      EdgeGenAITool(
        name: 'get_random_number',
        description: 'Gets a random whole number up to a maximum.',
        parameters: [
          EdgeGenAIToolParameter(
            name: 'maximum',
            description: 'The maximum value, from 1 to 100.',
            type: EdgeGenAIToolParameterType.integer,
            isRequired: false,
          ),
        ],
        onCall: _getRandomNumber,
      ),
      EdgeGenAITool(
        name: 'reverse_text',
        description: 'Reverses the characters in text.',
        parameters: [
          EdgeGenAIToolParameter(
            name: 'text',
            description: 'The text to reverse.',
          ),
        ],
        onCall: _reverseText,
      ),
      EdgeGenAITool(
        name: 'count_words',
        description: 'Counts the words in text.',
        parameters: [
          EdgeGenAIToolParameter(
            name: 'text',
            description: 'The text whose words should be counted.',
          ),
        ],
        onCall: _countWords,
      ),
      EdgeGenAITool(
        name: 'format_name',
        description: 'Formats a first and last name with capital letters.',
        parameters: [
          EdgeGenAIToolParameter(
            name: 'firstName',
            description: 'The first name.',
          ),
          EdgeGenAIToolParameter(
            name: 'lastName',
            description: 'The last name.',
            isRequired: false,
          ),
        ],
        onCall: _formatName,
      ),
      EdgeGenAITool(
        name: 'get_battery_level',
        description: 'Gets the device battery level as a percentage.',
        onCall: _getBatteryLevel,
      ),
    ],
  );
  final _controller = TextEditingController();
  String? _result;
  bool _isGenerating = false;
  ThemeMode _themeMode = ThemeMode.light;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<String> _toggleTheme(Map<String, Object?> _) async {
    _themeMode = _themeMode == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;
    widget.onThemeChanged(mode: _themeMode, color: Colors.indigo);
    return 'Theme changed to ${_themeMode.name} indigo.';
  }

  Future<String> _setTheme(Map<String, Object?> arguments) async {
    final isDark = arguments['darkMode'] as bool? ?? false;
    final accentColor = arguments['accentColor'];
    if (accentColor is! String) {
      throw ArgumentError.value(
        accentColor,
        'accentColor',
        'A #RRGGBB color is required.',
      );
    }
    final hexColor = accentColor.replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hexColor)) {
      throw ArgumentError.value(
        accentColor,
        'accentColor',
        'Expected a six-digit #RRGGBB color.',
      );
    }
    final color = Color(0xFF000000 | int.parse(hexColor, radix: 16));
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    widget.onThemeChanged(mode: _themeMode, color: color);
    return 'Theme changed to ${_themeMode.name} #${hexColor.toUpperCase()}.';
  }

  Future<String> _getCurrentTime(Map<String, Object?> _) async {
    final now = DateTime.now();
    return 'The local time is ${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}.';
  }

  Future<String> _getCurrentDate(Map<String, Object?> _) async {
    final now = DateTime.now();
    return 'Today is ${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}.';
  }

  Future<String> _getWeekday(Map<String, Object?> _) async {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return 'Today is ${weekdays[DateTime.now().weekday - 1]}.';
  }

  Future<String> _getGreeting(Map<String, Object?> arguments) async {
    final name = arguments['name'] as String? ?? 'there';
    return 'Hello, $name!';
  }

  Future<String> _calculateSum(Map<String, Object?> arguments) async {
    final firstNumber = arguments['firstNumber'] as num? ?? 0;
    final secondNumber = arguments['secondNumber'] as num? ?? 0;
    return '$firstNumber + $secondNumber = ${firstNumber + secondNumber}.';
  }

  Future<String> _convertCelsiusToFahrenheit(
    Map<String, Object?> arguments,
  ) async {
    final celsius = arguments['celsius'] as num? ?? 0;
    final fahrenheit = celsius * 9 / 5 + 32;
    return '$celsius°C is $fahrenheit°F.';
  }

  Future<String> _rollDice(Map<String, Object?> arguments) async {
    final sides = ((arguments['sides'] as num?)?.toInt() ?? 6)
        .clamp(2, 20)
        .toInt();
    return 'Rolled ${Random().nextInt(sides) + 1} on a $sides-sided die.';
  }

  Future<String> _flipCoin(Map<String, Object?> _) async =>
      Random().nextBool() ? 'Heads.' : 'Tails.';

  Future<String> _getRandomNumber(Map<String, Object?> arguments) async {
    final maximum = ((arguments['maximum'] as num?)?.toInt() ?? 100)
        .clamp(1, 100)
        .toInt();
    return 'Random number: ${Random().nextInt(maximum) + 1}.';
  }

  Future<String> _reverseText(Map<String, Object?> arguments) async {
    final text = arguments['text'] as String? ?? '';
    return text.split('').reversed.join();
  }

  Future<String> _countWords(Map<String, Object?> arguments) async {
    final text = arguments['text'] as String? ?? '';
    return 'Word count: ${RegExp(r'\S+').allMatches(text).length}.';
  }

  Future<String> _formatName(Map<String, Object?> arguments) async {
    final firstName = arguments['firstName'] as String? ?? '';
    final lastName = arguments['lastName'] as String? ?? '';
    return [firstName, lastName]
        .where((name) => name.isNotEmpty)
        .map(
          (name) =>
              '${name[0].toUpperCase()}${name.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  Future<String> _getBatteryLevel(Map<String, Object?> _) async {
    final batteryLevel = await Battery().batteryLevel;
    return 'Battery level: $batteryLevel%.';
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
    _prompt
        .generateContent(prompt)
        .listen(
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
            'Choose a function, then ask the model to run it.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final example in _examples)
                ActionChip(
                  label: Text(example.name),
                  onPressed: () => _useExample(example.prompt),
                ),
            ],
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
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: const Text('Run example'),
          ),
          const SizedBox(height: 16),
          if (_result != null)
            Card(
              margin: EdgeInsets.zero,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_result!),
              ),
            ),
        ],
      ),
    );
  }
}
