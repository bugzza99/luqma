import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../merchants/merchants_controller.dart';
import '../shell/layout.dart';

/// Every coupon in the city: the platform's own and every shop's.
///
/// A shop makes its own coupons from MerchantApp and they go live at once — the owner's
/// decision of 2026-09-17, because the discount is the shop's own money. This screen is
/// where the owner of the platform sees all of them and can stop any one, and where the
/// platform's own campaigns are made.
class CouponsScreen extends ConsumerStatefulWidget {
  const CouponsScreen({super.key});

  static const addKey = Key('coupons.add');
  static const emptyKey = Key('coupons.empty');
  static const searchKey = Key('coupons.search');
  static const filterAllKey = Key('coupons.filter.all');
  static const filterActiveKey = Key('coupons.filter.active');
  static const filterExpiredKey = Key('coupons.filter.expired');
  static const shopFilterKey = Key('coupons.filter.shop');

  @override
  ConsumerState<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends ConsumerState<CouponsScreen> {
  // A list rather than a stream: coupons change when somebody on this screen changes them,
  // so reading again after each write is all the liveness it needs.
  Future<Result<List<Coupon>>>? _load;

  /// The last list shown, kept on screen while the next read is on its way so pausing a
  /// coupon does not blank the list behind a spinner.
  Result<List<Coupon>>? _last;

  Timer? _timer;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'active', 'expired'
  String? _selectedShopId;

  @override
  void initState() {
    super.initState();
    _reload();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final load = ref.read(couponRepositoryProvider).listAll();
    setState(() {
      _load = load;
    });
    await load;
  }

  Future<void> _edit(Coupon? existing, List<Merchant> shops) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: CouponForm(
          initial: existing,
          cityId: ref.read(currentCityProvider),
          adminExtras: true,
          shops: shops,
          clock: ref.read(clockProvider),
          onSave: (draft) async {
            final repo = ref.read(couponRepositoryProvider);
            final result =
                existing == null ? await repo.create(draft) : await repo.update(draft);
            if (result case Err(:final failure)) return failure;
            if (sheetContext.mounted) Navigator.of(sheetContext).pop(true);
            return null;
          },
        ),
      ),
    );
    if (saved ?? false) _reload();
  }

  Future<void> _setActive(Coupon coupon, bool active) async {
    final result = await ref.read(couponRepositoryProvider).setActive(coupon.id, active);
    if (!mounted) return;
    if (result is Err) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مقدرناش نغيّر حالة الكوبون. جرّب تاني.')),
      );
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final shops = ref.watch(allMerchantsProvider).value ?? const <Merchant>[];
    final now = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(title: const Text('الكوبونات')),
      floatingActionButton: FloatingActionButton.extended(
        key: CouponsScreen.addKey,
        onPressed: () => _edit(null, shops),
        icon: const Icon(Icons.add),
        label: const Text('كوبون جديد'),
      ),
      body: AdminContent(
        child: FutureBuilder<Result<List<Coupon>>>(
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.data != null) _last = snapshot.data;
            final result = snapshot.data ?? _last;
            if (result == null) return const Center(child: CircularProgressIndicator());
            return switch (result) {
              Err(:final failure) => LuqmaErrorView(failure: failure, onRetry: _reload),
              Ok(:final value) when value.isEmpty => RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Center(
                        key: CouponsScreen.emptyKey,
                        child: Padding(
                          padding: const EdgeInsets.all(Space.xl),
                          child: Text(
                            'مفيش كوبونات لسه. كوبونات المحلات بتظهر هنا أول ما يعملوها.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: colors.textSecondary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Ok(:final value) => RefreshIndicator(
                  onRefresh: _reload,
                  child: Builder(
                    builder: (context) {
                      final filtered = value.where((c) {
                        if (_searchQuery.isNotEmpty &&
                            !c.code.toLowerCase().contains(_searchQuery.toLowerCase())) {
                          return false;
                        }
                        final isExpired =
                            !c.isActive || (c.validUntil != null && c.validUntil!.isBefore(now));
                        if (_statusFilter == 'active' && isExpired) return false;
                        if (_statusFilter == 'expired' && !isExpired) return false;

                        if (_selectedShopId != null) {
                          if (_selectedShopId == 'platform' && c.merchantId != null) return false;
                          if (_selectedShopId != 'platform' && c.merchantId != _selectedShopId) {
                            return false;
                          }
                        }
                        return true;
                      }).toList();

                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          Space.gutter,
                          Space.gutter,
                          Space.gutter,
                          Space.xxxl + Space.xl,
                        ),
                        children: [
                          TextField(
                            key: CouponsScreen.searchKey,
                            controller: _searchController,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              labelText: 'ابحث بكود الكوبون',
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      tooltip: 'مسح',
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    )
                                  : null,
                            ),
                            onChanged: (v) => setState(() => _searchQuery = v.trim()),
                          ),
                          const SizedBox(height: Space.sm),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                ChoiceChip(
                                  key: CouponsScreen.filterAllKey,
                                  label: const Text('كله'),
                                  selected: _statusFilter == 'all',
                                  onSelected: (_) => setState(() => _statusFilter = 'all'),
                                ),
                                const SizedBox(width: Space.xs),
                                ChoiceChip(
                                  key: CouponsScreen.filterActiveKey,
                                  label: const Text('شغّال'),
                                  selected: _statusFilter == 'active',
                                  onSelected: (_) => setState(() => _statusFilter = 'active'),
                                ),
                                const SizedBox(width: Space.xs),
                                ChoiceChip(
                                  key: CouponsScreen.filterExpiredKey,
                                  label: const Text('منتهي'),
                                  selected: _statusFilter == 'expired',
                                  onSelected: (_) => setState(() => _statusFilter = 'expired'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: Space.sm),
                          DropdownButtonFormField<String?>(
                            key: CouponsScreen.shopFilterKey,
                            initialValue: _selectedShopId,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'تصفية حسب المحل'),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('كل المحلات والمنصة')),
                              const DropdownMenuItem(value: 'platform', child: Text('المنصة فقط')),
                              for (final shop in shops)
                                DropdownMenuItem(value: shop.id, child: Text(shop.name)),
                            ],
                            onChanged: (v) => setState(() => _selectedShopId = v),
                          ),
                          const SizedBox(height: Space.md),
                          if (filtered.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(Space.xl),
                              child: Text(
                                'مفيش كوبونات مطابقة.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: colors.textSecondary),
                              ),
                            )
                          else
                            for (final coupon in filtered) ...[
                              Builder(
                                builder: (context) {
                                  final owner = coupon.merchantId == null
                                      ? 'المنصة'
                                      : shops
                                              .where((m) => m.id == coupon.merchantId)
                                              .firstOrNull
                                              ?.name ??
                                          'محل';
                                  return CouponTile(
                                    coupon: coupon,
                                    owner: owner,
                                    onTap: () => _edit(coupon, shops),
                                    onActiveChanged: (active) => _setActive(coupon, active),
                                  );
                                },
                              ),
                              const SizedBox(height: Space.sm),
                            ],
                        ],
                      );
                    },
                  ),
                ),
            };
          },
        ),
      ),
    );
  }
}
