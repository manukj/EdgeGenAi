import 'package:edge_ai_example/function_calling_page.dart';
import 'package:edge_ai_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the feature tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Function calling'), findsOneWidget);
    expect(find.text('Summarize'), findsOneWidget);
    expect(find.text('Proofread'), findsOneWidget);
    expect(find.text('Rewrite'), findsOneWidget);
    expect(find.text('Describe image'), findsOneWidget);
  });

  testWidgets('function hint pre-fills its prompt', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FunctionCallingPage(
            onThemeChanged: ({required mode, required color}) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('set_theme'));

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Use dark mode with a red accent.',
    );
  });
}
