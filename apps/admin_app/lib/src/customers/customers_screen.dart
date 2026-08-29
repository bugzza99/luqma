import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';

/// Customers, as AdminApp supports and moderates them.
///
/// Search by name or phone, see a customer's orders, and block or unblock. Blocking is
/// the one write here, and it goes through `admin_set_customer_blocked` — a flag that
/// decides who may sign in must not be editable by whoever holds the client.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  static const searchKey = Key('customers.search');
  static const rowKey = Key('customers.row');
  static const blockKey = Key('customers.block');
  static const resetKey = Key('customers.reset');
  static const confirmResetKey = Key('customers.confirmReset');

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _query = TextEditingController();

  List<CustomerSummary>? _results;
  Failure? _failure;
  bool _loading = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _failure = null;
    });

    final result = await ref.read(customerRepositoryProvider).search(query);
    if (!mounted) return;

    setState(() {
      _loading = false;
      switch (result) {
        case Ok(:final value):
          _results = value;
        case Err(:final failure):
          _failure = failure;
          _results = null;
      }
    });
  }

  Future<void> _toggleBlock(CustomerSummary customer) async {
    final result = await ref.read(customerRepositoryProvider).setBlocked(
          customer.id,
          blocked: !customer.isBlocked,
        );
    if (!mounted) return;

    if (result is Ok) {
      // Re-run the same search so the list reflects the new flag.
      await _search(_query.text);
    }
  }

  /// Gives a customer a new password, and shows it once.
  ///
  /// Asked first, because the old password stops working the moment this runs — doing it
  /// to the wrong row on a mistyped tap locks somebody out of their own account.
  Future<void> _resetPassword(CustomerSummary customer) async {
    final name = customer.name.isEmpty ? 'العميل' : customer.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('كلمة سر جديدة؟'),
        content: Text(
          'هيتعمل لـ$name كلمة سر جديدة، والقديمة هتبطّل تشتغل على طول. '
          'اقراها له في التليفون.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('لا'),
          ),
          FilledButton(
            key: CustomersScreen.confirmResetKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('اعملها'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;

    final result =
        await ref.read(customerRepositoryProvider).resetPassword(customer.id);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(result is Ok ? 'كلمة السر الجديدة' : 'مقدرناش'),
        content: switch (result) {
          // Selectable, and in one big line: this is read down a phone line, and it is
          // the only time anybody can see it.
          Ok(:final value) => SelectableText(
              value,
              textDirection: TextDirection.ltr,
              style: Theme.of(dialogContext).textTheme.headlineSmall,
            ),
          Err(failure: ConflictFailure()) =>
            const Text('ده حساب موظف مش عميل — غيّرها من شاشة الموظفين.'),
          Err() => const Text('حاول تاني.'),
        },
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('تمام'),
          ),
        ],
      ),
    );
  }

  Future<void> _showHistory(CustomerSummary customer) async {
    final result =
        await ref.read(customerRepositoryProvider).history(customer.id);
    if (!mounted) return;

    final orders = result.valueOrNull ?? const <Order>[];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(customer.name.isEmpty ? 'عميل' : customer.name),
        content: SizedBox(
          width: double.maxFinite,
          child: orders.isEmpty
              ? const Text('مفيش طلبات لسه.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: orders.length,
                  itemBuilder: (_, i) {
                    final order = orders[i];
                    return ListTile(
                      title: Text('أوردر #${order.orderNumber}'),
                      subtitle: Text(
                        '${LuqmaStrings.of(dialogContext).price(order.pricing.total)} — ${order.status.name}',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('قفل'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Scaffold(
      appBar: AppBar(title: const Text('العملاء')),
      body: AdminContent(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Space.gutter),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: CustomersScreen.searchKey,
                      controller: _query,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        labelText: 'ابحث بالاسم أو الرقم',
                        hintText: '01012345678',
                      ),
                      onSubmitted: _search,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  FilledButton(
                    onPressed: _loading ? null : () => _search(_query.text),
                    child: Text(_loading ? 'جاري…' : 'ابحث'),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildResults(theme, colors)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ThemeData theme, LuqmaColors colors) {
    if (_failure != null) {
      return LuqmaErrorView(
        failure: _failure!,
        onRetry: () => _search(_query.text),
      );
    }

    final results = _results;
    if (results == null) {
      return Center(
        child: Text(
          'دور على عميل بالاسم أو رقم الموبايل.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: colors.textSecondary),
        ),
      );
    }
    if (results.isEmpty) {
      return Center(
        child: Text(
          'مفيش نتايج.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: colors.textSecondary),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        0,
        Space.gutter,
        Space.xxxl,
      ),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
      itemBuilder: (context, i) => _CustomerRow(
        customer: results[i],
        onTap: () => _showHistory(results[i]),
        onToggleBlock: () => _toggleBlock(results[i]),
        onResetPassword: () => _resetPassword(results[i]),
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.customer,
    required this.onTap,
    required this.onToggleBlock,
    required this.onResetPassword,
  });

  final CustomerSummary customer;
  final VoidCallback onTap;
  final VoidCallback onToggleBlock;
  final VoidCallback onResetPassword;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return InkWell(
      onTap: onTap,
      borderRadius: Radii.cardAll,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        constraints: const BoxConstraints(minHeight: Sizes.minTarget),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: Radii.cardAll,
          border: Border.all(color: colors.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name.isEmpty ? 'عميل' : customer.name,
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    customer.phone.isEmpty ? 'من غير رقم' : customer.phone,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            IconButton(
              key: CustomersScreen.resetKey,
              tooltip: 'كلمة سر جديدة',
              icon: Icon(Icons.key_outlined, color: colors.textSecondary),
              onPressed: onResetPassword,
            ),
            IconButton(
              key: CustomersScreen.blockKey,
              tooltip: customer.isBlocked ? 'فك الحظر' : 'حظر',
              icon: Icon(
                customer.isBlocked ? Icons.lock_open_rounded : Icons.block,
                color: customer.isBlocked ? colors.brand : colors.danger,
              ),
              onPressed: onToggleBlock,
            ),
          ],
        ),
      ),
    );
  }
}
