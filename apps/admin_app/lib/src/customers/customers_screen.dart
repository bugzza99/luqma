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
        onDeleted: () {
          setState(() => _selectedCustomer = null);
          _search(_query.text);
        },
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
                      prefixIcon: Icon(Icons.search),
                      labelText: 'ابحث بالاسم أو الرقم',
                      hintText: '01012345678',
                    ),
                    onSubmitted: _search,
                  ),
                ),
                const SizedBox(width: Space.sm),
                FilledButton.icon(
                  onPressed: _loading ? null : () => _search(_query.text),
                  icon: const Icon(Icons.search, size: Sizes.iconSm),
                  label: Text(_loading ? 'جاري…' : 'ابحث'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(Sizes.minTarget, Sizes.minTarget),
                  ),
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
                      // Keyed by the customer, so selecting another row builds a fresh detail
                      // rather than reusing the previous one's state. The detail guards its own
                      // late loads as well; this is the second line, not the only one.
                      key: ValueKey(_selectedCustomer!.id),
                      customer: _selectedCustomer!,
                      onDeleted: () {
                        setState(() => _selectedCustomer = null);
                        _search(_query.text);
                      },
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
      return const LuqmaEmptyView(
        icon: Icons.search,
        message: 'دور على عميل بالاسم أو رقم الموبايل.',
      );
    }
    if (results.isEmpty) {
      return const LuqmaEmptyView(
        icon: Icons.person_off_outlined,
        message: 'مفيش نتايج.',
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

    final initialLetter =
        customer.name.trim().isNotEmpty ? customer.name.trim()[0] : 'ع';

    final content = Material(
      color: colors.card,
      borderRadius: Radii.cardAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.cardAll,
        child: Container(
          padding: const EdgeInsets.all(Space.md),
          constraints: const BoxConstraints(minHeight: Sizes.minTarget),
          decoration: BoxDecoration(
            borderRadius: Radii.cardAll,
            border: Border.all(color: colors.hairline),
          ),
          child: Row(
            children: [
              // A12 avatar: role/status coloured avatar with applicant/customer initial
              CircleAvatar(
                radius: 20,
                backgroundColor:
                    customer.isBlocked ? colors.danger : colors.brand,
                child: Text(
                  initialLetter,
                  style: TextStyle(
                    color: colors.onBrand,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            customer.name.isEmpty ? 'عميل' : customer.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (customer.isBlocked) ...[
                          const SizedBox(width: Space.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.xs,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.danger.withValues(alpha: 0.12),
                              borderRadius: Radii.pillAll,
                              border: Border.all(
                                color: colors.danger.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              'محظور',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.danger,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: Space.xs),
                    Wrap(
                      spacing: Space.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          customer.phone.isEmpty ? 'من غير رقم' : customer.phone,
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        if (customer.rejectedOrdersCount > 0)
                          Text(
                            '· ${customer.rejectedOrdersCount} رفض',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.danger,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
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
      ),
    );

    // Blocked accounts are visually dimmed per A12 mock (opacity 0.55)
    if (customer.isBlocked) {
      return Opacity(opacity: 0.55, child: content);
    }
    return content;
  }
}
