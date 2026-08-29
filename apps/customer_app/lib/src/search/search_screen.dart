import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../home/sections/merchant_card.dart';
import '../merchant/open_merchant.dart';

/// Looking for something to eat.
///
/// This screen is what `docs/04` meant when it decided against a categories tab: thirty
/// merchants cannot fill one, "search covers the rest". The search box then shipped as a
/// read-only field with an empty `onTap`, so the thing the whole decision rested on did
/// nothing at all — the tab was removed and nothing took its place.
///
/// Shops and dishes, in two lists. Somebody typing here is looking for food rather than
/// for a building, so "كشري" has to find whoever makes it.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  static const fieldKey = Key('search.field');
  static const emptyKey = Key('search.empty');
  static const noResultsKey = Key('search.noResults');
  static const merchantsKey = Key('search.merchants');
  static const dishesKey = Key('search.dishes');

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  /// Long enough that typing a word is one query rather than six, short enough that it
  /// still feels like it is keeping up.
  static const _debounce = Duration(milliseconds: 300);

  final _controller = TextEditingController();
  Timer? _timer;

  SearchResults? _results;
  Failure? _failure;
  bool _searching = false;
  String _lastQuery = '';

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        // Clearing the box also has to invalidate whatever is already in the air.
        // `_run` guards on `query != _lastQuery`, so leaving the old query here means a
        // response that lands after the customer hits clear passes that guard and
        // repopulates the list under an empty box.
        _lastQuery = '';
        _results = null;
        _failure = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _timer = Timer(_debounce, () => _run(value));
  }

  Future<void> _run(String query) async {
    _lastQuery = query;
    final result = await ref.read(searchRepositoryProvider).search(
          cityId: ref.read(currentCityProvider),
          query: query,
        );
    if (!mounted) return;

    // A result for something the customer has since retyped is stale; dropping it stops
    // the list flickering back to an older answer.
    if (query != _lastQuery) return;

    setState(() {
      _searching = false;
      _results = result.valueOrNull;
      _failure = result.failureOrNull;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    final strings = LuqmaStrings.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: TextField(
          key: SearchScreen.fieldKey,
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (v) {
            _timer?.cancel();
            _run(v);
          },
          decoration: InputDecoration(
            hintText: strings.searchHint,
            border: InputBorder.none,
            isDense: true,
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              // The accessible name as well as the long-press label; every IconButton in
              // this product carries one, and a test scans the source to make sure.
              tooltip: 'امسح',
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final failure = _failure;
    if (failure != null) {
      return LuqmaErrorView(failure: failure, onRetry: () => _run(_lastQuery));
    }

    final results = _results;
    if (results == null) {
      return _searching
          ? const Center(child: CircularProgressIndicator())
          : const _Prompt();
    }
    if (results.isEmpty) return _NoResults(query: _lastQuery);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.md,
        Space.gutter,
        Space.xxxl,
      ),
      children: [
        if (results.merchants.isNotEmpty) ...[
          const _Heading(text: 'مطاعم', headingKey: SearchScreen.merchantsKey),
          for (final merchant in results.merchants) ...[
            MerchantCard(merchant: merchant),
            const SizedBox(height: Space.sm),
          ],
        ],
        if (results.dishes.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          const _Heading(text: 'أصناف', headingKey: SearchScreen.dishesKey),
          for (final dish in results.dishes) ...[
            _DishRow(item: dish.item, merchant: dish.merchant),
            const SizedBox(height: Space.sm),
          ],
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.text, required this.headingKey});

  final String text;
  final Key headingKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: headingKey,
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// A dish, with the shop that makes it.
///
/// The shop's name is not decoration: a dish on its own is something the customer cannot
/// act on, and tapping opens the shop rather than the dish because that is where the
/// price, the options and the basket are.
class _DishRow extends StatelessWidget {
  const _DishRow({required this.item, required this.merchant});

  final MenuItem item;
  final Merchant merchant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return InkWell(
      onTap: () => openMerchant(context, merchant.id),
      borderRadius: Radii.cardAll,
      child: Container(
        padding: const EdgeInsets.all(Space.sm + 2),
        constraints: const BoxConstraints(minHeight: Sizes.minTarget),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: Radii.cardAll,
          border: Border.all(color: colors.hairline),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: Radii.imageAll,
              child: SizedBox(
                width: 52,
                height: 52,
                child: LuqmaImage(url: null, name: item.name),
              ),
            ),
            const SizedBox(width: Space.md - 1),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: theme.textTheme.titleMedium),
                  Text(
                    merchant.name,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            // A price below 18sp uses the deeper accent: #D67F2B on white is 3.03:1 and
            // clears only the large-text threshold.
            Text(
              strings.price(item.price),
              style: LuqmaType.priceSmall.copyWith(color: colors.price),
            ),
          ],
        ),
      ),
    );
  }
}

/// Before anything has been typed.
class _Prompt extends ConsumerWidget {
  const _Prompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final cuisines = ref.watch(cuisinesProvider).value ?? const <Cuisine>[];

    return Padding(
      key: SearchScreen.emptyKey,
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'دوّر على مطعم، أو على الأكلة نفسها.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colors.textSecondary),
          ),
          if (cuisines.isNotEmpty) ...[
            const SizedBox(height: Space.lg),
            // Something to press rather than a blank screen with a cursor on it — and
            // the cuisines are the words most likely to find anything.
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final cuisine in cuisines)
                  ActionChip(
                    label: Text(cuisine.name),
                    backgroundColor: colors.card,
                    side: BorderSide(color: colors.border),
                    onPressed: () {
                      final state = context
                          .findAncestorStateOfType<_SearchScreenState>();
                      state?._controller.text = cuisine.name;
                      state?._onChanged(cuisine.name);
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Center(
      key: SearchScreen.noResultsKey,
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Text(
          'مالقيناش «$query».',
          textAlign: TextAlign.center,
          style:
              theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}
