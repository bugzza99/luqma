import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// The way in for prospective partners who do not have an account yet.
///
/// Somebody with no account looks at the sign-in screen and has nowhere to go. This page
/// lets them leave their name, phone, and role details.
///
/// It is completely honest about what happens next: filling this form does NOT create an
/// account. The owner reviews it in AdminApp, telephones the applicant, and sets up the
/// account through the staff screen.
class ApplyScreen extends ConsumerStatefulWidget {
  const ApplyScreen({super.key});

  static const nameKey = Key('apply.name');
  static const phoneKey = Key('apply.phone');
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
  final _note = TextEditingController();

  StaffApplicationKind _kind = StaffApplicationKind.courier;
  bool _busy = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final repo = ref.read(staffApplicationRepositoryProvider);
    final result = await repo.apply(
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
            'سجل بياناتك وهنتواصل معاك تليفونياً لمراجعة الطلب.',
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
                    'تقديم الطلب مش معناه عمل حساب فوري. إدارة لقمة هتتصل بيك تليفونياً لمراجعة البيانات وتفعيل الحساب، ومش بيتعمل حساب من خلال الفورم دي.',
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
          'سجلنا بياناتك بنجاح. حد من إدارة لقمة هتتصل بيك تليفونياً في أقرب وقت لمراجعة التفاصيل. تقديم الطلب مش بيعمل حساب تلقائي، وإنشاء الحساب بيتم بعد التواصل.',
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
