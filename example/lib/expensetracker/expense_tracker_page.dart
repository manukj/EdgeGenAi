import 'dart:async';
import 'dart:convert';

import 'package:edge_gen_ai/edge_gen_ai.dart';
import 'package:flutter/material.dart';

class ExpenseTrackerPage extends StatefulWidget {
  const ExpenseTrackerPage({super.key});

  @override
  State<ExpenseTrackerPage> createState() => _ExpenseTrackerPageState();
}

class _Expense {
  _Expense(this.pence, this.category, this.note) : date = DateTime.now();

  final int pence;
  final String category;
  final String note;
  final DateTime date;
}

class _ExpenseTrackerPageState extends State<ExpenseTrackerPage> {
  static const _categories = [
    'food',
    'transport',
    'shopping',
    'bills',
    'other',
  ];
  final _controller = TextEditingController();
  final _expenses = <_Expense>[];
  final _tools = <({String name, String arguments})>[];
  bool _busy = false;
  bool _loading = true;
  EdgeGenAIAvailability? _availability;
  String? _status;

  late final _prompt = EdgeGenAIPrompt(
    tools: [
      EdgeGenAITool(
        name: 'add_expense',
        description: 'Records one expense in pounds sterling (GBP).',
        parameters: [
          EdgeGenAIToolParameter(
            name: 'amount',
            description:
                'The positive expense amount in pounds, for example 12.50.',
            schema: EdgeGenAIToolSchema.number(minimum: 0.01),
          ),
          EdgeGenAIToolParameter(
            name: 'category',
            description: 'The expense category; use other when unsure.',
            schema: EdgeGenAIToolSchema.string(enumValues: _categories),
          ),
          EdgeGenAIToolParameter(
            name: 'note',
            description: 'A short description of the expense.',
          ),
        ],
        onCall: _addExpense,
      ),
      EdgeGenAITool(
        name: 'get_spending_summary',
        description:
            'Gets today’s recorded spending total and totals by category.',
        onCall: _getSummary,
      ),
    ],
  );

  static String _money(int pence) => '£${(pence / 100).toStringAsFixed(2)}';

  List<_Expense> get _today {
    final now = DateTime.now();
    return _expenses
        .where(
          (expense) =>
              expense.date.year == now.year &&
              expense.date.month == now.month &&
              expense.date.day == now.day,
        )
        .toList();
  }

  int get _total => _today.fold(0, (total, expense) => total + expense.pence);

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  @override
  void dispose() {
    unawaited(_prompt.stop().catchError((Object _) {}));
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkAvailability() async {
    try {
      final availability = await _prompt.checkAvailability();
      if (!mounted) return;
      setState(() {
        _availability = availability;
        _loading = false;
        _status = availability == EdgeGenAIAvailability.unavailable
            ? 'On-device AI is unavailable on this device.'
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'Could not check AI availability: $error';
      });
    }
  }

  Future<void> _download() async {
    setState(() {
      _loading = true;
      _status = 'Downloading the on-device model…';
    });
    try {
      await for (final _ in _prompt.downloadModel()) {
        if (!mounted) return;
      }
      await _checkAvailability();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'Download failed: $error';
      });
    }
  }

  void _recordTool(String name, Map<String, Object?> arguments) {
    if (!mounted || !_busy) {
      throw StateError('This request is no longer active.');
    }
    setState(() => _tools.add((name: name, arguments: jsonEncode(arguments))));
  }

  Future<String> _addExpense(Map<String, Object?> arguments) async {
    _recordTool('add_expense', arguments);
    final amount = arguments['amount'];
    final category = arguments['category'];
    final note = arguments['note'];
    if (amount is! num ||
        !amount.isFinite ||
        amount < 0.01 ||
        !_categories.contains(category) ||
        note is! String ||
        note.trim().isEmpty) {
      throw ArgumentError(
        'Provide a positive amount, a valid category, and a description.',
      );
    }
    final expense = _Expense(
      (amount * 100).round(),
      category as String,
      note.trim(),
    );
    setState(() => _expenses.insert(0, expense));
    return 'Added ${_money(expense.pence)} for ${expense.note}. Today’s total: ${_money(_total)}.';
  }

  Future<String> _getSummary(Map<String, Object?> arguments) async {
    _recordTool('get_spending_summary', arguments);
    if (_today.isEmpty) return 'No expenses recorded today.';
    final categories = <String, int>{};
    for (final expense in _today) {
      categories.update(
        expense.category,
        (value) => value + expense.pence,
        ifAbsent: () => expense.pence,
      );
    }
    final breakdown = categories.entries
        .map((entry) => '${entry.key}: ${_money(entry.value)}')
        .join(' · ');
    final count = _today.length;
    return 'Today’s spending: ${_money(_total)} across $count ${count == 1 ? 'expense' : 'expenses'}.\n$breakdown';
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (_busy ||
        text.isEmpty ||
        _availability != EdgeGenAIAvailability.available) {
      return;
    }
    setState(() {
      _busy = true;
      _tools.clear();
      _controller.clear();
    });
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await for (final response in _prompt.generateContent(text)) {
        if (!mounted) return;
        if (response.startsWith('The tool failed with an error:')) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(response)));
        }
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not complete the request: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Expense Tracker')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  CustomPaint(
                    painter: _DottedBorder(theme.colorScheme.outlineVariant),
                    child: SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Today’s spending',
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _money(_total),
                              style: theme.textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_loading) const LinearProgressIndicator(),
                  if (_status != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_status!),
                    ),
                  if (!_loading &&
                      _availability == EdgeGenAIAvailability.downloadable)
                    OutlinedButton(
                      onPressed: _download,
                      child: const Text('Download model'),
                    ),
                  const SizedBox(height: 24),
                  Text('Expenses', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_expenses.isEmpty) const Text('No expenses yet.'),
                  for (final expense in _expenses)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(expense.note),
                      subtitle: Text(expense.category),
                      trailing: Text(
                        _money(expense.pence),
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_tools.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final tool in _tools)
                        Tooltip(
                          message: tool.arguments,
                          child: Chip(
                            avatar: const Icon(Icons.build_outlined, size: 16),
                            label: Text(tool.name),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_busy,
                      textInputAction: TextInputAction.send,
                      decoration: const InputDecoration(
                        hintText: 'Add an expense or ask for a total',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send',
                    icon: const Icon(Icons.arrow_upward),
                    onPressed:
                        _busy ||
                            _loading ||
                            _availability != EdgeGenAIAvailability.available
                        ? null
                        : _send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DottedBorder extends CustomPainter {
  const _DottedBorder(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final border = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1),
          const Radius.circular(16),
        ),
      );
    final paint = Paint()..color = color;
    for (final metric in border.computeMetrics()) {
      for (double offset = 0; offset < metric.length; offset += 6) {
        final tangent = metric.getTangentForOffset(offset);
        if (tangent != null) canvas.drawCircle(tangent.position, 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DottedBorder oldDelegate) => color != oldDelegate.color;
}
