import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import 'address_editor_screen.dart';

/// The customer's addresses, and which one an order would go to.
///
/// Each row is written the way a courier reads it: the zone first, then the landmark.
/// A building number is the last thing anybody navigates by here, so it is not what the
/// row leads with.
class AddressListScreen extends ConsumerWidget {
  const AddressListScreen({super.key, this.onSignIn});

  /// Opens the sign-in sheet. Injected so the shell owns that decision.
  final VoidCallback? onSignIn;

  static const emptyKey = Key('addresses.empty');
  static const addKey = Key('addresses.add');
  static const signInKey = Key('addresses.signIn');
  static const confirmDeleteKey = Key('addresses.confirmDelete');

  static Key rowKey(String id) => Key('addresses.row.$id');
  static Key chosenKey(String id) => Key('addresses.chosen.$id');
  static Key deleteKey(String id) => Key('addresses.delete.$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(currentIdentityProvider).value;
    final addresses = ref.watch(myAddressesProvider);
    final chosen = ref.watch(chosenAddressProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('عناويني')),
      body: identity == null
          ? _SignedOut(onSignIn: onSignIn)
          : switch (addresses) {
              // An error arm comes first, and matches on `hasError` rather than on the
              // `AsyncError` type: a stream that fails before it has ever emitted stays
              // `AsyncLoading` with the error hanging off it, so a type match never fires
              // and the screen spins for ever on a dropped connection.
              AsyncValue(hasError: true, :final error?) => LuqmaErrorView(failure: error, onRetry: () => ref.invalidate(myAddressesProvider)),
              AsyncValue(hasValue: true, :final value?) when value.isEmpty =>
                const _Empty(),
              AsyncValue(hasValue: true, :final value?) => _List(
                  addresses: value,
                  chosenId: chosen?.id,
                ),
                          _ => const Center(child: CircularProgressIndicator()),
},
      floatingActionButton: identity == null
          ? null
          : FloatingActionButton.extended(
              key: addKey,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AddressEditorScreen(),
                ),
              ),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('ضيف عنوان'),
            ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.addresses, required this.chosenId});

  final List<Address> addresses;
  final String? chosenId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zones = ref.watch(zonesProvider).value ?? const <Zone>[];

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        Space.xxxl * 2,
      ),
      itemCount: addresses.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
      itemBuilder: (context, i) {
        final address = addresses[i];
        final zone = zones.where((z) => z.id == address.zoneId).firstOrNull;
        return _Row(
          address: address,
          zoneName: zone?.name ?? '',
          isChosen: address.id == chosenId,
        );
      },
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({
    required this.address,
    required this.zoneName,
    required this.isChosen,
  });

  final Address address;
  final String zoneName;
  final bool isChosen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return InkWell(
      key: AddressListScreen.rowKey(address.id),
      onTap: () => ref.read(addressActionsProvider).choose(address.id),
      borderRadius: Radii.cardAll,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        constraints: const BoxConstraints(minHeight: Sizes.minTarget),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: Radii.cardAll,
          border: Border.all(
            color: isChosen ? colors.brand : colors.hairline,
            width: isChosen ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isChosen
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              key: isChosen ? AddressListScreen.chosenKey(address.id) : null,
              color: isChosen ? colors.brand : colors.textSecondary,
              size: Sizes.iconMd,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (address.label != null && address.label!.isNotEmpty)
                    Text(address.label!, style: theme.textTheme.titleMedium),
                  Text(
                    address.format(zoneName: zoneName),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            IconButton(
              key: AddressListScreen.deleteKey(address.id),
              tooltip: 'امسح العنوان',
              onPressed: () => _confirmDelete(context, ref),
              icon: Icon(Icons.delete_outline_rounded, color: colors.textSecondary),
              constraints: const BoxConstraints(
                minWidth: Sizes.minTarget,
                minHeight: Sizes.minTarget,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    // Never silently: an address is a few minutes of somebody's typing, and a tap next
    // to the row that selects it is exactly the tap that gets made by accident.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تمسح العنوان؟'),
        content: Text(address.label ?? address.format(zoneName: zoneName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('سيبه'),
          ),
          FilledButton(
            key: AddressListScreen.confirmDeleteKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('امسح'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(addressActionsProvider).remove(address.id);
    }
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut({this.onSignIn});

  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'العناوين محفوظة على حسابك.',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.sm),
            Text(
              'سجّل دخول عشان تحفظ عنوانك مرة واحدة وتستخدمه كل مرة.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.luqma.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.xl),
            FilledButton(
              key: AddressListScreen.signInKey,
              onPressed: onSignIn,
              child: const Text('سجّل دخول'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      key: AddressListScreen.emptyKey,
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_off_outlined,
              size: 56,
              color: theme.luqma.textSecondary,
            ),
            const SizedBox(height: Space.lg),
            Text(
              'لسه مفيش عناوين محفوظة.',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.sm),
            Text(
              'ضيف عنوانك مرة واحدة وهيفضل موجود.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.luqma.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

