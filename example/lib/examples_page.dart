import 'package:flutter/material.dart';

import 'expensetracker/expense_tracker_page.dart';

class ExamplesPage extends StatelessWidget {
  const ExamplesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined, size: 40),
            const SizedBox(height: 16),
            Text(
              'AI in everyday apps',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Turn a message into an action.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Expense Tracker'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ExpenseTrackerPage(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
