import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'error_view.dart';

/// The three states every screen in this product has, decided in one place.
///
/// Twenty-eight screens hand-wrote the same `switch`, and the line count is the least of
/// it. The error arm has to come first, and it has to match on `hasError` rather than on
/// the `AsyncError` type: a stream that fails before it has ever emitted stays
/// `AsyncLoading` with the error hanging off it, so a type match never fires and the
/// screen spins for ever on a dropped connection.
///
/// That is written in `CLAUDE.md` as a trap because it was got wrong on the merchant's
/// order inbox, where a screen that spins reads as a quiet evening and a quiet evening is
/// money. Twenty-eight copies of a rule is twenty-eight chances to write the twenty-ninth
/// wrong. Here it is written once.
///
/// Screens that build slivers keep their own `switch` — a widget cannot be both a box and
/// a sliver, and there is exactly one of those.
class LuqmaAsyncView<T> extends StatelessWidget {
  const LuqmaAsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.empty,
    this.isEmpty,
    this.loading,
    this.errorKey,
  });

  final AsyncValue<T> value;

  /// What the screen actually draws once there is something to draw.
  final Widget Function(BuildContext context, T value) builder;

  /// Usually `ref.invalidate` on the provider that failed. Without it no control is
  /// drawn, on [LuqmaErrorView]'s rule: a button that does nothing is worse than none.
  final VoidCallback? onRetry;

  /// Shown instead of [builder] when [isEmpty] says there is nothing.
  ///
  /// Optional, because a screen whose empty row belongs *inside* its own list — a table
  /// with a "nothing yet" line under the header — should keep drawing it itself.
  final Widget? empty;

  /// Whether the loaded value counts as nothing. Only consulted when [empty] is given.
  final bool Function(T value)? isEmpty;

  /// For a screen whose waiting state is a skeleton of itself rather than a spinner.
  final Widget? loading;

  /// Passed through to the error view.
  ///
  /// Several screens name their error state so a test can find it, and consolidating
  /// must not quietly take that away — a test that can no longer find what it asserts on
  /// is a test that stops testing.
  final Key? errorKey;

  @override
  Widget build(BuildContext context) {
    // `hasError` first, and before any check on the value: this is the whole point.
    if (value.hasError && !value.hasValue) {
      return LuqmaErrorView(key: errorKey, failure: value.error, onRetry: onRetry);
    }

    // A value already loaded stays on screen while a refresh is in flight. Blanking a
    // working page to a spinner on every reload is a flicker the customer reads as the
    // app losing their place.
    if (value.hasValue) {
      final loaded = value.value as T;
      final blank = empty != null && (isEmpty?.call(loaded) ?? false);
      return blank ? empty! : builder(context, loaded);
    }

    return loading ?? const Center(child: CircularProgressIndicator());
  }
}
