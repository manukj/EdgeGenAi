import 'dart:typed_data';

import 'package:edge_ai_example/examples_page.dart';
import 'package:edge_ai_example/expensetracker/expense_tracker_page.dart';
import 'package:edge_gen_ai/edge_gen_ai.dart';
import 'package:edge_gen_ai/edge_gen_ai_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ExpensePlatform extends EdgeGenAIPlatform {
  @override
  Future<EdgeGenAIAvailability> checkAvailability(
    EdgeGenAIFeature feature,
  ) async => EdgeGenAIAvailability.available;

  @override
  Future<void> stopGeneration(String sessionId) async {}

  @override
  Stream<String> generateContent(
    String sessionId,
    String prompt, {
    EdgeGenAIGenerationOptions? options,
    bool useMemory = false,
    Uint8List? image,
    List<EdgeGenAITool> tools = const [],
  }) async* {
    final summary = prompt.contains('spent');
    final tool = tools.singleWhere(
      (tool) => tool.name == (summary ? 'get_spending_summary' : 'add_expense'),
    );
    yield await tool.onCall(
      summary ? {} : {'amount': 12.50, 'category': 'food', 'note': 'Lunch'},
    );
  }
}

void main() {
  late EdgeGenAIPlatform previousPlatform;
  setUp(() {
    previousPlatform = EdgeGenAIPlatform.instance;
    EdgeGenAIPlatform.instance = _ExpensePlatform();
  });
  tearDown(() => EdgeGenAIPlatform.instance = previousPlatform);

  testWidgets('example button opens the tracker', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ExamplesPage())),
    );
    await tester.tap(find.text('Expense Tracker'));
    await tester.pumpAndSettle();
    expect(find.byType(ExpenseTrackerPage), findsOneWidget);
    expect(find.text('£0.00'), findsOneWidget);
  });

  testWidgets(
    'tool callbacks update expenses and show only the latest tool above the input',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ExpenseTrackerPage()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Add £12.50 for lunch');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Chip, 'add_expense'), findsOneWidget);
      expect(find.text('Add £12.50 for lunch'), findsNothing);
      expect(
        tester.getBottomLeft(find.byType(Chip)).dy,
        lessThan(tester.getTopLeft(find.byType(TextField)).dy),
      );
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('£12.50'), findsNWidgets(2));
      expect(
        find.text('Added £12.50 for Lunch. Today’s total: £12.50.'),
        findsNothing,
      );

      await tester.enterText(
        find.byType(TextField),
        'How much have I spent today?',
      );
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(Chip, 'get_spending_summary'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'add_expense'), findsNothing);
      expect(
        find.text('Added £12.50 for Lunch. Today’s total: £12.50.'),
        findsNothing,
      );
      expect(
        find.text('Today’s spending: £12.50 across 1 expense.\nfood: £12.50'),
        findsNothing,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Lunch'), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Lunch'),
          matching: find.text('£12.50'),
        ),
        findsOneWidget,
      );
    },
  );
}
