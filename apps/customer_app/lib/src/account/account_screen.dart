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
  static const nameKey = Key('account.name');
  static const phoneKey = Key('account.phone');
  static const passwordKey = Key('account.password');
  static const toggleModeKey = Key('account.toggleMode');
  static const errorKey = Key('account.error');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(currentIdentityProvider).value;
    final colors = Theme.of(context).luqma;
    // `support_whatsapp` has been carried from AdminApp to the phone since Phase 1 and
    // read by nobody: this tile was drawn regardless and did nothing when tapped. Blank
    // means the owner has not set a number, and then there is no tile — the same rule
    // حول لقمة already applies to its own icons.
    final support = ref.watch(appConfigProvider).supportWhatsapp.trim();

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
          if (support.isNotEmpty) ...[
            _Tile(
              tileKey: contactKey,
              icon: Icons.support_agent_outlined,
              title: 'كلّمنا',
              subtitle: 'لو في مشكلة في طلب أو حاجة مش مظبوطة',
              onTap: () => openExternalLink(
                context,
                ref,
                Uri.parse('https://wa.me/${Phone.toWhatsapp(support)}'),
                whenUnavailable: 'مفيش واتساب على التليفون ده. الرقم $support',
              ),
            ),
            const SizedBox(height: Space.sm),
          ],
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
    // Asked, because signing out on a shared phone is easy to do by accident and getting
    // back in means remembering a password.
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
              // The first letter of the name they typed. An avatar image would be a
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
                if (identity.phone != null)
                  Text(
                    identity.phone!,
                    textDirection: TextDirection.ltr,
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
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  // Sign-in is the default: most people opening this card already have an account.
  bool _signingUp = false;
  bool _busy = false;
  Failure? _failure;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _failure = null;
    });

    final auth = ref.read(authServiceProvider);
    final result = _signingUp
        ? await auth.signUpWithPhone(
            phone: _phone.text.trim(),
            password: _password.text,
            name: _name.text.trim(),
          )
        : await auth.signInWithPhone(
            phone: _phone.text.trim(),
            password: _password.text,
          );
    if (!mounted) return;

    setState(() {
      _busy = false;
      _failure = result.failureOrNull;
    });
  }

  void _toggleMode() {
    setState(() {
      _signingUp = !_signingUp;
      _failure = null;
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
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _signingUp ? 'حساب جديد' : 'سجّل دخول',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: Space.sm),
            Text(
              'عشان تحفظ عنوانك، وتتابع طلباتك، ونعرف نرجعلك لو في مشكلة.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: Space.lg),
            if (_signingUp) ...[
              TextFormField(
                key: AccountScreen.nameKey,
                controller: _name,
                decoration: const InputDecoration(labelText: 'الاسم'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'اكتب اسمك' : null,
              ),
              const SizedBox(height: Space.md),
            ],
            TextFormField(
              key: AccountScreen.phoneKey,
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'رقم الموبايل',
                hintText: '01012345678',
              ),
              validator: (v) => Phone.isValidEgyptianMobile(v ?? '')
                  ? null
                  : 'اكتب رقم موبايل مصري صحيح — يبدأ بـ 01 ومكوّن من 11 رقم.',
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              key: AccountScreen.passwordKey,
              controller: _password,
              obscureText: true,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'كلمة السر'),
              validator: (v) {
                if ((v ?? '').isEmpty) return 'اكتب كلمة السر';
                // Only enforced going in: an existing account's password was already
                // accepted once, and a shorter minimum since then must not lock it out.
                if (_signingUp && v!.length < 6) {
                  return 'كلمة السر لازم تكون 6 حروف على الأقل';
                }
                return null;
              },
              onFieldSubmitted: (_) => _busy ? null : _submit(),
            ),
            if (_failure != null) ...[
              const SizedBox(height: Space.md),
              Text(
                switch (_failure!) {
                  OfflineFailure() => strings.errorOffline,
                  PhoneTakenFailure() => strings.errorPhoneTaken,
                  _ => _signingUp
                      ? 'مقدرناش نعمل الحساب. جرّب تاني.'
                      : 'رقم الموبايل أو كلمة السر غلط',
                },
                key: AccountScreen.errorKey,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.danger),
              ),
            ],
            const SizedBox(height: Space.lg),
            FilledButton(
              key: AccountScreen.signInKey,
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: Text(
                _busy ? 'لحظة…' : (_signingUp ? 'إنشاء الحساب' : 'دخول'),
              ),
            ),
            const SizedBox(height: Space.sm),
            TextButton(
              key: AccountScreen.toggleModeKey,
              onPressed: _busy ? null : _toggleMode,
              child: Text(
                _signingUp ? 'عندي حساب بالفعل' : 'معنديش حساب، عايز أعمل واحد',
              ),
            ),
          ],
        ),
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
