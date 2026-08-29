import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// Entering or correcting one address.
///
/// The zone/landmark/detail part is [AddressPicker], shared with AdminApp so an address
/// the owner types during onboarding is the same shape as one a customer types. The only
/// thing added here is the label — the word the customer will pick this address by later,
/// which is theirs and means nothing to a courier.
class AddressEditorScreen extends ConsumerStatefulWidget {
  const AddressEditorScreen({super.key, this.initial});

  final Address? initial;

  static const labelKey = Key('addressEditor.label');
  static const errorKey = Key('addressEditor.error');

  @override
  ConsumerState<AddressEditorScreen> createState() => _AddressEditorScreenState();
}

class _AddressEditorScreenState extends ConsumerState<AddressEditorScreen> {
  late final _label = TextEditingController(text: widget.initial?.label ?? '');

  Failure? _failure;
  bool _saving = false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save(Address address) async {
    setState(() {
      _saving = true;
      _failure = null;
    });

    final label = _label.text.trim();
    final result = await ref.read(addressActionsProvider).save(
          address.copyWith(label: label.isEmpty ? null : label),
        );

    if (!mounted) return;

    switch (result) {
      // Sending somebody back to a blank form after a failed save is the app losing
      // their work on its own behalf. The form stays exactly as they left it.
      case Err(:final failure):
        setState(() {
          _saving = false;
          _failure = failure;
        });
      case Ok():
        // Cleared before popping, not instead of it. A screen opened as a root — the
        // first-address flow at checkout has no editor to pop back from — would
        // otherwise sit under a progress bar that never goes away.
        setState(() => _saving = false);
        Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    // Watched, not merely read at save time: the address is saved onto whoever is
    // signed in, so the session has to be live and resolved before the save runs —
    // otherwise the save waits on a provider nothing has started.
    ref.watch(currentIdentityProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'عنوان جديد' : 'تعديل العنوان'),
      ),
      body: Column(
        children: [
          if (_failure != null)
            _ErrorBanner(key: AddressEditorScreen.errorKey, failure: _failure!),
          if (_saving) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.lg,
              Space.gutter,
              0,
            ),
            child: TextField(
              key: AddressEditorScreen.labelKey,
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'اسم العنوان',
                hintText: 'البيت، الشغل…',
              ),
            ),
          ),
          Expanded(
            child: AddressPicker(
              initial: widget.initial,
              onSaved: (address) => _saving ? null : _save(address),
            ),
          ),
        ],
      ),
      backgroundColor: colors.background,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({super.key, required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    final strings = LuqmaStrings.of(context);

    return Container(
      width: double.infinity,
      color: colors.danger.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.md,
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: Sizes.iconSm, color: colors.danger),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              switch (failure) {
                OfflineFailure() => strings.errorOffline,
                PermissionFailure() => 'لازم تسجّل دخول الأول عشان تحفظ عنوان.',
                _ => strings.errorUnknown,
              },
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
