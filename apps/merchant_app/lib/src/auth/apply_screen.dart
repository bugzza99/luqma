import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// The way in for prospective partners who do not have an account yet.
///
/// Somebody with no account looks at the sign-in screen and has nowhere to go. This page
/// lets them leave their name, phone, and role details.
///
/// What it does, since 2026-09-18: it makes the applicant an ordinary phone account — the
/// same one a customer has, and one that carries **no privileges of any kind** — and files
/// the application against it. The owner reads the application in AdminApp, telephones, and
/// approves; approval is what mints the `staff` row and the shop.
///
/// Before that, this form asked for no password at all, so an approved merchant had nothing
/// to sign in with — which is exactly what happened to the first one.
class ApplyScreen extends ConsumerStatefulWidget {
  const ApplyScreen({super.key});

  static const nameKey = Key('apply.name');
  static const phoneKey = Key('apply.phone');
  static const passwordKey = Key('apply.password');
  static const confirmKey = Key('apply.confirm');
  static const noteKey = Key('apply.note');
  static const submitKey = Key('apply.submit');
  static const errorKey = Key('apply.error');
  static const successKey = Key('apply.success');
  static const backButtonKey = Key('apply.back');

  @override
  ConsumerState<ApplyScreen> createState() => _ApplyScreenState();
}

class _ApplyScreenState extends ConsumerState<ApplyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _note = TextEditingController();

  StaffApplicationKind _kind = StaffApplicationKind.courier;
  bool _busy = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    // The account first: an application with nothing to approve into is what left the first
    // merchant approved and non-existent. It carries no privileges until an admin approves.
    final auth = ref.read(authServiceProvider);
    var account = await auth.signUpWithPhone(
      phone: _phone.text,
      password: _password.text,
      name: _name.text,
    );
    if (account case Err(failure: PhoneTakenFailure())) {
      // The same person, already signed up here or as a customer: their password lets them
      // prove it. A wrong one is not an account we may attach an application to.
      account = await auth.signInWithPhone(
        phone: _phone.text,
        password: _password.text,
      );
      if (account is Err) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = 'الرقم ده عنده حساب بالفعل. اكتب كلمة السر بتاعته أو استخدم رقم تاني.';
        });
        return;
      }
    }
    if (account case Err(failure: final failure)) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure is OfflineFailure
            ? 'مفيش اتصال بالإنترنت — اتأكد من الشبكة وجرّب تاني'
            : 'مقدرناش نعمل الحساب. جرّب تاني.';
      });
      return;
    }

    final repo = ref.read(staffApplicationRepositoryProvider);
    final result = await repo.apply(
      applicantUid: account.valueOrNull?.uid,
      kind: _kind,
      name: _name.text,
      phone: _phone.text,
      note: _note.text,
    );

    if (!mounted) return;

    setState(() {
      _busy = false;
      switch (result) {
        case Ok():
          _submitted = true;
          _error = null;
        case Err(failure: OfflineFailure()):
          _error = 'مفيش اتصال بالإنترنت — اتأكد من الشبكة وجرّب تاني';
        case Err(failure: AlreadyAppliedFailure()):
          _error = 'في طلب متقدم بالرقم ده بالفعل — حد من الإدارة هيكلمك';
        case Err():
          _error = 'حصل خطأ — جرّب تاني';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('طلب انضمام'),
        leading: Navigator.of(context).canPop()
            ? IconButton(
                tooltip: 'رجوع',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: _submitted ? _buildSuccess(context) : _buildForm(context),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    final noteConfig = switch (_kind) {
      StaffApplicationKind.courier => (
          label: 'المناطق اللي بتغطيها',
          hint: 'اكتب المناطق أو الأحياء اللي تقدر توصل فيها',
        ),
      StaffApplicationKind.restaurant => (
          label: 'مكان المطعم ومواعيد العمل',
          hint: 'اكتب عنوان المطعم ومواعيد الفتح والقفل',
        ),
      StaffApplicationKind.homeKitchen => (
          label: 'مكان المطبخ ومواعيد العمل',
          hint: 'اكتب منطقتك ومواعيد تجهيز الأكل',
        ),
    };

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: LuqmaLockup(logo: LuqmaLogo.mark, height: 64)),
          const SizedBox(height: Space.lg),
          Text(
            'انضم لشبكة لقمة',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.xs),
          Text(
            'سجل بياناتك وكلمة سر، وهنتواصل معاك تليفونياً. أول ما نوافق تدخل بنفس الرقم وكلمة السر.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.xl),
          Text(
            'إنت مندوب توصيل، ولا مطعم، ولا أكل بيتي؟',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: Space.sm),
          SegmentedButton<StaffApplicationKind>(
            segments: const [
              ButtonSegment(
                value: StaffApplicationKind.courier,
                label: Text('مندوب توصيل', key: Key('apply.kind.courier')),
              ),
              ButtonSegment(
                value: StaffApplicationKind.restaurant,
                label: Text('مطعم', key: Key('apply.kind.restaurant')),
              ),
              ButtonSegment(
                value: StaffApplicationKind.homeKitchen,
                label: Text('أكل بيتي', key: Key('apply.kind.homeKitchen')),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (selected) {
              setState(() {
                _kind = selected.first;
              });
            },
          ),
          const SizedBox(height: Space.lg),
          TextFormField(
            key: ApplyScreen.nameKey,
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'الاسم',
              hintText: 'اكتب اسمك بالكامل',
            ),
            validator: (v) {
              final trimmed = (v ?? '').trim();
              if (trimmed.length < 2) return 'اكتب اسمك (حرفين على الأقل)';
              if (trimmed.length > 80) return 'الاسم طويل زيادة (بحد أقصى 80 حرف)';
              return null;
            },
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            key: ApplyScreen.phoneKey,
            controller: _phone,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'رقم الموبايل',
              hintText: '01012345678',
            ),
            validator: (v) => Phone.isValidEgyptianMobile(v ?? '')
                ? null
                : 'اكتب رقم موبايل مصري صحيح',
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            key: ApplyScreen.passwordKey,
            controller: _password,
            obscureText: true,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'كلمة السر',
              hintText: '8 حروف على الأقل',
            ),
            validator: (v) =>
                (v ?? '').trim().length < 8 ? 'كلمة السر 8 حروف على الأقل' : null,
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            key: ApplyScreen.confirmKey,
            controller: _confirm,
            obscureText: true,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'اكتب كلمة السر تاني'),
            validator: (v) =>
                (v ?? '').trim() == _password.text.trim() ? null : 'كلمتي السر مش متطابقتين',
          ),
          const SizedBox(height: Space.md),
          TextFormField(
            key: ApplyScreen.noteKey,
            controller: _note,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: noteConfig.label,
              hintText: noteConfig.hint,
              alignLabelWithHint: true,
            ),
            validator: (v) {
              final trimmed = (v ?? '').trim();
              if (trimmed.length > 500) {
                return 'الكلام طويل زيادة (بحد أقصى 500 حرف)';
              }
              return null;
            },
          ),
          const SizedBox(height: Space.md),
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: Radii.cardAll,
              border: Border.all(color: colors.hairline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 20, color: colors.brand),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    'الحساب اللي بتعمله هنا من غير أي صلاحيات لحد ما نوافق. إدارة لقمة هتتصل بيك تليفونياً لمراجعة البيانات، وبعدها الحساب يتفعّل وتدخل بنفس الرقم وكلمة السر.',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.md),
            Text(
              _error!,
              key: ApplyScreen.errorKey,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.danger),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: Space.xl),
          FilledButton(
            key: ApplyScreen.submitKey,
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: Text(_busy ? 'لحظة…' : 'إرسال الطلب'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Column(
      key: ApplyScreen.successKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle_outline, size: 72, color: colors.brand),
        const SizedBox(height: Space.lg),
        Text(
          'وصلنا طلبك!',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Space.md),
        Text(
          'سجلنا بياناتك وعملنا حسابك بالرقم وكلمة السر اللي كتبتهم. إدارة لقمة هتتصل بيك تليفونياً في أقرب وقت، وأول ما نوافق تدخل بنفس الرقم وكلمة السر. لحد ساعتها الحساب من غير صلاحيات.',
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Space.xxl),
        FilledButton(
          key: ApplyScreen.backButtonKey,
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
          child: const Text('الرجوع لصفحة الدخول'),
        ),
      ],
    );
  }
}
