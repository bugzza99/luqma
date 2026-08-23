import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';

/// What needs attention today.
///
/// Deliberately empty of decoration: this is the screen the owner opens to find out
/// whether anything is wrong, so anything on it that is not a problem is in the way.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const LuqmaLockup.appBar()),
      body: AdminContent(
        child: ListView(
          padding: const EdgeInsets.all(Space.gutter),
          children: [
            Text('النهارده', style: theme.textTheme.headlineMedium),
            const SizedBox(height: Space.lg),
            Text(
              'لوحة اليوم بتتملى مع أول طلبات.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.luqma.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
