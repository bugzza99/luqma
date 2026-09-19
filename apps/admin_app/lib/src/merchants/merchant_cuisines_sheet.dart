import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../cuisines/cuisines_screen.dart';

/// Backed by the `cuisines` table (city-wide, name + picture).
/// Lists every category of the merchant's city as [FilterChip]s (multi-select),
/// pre-selected from `cuisinesOf`, with a save button that calls `setMerchantCuisines`.
class MerchantCuisinesSheet extends ConsumerStatefulWidget {
  const MerchantCuisinesSheet({super.key, required this.merchant});

  final Merchant merchant;

  static const openKey = Key('merchant.cuisines.open');
  static Key chipKey(dynamic id) => Key('merchant.cuisines.chip.$id');
  static const saveKey = Key('merchant.cuisines.save');

  @override
  ConsumerState<MerchantCuisinesSheet> createState() =>
      _MerchantCuisinesSheetState();
}

class _MerchantCuisinesSheetState extends ConsumerState<MerchantCuisinesSheet> {
  bool _loading = true;
  Failure? _loadFailure;
  List<Cuisine> _cuisines = const [];
  Set<String> _selected = const {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool keepSelection = false}) async {
    setState(() {
      _loading = true;
      _loadFailure = null;
    });

    final repo = ref.read(cuisineRepositoryProvider);
    if (keepSelection) {
      final cityResult = await repo.forCity(widget.merchant.cityId);
      if (!mounted) return;
      if (cityResult case Err(:final failure)) {
        setState(() {
          _loading = false;
          _loadFailure = failure;
        });
        return;
      }
      setState(() {
        _loading = false;
        _cuisines = cityResult.valueOrNull ?? [];
      });
    } else {
      final results = await Future.wait([
        repo.forCity(widget.merchant.cityId),
        repo.cuisinesOf(widget.merchant.id),
      ]);
      if (!mounted) return;

      final cityResult = results[0] as Result<List<Cuisine>>;
      final ofResult = results[1] as Result<Set<String>>;

      if (cityResult case Err(:final failure)) {
        setState(() {
          _loading = false;
          _loadFailure = failure;
        });
        return;
      }
      if (ofResult case Err(:final failure)) {
        setState(() {
          _loading = false;
          _loadFailure = failure;
        });
        return;
      }

      setState(() {
        _loading = false;
        _cuisines = cityResult.valueOrNull ?? [];
        _selected = {...(ofResult.valueOrNull ?? {})};
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(cuisineRepositoryProvider);
    final result =
        await repo.setMerchantCuisines(widget.merchant.id, _selected);
    if (!mounted) return;
    setState(() => _saving = false);

    switch (result) {
      case Ok():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اتحفظت تصنيفات المحل')),
        );
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      case Err(:final failure):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switch (failure) {
              OfflineFailure() => 'مفيش نت — جرّب تاني.',
              _ => 'مقدرناش نحفظ. جرّب تاني.',
            }),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Padding(
      padding: EdgeInsets.only(
        left: Space.gutter,
        right: Space.gutter,
        top: Space.xl,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Space.xl,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('تصنيفات المحل', style: theme.textTheme.titleLarge),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: Space.xs),
              Text(
                'اختر تصنيفات المحل اللي بيظهر فيها في تطبيق العميل',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: Space.lg),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(Space.xxl),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_loadFailure != null)
                LuqmaErrorView(
                  failure: _loadFailure,
                  onRetry: _load,
                )
              else if (_cuisines.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'مفيش تصنيفات لسه',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          'المدينة دي لسه مفيهاش أي تصنيفات محلات. تقدر تضيفها من شاشة تصنيفات المحلات.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: Space.lg),
                        FilledButton(
                          onPressed: () async {
                            // Pushed on the Navigator, above this sheet, rather than through
                            // the router: a router push rebuilds the page stack and drops
                            // the sheet under it, so coming back found nothing to reload.
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const CuisinesScreen(),
                              ),
                            );
                            if (mounted) {
                              await _load(keepSelection: true);
                            }
                          },
                          child: const Text('تصنيفات المحلات'),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final cuisine in _cuisines)
                      FilterChip(
                        key: MerchantCuisinesSheet.chipKey(cuisine.id),
                        label: Text(cuisine.name),
                        selected: _selected.contains(cuisine.id),
                        onSelected: (selected) {
                          setState(() {
                            final next = {..._selected};
                            if (selected) {
                              next.add(cuisine.id);
                            } else {
                              next.remove(cuisine.id);
                            }
                            _selected = next;
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: Space.xl),
                FilledButton(
                  key: MerchantCuisinesSheet.saveKey,
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(Sizes.minTarget),
                  ),
                  child: Text(_saving ? 'جاري…' : 'احفظ'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
