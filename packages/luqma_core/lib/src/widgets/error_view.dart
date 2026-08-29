import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../result.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';

/// What a screen shows when the thing it was reading failed.
///
/// One widget, shared by all three apps. It began as a private `_Error` copied into
/// seventeen files — fifteen of which had quietly drifted apart — and none of the copies
/// offered a way out. That mattered most on the merchant's order inbox: a stream that
/// dropped left a sentence on the screen and no control at all, so recovering meant
/// killing the app from the task switcher, on the one screen where a silent evening is
/// money.
///
/// The failure decides the sentence, because "no connection", "not allowed" and
/// "something broke" ask three different things of the person reading them, and only
/// one of the three is worth trying again straight away.
class LuqmaErrorView extends StatelessWidget {
  const LuqmaErrorView({
    super.key,
    required this.failure,
    this.onRetry,
    this.compact = false,
  });

  /// What went wrong. A [Failure] is turned into its own sentence; anything else falls
  /// back to the general one rather than putting a stack trace in front of a customer.
  final Object? failure;

  /// What to do about it — usually `ref.invalidate` on the provider that failed. When
  /// null no control is drawn: a button that does nothing is worse than no button.
  final VoidCallback? onRetry;

  /// For a slot inside a working page — a banner row on the home screen — where the
  /// full-height form would take over a page that is otherwise fine.
  final bool compact;

  String _sentence(LuqmaStrings strings) => switch (failure) {
        OfflineFailure() => strings.errorOffline,
        PermissionFailure() => strings.errorPermission,
        NotFoundFailure() => strings.errorNotFound,
        ConflictFailure() => strings.errorConflict,
        EmailTakenFailure() => strings.errorEmailTaken,
        PhoneTakenFailure() => strings.errorPhoneTaken,
        _ => strings.errorUnknown,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = LuqmaStrings.of(context);
    final retry = onRetry;

    final message = Text(
      _sentence(strings),
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(color: theme.luqma.textSecondary),
    );

    if (retry == null) {
      return Padding(
        padding: EdgeInsets.all(compact ? Space.md : Space.xxl),
        child: Center(child: message),
      );
    }

    final button = TextButton.icon(
      onPressed: retry,
      icon: const Icon(Icons.refresh, size: 18),
      // The label is the accessible name as well as the visible one: an icon on its own
      // is announced as "button" and nothing more.
      label: Text(strings.actionRetry),
    );

    return Padding(
      padding: EdgeInsets.all(compact ? Space.md : Space.xxl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            message,
            SizedBox(height: compact ? Space.sm : Space.lg),
            button,
          ],
        ),
      ),
    );
  }
}
