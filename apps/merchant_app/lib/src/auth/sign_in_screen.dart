import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import 'apply_screen.dart';

/// The way in.
///
/// A phone number and a password, the same pair a customer signs in with (2026-09-18).
/// It used to ask for an email only, because accounts were minted by the owner with one —
/// and the first real merchant was asked for an email and a password they had never had. A
/// partner now makes their own phone account when they apply; approval is what turns it
/// into a shop or a rider.
///
/// **An email still signs in**, and that is not politeness: every account
/// `create-staff-account` has ever minted — which is still how «الفريق» makes one — has a
/// real address and no phone identity at all. A phone-only field would lock every one of
/// them out of the app, silently, with «البيانات غلط». Which of the two arrived is decided
/// by the `@`, because that is the one thing an Egyptian mobile number can never contain.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  static const phoneKey = Key('signIn.phone');
  // The old key, kept so nothing that reaches for it breaks: it is the same field.
  static const emailKey = phoneKey;
  static const passwordKey = Key('signIn.password');
  static const submitKey = Key('signIn.submit');
  static const applyKey = Key('signIn.apply');
  static const errorKey = Key('signIn.error');

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final typed = _phone.text.trim();
    final auth = ref.read(authServiceProvider);
    final result = typed.contains('@')
        ? await auth.signInWithPassword(email: typed, password: _password.text)
        : await auth.signInWithPhone(phone: typed, password: _password.text);
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
                  // Not «دخول التاجر». The courier signs in on this same screen, and a
                  // rider who opens the app and reads «التاجر» across the top is being told
                  // they installed the wrong one. The app is «لقمة شريك» for that reason.
                  Text(
                    'دخول الشركاء',
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    // This said the only way in was to call the office. There is a way in
                    // now — the application just below — and a sentence telling somebody
                    // there is not sends them to the telephone instead of the button.
                    'مطعم، أكل بيتي، أو مندوب توصيل. لو لسه ملكش حساب، قدّم طلب وإحنا هنكلمك.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Space.xl),
                  TextFormField(
                    key: SignInScreen.phoneKey,
                    controller: _phone,
                    // Not `TextInputType.phone`: an address has to be typeable here too.
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'رقم الموبايل أو الإيميل',
                    ),
                    validator: (v) {
                      final typed = (v ?? '').trim();
                      if (typed.contains('@')) return null;
                      return Phone.isValidEgyptianMobile(typed)
                          ? null
                          : 'اكتب رقم موبايل صح أو الإيميل';
                    },
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
                  const SizedBox(height: Space.md),
                  TextButton(
                    key: SignInScreen.applyKey,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ApplyScreen(),
                      ),
                    ),
                    child: const Text('طلب انضمام جديد'),
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
