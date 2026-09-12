import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';
import 'customer_detail_screen.dart';

/// Customers, as AdminApp supports and moderates them.
///
/// Search by name or phone, view customer detail with verification facts and order history,
/// and block or unblock.
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
  CustomerSummary? _selectedCustomer;

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
          // Keep selected customer fresh if still in search results
          if (_selectedCustomer != null) {
            final fresh = value.where((c) => c.id == _selectedCustomer!.id).firstOrNull;
            if (fresh != null) {
              _selectedCustomer = fresh;
            }
          }
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
      await _search(_query.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final layout = AdminLayout.of(context);

    // On narrow screens (phone), the customer detail replaces the search list
    // so controls have full touch targets.
    if (!layout.showsTwoPanes && _selectedCustomer != null) {
      return CustomerDetailScreen(
        customer: _selectedCustomer!,
        onBack: () => setState(() => _selectedCustomer = null),
        onCustomerUpdated: () => _search(_query.text),
      );
    }

    final searchAndList = AdminContent(
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
    );

    if (layout.showsTwoPanes) {
      return Scaffold(
        appBar: AppBar(title: const Text('العملاء')),
        body: Row(
          children: [
            Expanded(flex: 2, child: searchAndList),
            VerticalDivider(width: 1, color: colors.hairline),
            Expanded(
              flex: 3,
              child: _selectedCustomer == null
                  ? Center(
                      child: Text(
                        strings.customerNothingSelected,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    )
                  : CustomerDetailScreen(
                      customer: _selectedCustomer!,
                      onCustomerUpdated: () => _search(_query.text),
                    ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('العملاء')),
      body: searchAndList,
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
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
      );
    }
    if (results.isEmpty) {
      return Center(
        child: Text(
          'مفيش نتايج.',
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
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
        onTap: () => setState(() => _selectedCustomer = results[i]),
        onToggleBlock: () => _toggleBlock(results[i]),
        onResetPassword: () => setState(() => _selectedCustomer = results[i]),
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
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            IconButton(
              key: CustomersScreen.resetKey,
              tooltip: 'تفاصيل وإعادة تعيين كلمة السر',
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
