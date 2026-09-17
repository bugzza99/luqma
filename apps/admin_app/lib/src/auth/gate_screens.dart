import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// Shown while the session resolves.
///
/// The brand splash rather than a spinner: it is the same moment the customer app uses
/// it for, and a bare spinner here would be the only unbranded screen in the product.
class StartingScreen extends StatelessWidget {
  const StartingScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: LuqmaSplash());
}

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  static const emailKey = Key('signIn.email');
  static const passwordKey = Key('signIn.password');
  static const submitKey = Key('signIn.submit');

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  var _email = '';
  var _password = '';
  var _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref.read(authServiceProvider).signInWithPassword(
          email: _email,
          password: _password,
        );
    if (!mounted) return;

    // No navigation on success. The router is watching the session and moves on its
    // own — pushing a route as well would race it.
    setState(() {
      _busy = false;
      _error = switch (result) {
        Ok() => null,
        // Never the raw Firebase code, and never "invalid credential" — neither tells
        // somebody standing in a shop anything they can act on.
        Err(failure: OfflineFailure()) => 'مفيش اتصال بالإنترنت',
        Err() => 'البيانات غلط',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LuqmaLockup(logo: LuqmaLogo.mark, height: 64),
                  const SizedBox(height: Space.lg),
                  Text(
                    'لوحة إدارة لقمة',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    'للفريق الإداري فقط',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Space.xxl),
                  TextFormField(
                    key: SignInScreen.emailKey,
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      hintText: 'admin@luqma.app',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    validator: (v) =>
                        (v == null || !v.contains('@')) ? 'اكتب بريد صحيح' : null,
                    onSaved: (v) => _email = v!.trim(),
                  ),
                  const SizedBox(height: Space.md),
                  TextFormField(
                    key: SignInScreen.passwordKey,
                    decoration: const InputDecoration(labelText: 'كلمة السر'),
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'اكتب كلمة السر' : null,
                    onSaved: (v) => _password = v!,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Space.md),
                    Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: Space.xl),
                  FilledButton(
                    key: SignInScreen.submitKey,
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(Sizes.minTarget),
                    ),
                    child: Text(_busy ? '…' : 'دخول'),
                  ),
                  const SizedBox(height: Space.xl),
                  // The design's A01 notice said access is checked against
                  // `staff.scope = platform` and that every change is written to `auditLog`.
                  // Neither belongs here. The second is not true — config changes, payments
                  // and application reviews are audited, and menu edits, for one, are not —
                  // and a sentence the product says about itself that is false is the kind
                  // somebody relies on three weeks later. The first is a table and a column,
                  // on the one screen anybody holding this APK can open without an account.
                  Text(
                    'للفريق الإداري فقط. الحسابات بتتعمل من جوه لقمة.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Signed in, but the token carries no admin claim.
class NoAccessScreen extends ConsumerWidget {
  const NoAccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LuqmaLockup(logo: LuqmaLogo.mark, height: 64),
              const SizedBox(height: Space.xl),
              Text(
                'الحساب ده مالوش صلاحية دخول',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.sm),
              Text(
                'لو ده حسابك الصح، الصلاحية بتتضاف من السيرفر مرة واحدة.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.luqma.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.xl),
              OutlinedButton(
                onPressed: () => ref.read(authServiceProvider).signOut(),
                child: const Text('تسجيل الخروج'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
