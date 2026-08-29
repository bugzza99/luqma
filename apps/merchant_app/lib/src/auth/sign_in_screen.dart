import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// The way in.
///
/// Email and password, because a merchant account is created *for* somebody by the
/// owner — there is no self-service sign-up, and there never will be. The whole supply
/// side of this platform is people the owner has met.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  static const emailKey = Key('signIn.email');
  static const passwordKey = Key('signIn.password');
  static const submitKey = Key('signIn.submit');
  static const errorKey = Key('signIn.error');

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref.read(authServiceProvider).signInWithPassword(
          email: _email.text,
          password: _password.text,
        );
    if (!mounted) return;

    // No navigation on success: the app is watching the session and moves on its own.
    // Pushing a route here as well would race it.
    setState(() {
      _busy = false;
      _error = switch (result) {
        Ok() => null,
        Err(failure: OfflineFailure()) => 'مفيش اتصال بالإنترنت',
        // Never "invalid credential", and never the raw code: neither tells somebody
        // standing in a kitchen anything they can act on.
        Err() => 'البيانات غلط',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Scaffold(
      backgroundColor: colors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: LuqmaLockup(logo: LuqmaLogo.mark, height: 72)),
                  const SizedBox(height: Space.xl),
                  Text(
                    'دخول التاجر',
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    'الحساب بيتعمل من إدارة لقمة. لو مش معاك بيانات دخول كلّمهم.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Space.xl),
                  TextFormField(
                    key: SignInScreen.emailKey,
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(labelText: 'الإيميل'),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'اكتب الإيميل' : null,
                  ),
                  const SizedBox(height: Space.md),
                  TextFormField(
                    key: SignInScreen.passwordKey,
                    controller: _password,
                    obscureText: true,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(labelText: 'كلمة السر'),
                    validator: (v) =>
                        (v ?? '').isEmpty ? 'اكتب كلمة السر' : null,
                    onFieldSubmitted: (_) => _busy ? null : _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Space.md),
                    Text(
                      _error!,
                      key: SignInScreen.errorKey,
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.danger),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: Space.xl),
                  FilledButton(
                    key: SignInScreen.submitKey,
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: Text(_busy ? 'لحظة…' : 'دخول'),
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
