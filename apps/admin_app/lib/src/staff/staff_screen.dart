import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';
import '../merchants/merchants_controller.dart';
import 'staff_controller.dart';

/// The platform's own accounts: admins, moderators, and the shops' owners and couriers.
///
/// Lists, deactivates, and — now that `create-staff-account` exists on the server —
/// creates. The create form asks for everything the function will check: an address,
/// a password to hand over in person, who this person is, and whose shop they answer
/// for when the scope is a merchant's.
class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  static const emptyKey = Key('staff.empty');
  static const toggleKey = Key('staff.toggle');
  static const createKey = Key('staff.create');
  static const submitKey = Key('staff.submit');

  static const _roles = {
    'admin': 'أدمن',
    'moderator': 'مشرف',
    'owner': 'صاحب مطعم',
    'courier': 'دليفري',
  };

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(staffListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الفريق'),
        actions: [
          IconButton(
            key: StaffScreen.createKey,
            tooltip: 'إضافة حساب',
            icon: const Icon(Icons.person_add_alt),
            onPressed: () => _showCreateDialog(context),
          ),
        ],
      ),
      body: AdminContent(
        child: LuqmaAsyncView(
          value: staff,
          onRetry: () => ref.invalidate(staffListProvider),
          empty: Center(
              key: StaffScreen.emptyKey,
              child: Text(
                'مفيش حسابات لسه.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).luqma.textSecondary,
                    ),
              ),
            ),
          isEmpty: (value) => value.isEmpty,
          builder: (context, value) => ListView.separated(
              padding: const EdgeInsets.all(Space.gutter),
              itemCount: value.length,
              separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
              itemBuilder: (context, i) => _StaffRow(
                member: value[i],
                onToggle: () => _toggle(context, ref, value[i]),
              ),
            )
        ),
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    StaffMember member,
  ) async {
    await ref
        .read(staffRepositoryProvider)
        .setActive(member.uid, active: !member.isActive);
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    // Captured before the await: after it, only this State's own members are safe.
    final messenger = ScaffoldMessenger.of(context);
    final created = await showDialog<Result<StaffMember>>(
      context: context,
      builder: (_) => const _CreateStaffDialog(),
    );
    if (!mounted || created == null) return;

    if (created is Ok<StaffMember>) {
      ref.invalidate(staffListProvider);
      messenger.showSnackBar(
        SnackBar(
            content:
                Text('اتعمل الحساب لـ ${created.value.name ?? created.value.uid}')),
      );
    } else if (created case Err(:final failure)) {
      messenger.showSnackBar(
        SnackBar(
          key: Key('staff.create-error'),
          content: Text(switch (failure) {
            EmailTakenFailure() => 'الإيميل ده متسجل قبل كده.',
            PermissionFailure() => 'مش مسموحلك تعمل حسابات.',
            ConflictFailure() => 'فيه معلومة ناقصة أو غلط.',
            OfflineFailure() => 'مفيش نت — جرّب تاني.',
            _ => 'معرفنش عمل الحساب. جرّب تاني.',
          }),
        ),
      );
    }
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({required this.member, required this.onToggle});

  final StaffMember member;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Container(
      padding: const EdgeInsets.all(Space.md),
      constraints: const BoxConstraints(minHeight: Sizes.minTarget),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name?.isNotEmpty == true ? member.name! : 'حساب',
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  '${StaffScreen._roles[member.role] ?? member.role} — '
                  '${member.scope == 'merchant' ? 'مطعم' : 'المنصة'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            key: StaffScreen.toggleKey,
            tooltip: member.isActive ? 'تعطيل' : 'تفعيل',
            icon: Icon(
              member.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline,
              color: member.isActive ? colors.danger : colors.brand,
            ),
            onPressed: onToggle,
          ),
        ],
      ),
    );
  }
}

/// The form the owner fills to mint one account.
///
/// Everything here is checked twice — once for shape on the phone, once for truth on
/// the server — because a password of three letters should not survive the trip.
class _CreateStaffDialog extends ConsumerStatefulWidget {
  const _CreateStaffDialog();

  @override
  ConsumerState<_CreateStaffDialog> createState() => _CreateStaffDialogState();
}

class _CreateStaffDialogState extends ConsumerState<_CreateStaffDialog> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  String _scope = 'merchant';
  String _role = 'owner';

  /// The shop this account belongs to, chosen from the list rather than typed.
  String? _merchantId;

  bool get _isMerchantScope => _scope == 'merchant';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final result = await ref.read(staffRepositoryProvider).createAccount(
          email: _email.text.trim(),
          password: _password.text,
          name: _name.text.trim(),
          scope: _scope,
          role: _role,
          merchantId: _isMerchantScope ? _merchantId : null,
        );
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('حساب جديد'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('staff.email'),
                controller: _email,
                decoration: const InputDecoration(labelText: 'الإيميل'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) =>
                    v != null && v.contains('@') ? null : 'اكتب إيميل صحيح',
              ),
              TextFormField(
                key: const Key('staff.password'),
                controller: _password,
                decoration:
                    const InputDecoration(labelText: 'كلمة السر (8 حروف على الأقل)'),
                obscureText: true,
                validator: (v) =>
                    v != null && v.length >= 8 ? null : '8 حروف على الأقل',
              ),
              TextFormField(
                key: const Key('staff.name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'الاسم'),
              ),
              DropdownButtonFormField<String>(
                key: const Key('staff.scope'),
                initialValue: _scope,
                decoration: const InputDecoration(labelText: 'النطاق'),
                items: const [
                  DropdownMenuItem(value: 'merchant', child: Text('مطعم')),
                  DropdownMenuItem(value: 'platform', child: Text('المنصة')),
                ],
                onChanged: (v) => setState(() {
                  _scope = v ?? _scope;
                  // The roles a platform account can carry are not the ones a shop's do.
                  _role = _isMerchantScope ? 'owner' : 'admin';
                }),
              ),
              DropdownButtonFormField<String>(
                key: const Key('staff.role'),
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'الدور'),
                items: _isMerchantScope
                    ? const [
                        DropdownMenuItem(value: 'owner', child: Text('صاحب مطعم')),
                        DropdownMenuItem(value: 'courier', child: Text('دليفري')),
                      ]
                    : const [
                        DropdownMenuItem(value: 'admin', child: Text('أدمن')),
                        DropdownMenuItem(value: 'moderator', child: Text('مشرف')),
                      ],
                onChanged: (v) => setState(() => _role = v ?? _role),
              ),
              // Picked by name, never typed. This was a free-text box labelled
              // "رقم المطعم (UUID)" — and no screen in this app shows a merchant's uuid
              // or lets anybody copy one, so there was no way to fill it correctly and
              // no merchant or courier account could be created at all.
              if (_isMerchantScope)
                _MerchantPicker(
                  selected: _merchantId,
                  onChanged: (id) => setState(() => _merchantId = id),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: StaffScreen.submitKey,
          onPressed: _submit,
          child: const Text('اعمل الحساب'),
        ),
      ],
    );
  }
}

/// Which shop an account belongs to, chosen from the list of them.
///
/// A dropdown of names rather than a box for a uuid. The owner knows their shops by
/// name — "مطعم الشاطئ" — and has no way to learn a uuid from anywhere in this app,
/// which is what made creating a merchant or courier account impossible.
///
/// A failed read of the merchants leaves the field disabled with a sentence rather than
/// an empty menu: a picker with nothing in it and no explanation reads as a shop list
/// that is genuinely empty, and the answer to that is to go and add a shop.
class _MerchantPicker extends ConsumerWidget {
  const _MerchantPicker({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchants = ref.watch(allMerchantsProvider);

    return switch (merchants) {
      AsyncValue(hasError: true) => const InputDecorator(
          decoration: InputDecoration(labelText: 'المطعم'),
          child: Text('مقدرناش نجيب المطاعم. اقفل وافتح تاني.'),
        ),
      AsyncValue(hasValue: true, :final value?) => DropdownButtonFormField<String>(
          key: const Key('staff.merchant'),
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'المطعم'),
          items: [
            for (final merchant in value)
              DropdownMenuItem(
                value: merchant.id,
                child: Text(merchant.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
          validator: (v) => v != null && v.isNotEmpty ? null : 'اختار المطعم',
        ),
      _ => const InputDecorator(
          decoration: InputDecoration(labelText: 'المطعم'),
          child: Text('بنجيب المطاعم…'),
        ),
    };
  }
}
