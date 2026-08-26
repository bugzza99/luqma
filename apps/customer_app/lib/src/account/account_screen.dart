import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../address/address_list_screen.dart';
import '../about/about_screen.dart';

/// حسابي.
///
/// Short on purpose. Everything a customer actually does lives on the other two tabs;
/// this one holds who they are, where they live, the way to reach a person, and the way
/// out. An account somebody cannot leave is trusted less, not more.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  static const signInKey = Key('account.signIn');
  static const signOutKey = Key('account.signOut');
  static const confirmSignOutKey = Key('account.confirmSignOut');
  static const addressesKey = Key('account.addresses');
  static const contactKey = Key('account.contact');
  static const aboutKey = Key('account.about');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(currentIdentityProvider).value;
    final colors = Theme.of(context).luqma;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('حسابي')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.lg,
          Space.gutter,
          Space.xxxl,
        ),
        children: [
          if (identity == null) const _SignInCard() else _Person(identity: identity),
          const SizedBox(height: Space.xl),
          if (identity != null) ...[
            _Tile(
              tileKey: addressesKey,
              icon: Icons.place_outlined,
              title: 'عناويني',
              subtitle: 'المناطق والعلامات اللي الدليفري بيمشي بيها',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AddressListScreen(),
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
          ],
          // Reachable signed in or out: somebody with a problem needs a person, and a
          // problem is exactly the moment an account stops working.
          _Tile(
            tileKey: contactKey,
            icon: Icons.support_agent_outlined,
            title: 'كلّمنا',
            subtitle: 'لو في مشكلة في طلب أو حاجة مش مظبوطة',
            onTap: () {},
          ),
          const SizedBox(height: Space.sm),
          _Tile(
            tileKey: aboutKey,
            icon: Icons.info_outline,
            title: 'حول لقمة',
            subtitle: 'مين احنا وإزاي توصلنا',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
            ),
          ),
          if (identity != null) ...[
            const SizedBox(height: Space.xl),
            TextButton(
              key: signOutKey,
              onPressed: () => _confirmSignOut(context, ref),
              style: TextButton.styleFrom(
                foregroundColor: colors.danger,
                minimumSize: const Size.fromHeight(Sizes.minTarget),
              ),
              child: const Text('تسجيل الخروج'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    // Asked, because signing out on a shared phone is easy to do by accident and
    // getting back in means another round-trip through Google.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تسجّل خروج؟'),
        content: const Text('عناوينك وطلباتك هتفضل محفوظة على حسابك.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('لا'),
          ),
          FilledButton(
            key: confirmSignOutKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('اخرج'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(authServiceProvider).signOut();
    }
  }
}

class _Person extends StatelessWidget {
  const _Person({required this.identity});

  final LuqmaIdentity identity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
        boxShadow: Elevations.card,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: colors.surface,
            child: Text(
              // The first letter of whatever Google gave us. An avatar image would be a
              // network fetch on a screen that has nothing else to wait for.
              (identity.name?.trim().isNotEmpty ?? false)
                  ? identity.name!.trim().characters.first
                  : '؟',
              style: theme.textTheme.titleLarge?.copyWith(color: colors.brand),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  identity.name ?? 'عميل لقمة',
                  style: theme.textTheme.titleMedium,
                ),
                if (identity.email != null)
                  Text(
                    identity.email!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignInCard extends ConsumerStatefulWidget {
  const _SignInCard();

  @override
  ConsumerState<_SignInCard> createState() => _SignInCardState();
}

class _SignInCardState extends ConsumerState<_SignInCard> {
  Failure? _failure;
  bool _busy = false;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _failure = null;
    });

    final result = await ref.read(authServiceProvider).signInWithGoogle();
    if (!mounted) return;

    setState(() {
      _busy = false;
      // Backing out of Google's sheet comes back as Ok(null). Showing an error for it
      // would be the app apologising for somebody's decision.
      _failure = result.failureOrNull;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
        boxShadow: Elevations.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('سجّل دخول', style: theme.textTheme.titleLarge),
          const SizedBox(height: Space.sm),
          Text(
            'عشان تحفظ عنوانك، وتتابع طلباتك، ونعرف نرجعلك لو في مشكلة.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colors.textSecondary),
          ),
          if (_failure != null) ...[
            const SizedBox(height: Space.md),
            Text(
              switch (_failure!) {
                OfflineFailure() => strings.errorOffline,
                _ => 'مقدرناش نسجّل دخولك. جرّب تاني.',
              },
              style: theme.textTheme.bodySmall?.copyWith(color: colors.danger),
            ),
          ],
          const SizedBox(height: Space.lg),
          FilledButton.icon(
            key: AccountScreen.signInKey,
            onPressed: _busy ? null : _signIn,
            icon: const Icon(Icons.account_circle_outlined, size: Sizes.iconSm),
            label: Text(_busy ? 'لحظة…' : 'دخول بجوجل'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.tileKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key tileKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return InkWell(
      key: tileKey,
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
            Icon(icon, color: colors.brand, size: Sizes.iconMd),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_left_rounded,
              color: colors.textSecondary,
              size: Sizes.iconMd,
            ),
          ],
        ),
      ),
    );
  }
}
