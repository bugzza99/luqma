import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';
import 'config_controller.dart';

/// The control plane, edited from one screen.
///
/// The one place where a typo reaches every phone in the city at once, which is why the
/// form is explicit about units (piastres, milliseconds) rather than trusting somebody to
/// remember. Saving goes through `admin_set_config`, so the change is audited and the
/// customer's realtime config arrives at once.
class ConfigScreen extends ConsumerWidget {
  const ConfigScreen({super.key});

  static const saveKey = Key('config.save');
  static const whatsappKey = Key('config.whatsapp');
  static const pushKey = Key('config.push');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(adminConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: AdminContent(
        child: LuqmaAsyncView(
          value: config,
          onRetry: () => ref.invalidate(adminConfigProvider),
          builder: (context, value) => _ConfigForm(initial: value)
        ),
      ),
    );
  }
}

class _ConfigForm extends ConsumerStatefulWidget {
  const _ConfigForm({required this.initial});

  final Map<String, Object> initial;

  @override
  ConsumerState<_ConfigForm> createState() => _ConfigFormState();
}

class _ConfigFormState extends ConsumerState<_ConfigForm> {
  late bool _otp = _flag('otp_enabled', LuqmaConfig.defaults.otpEnabled);
  late bool _admob = _flag('admob_enabled', LuqmaConfig.defaults.admobEnabled);
  late bool _publicComments =
      _flag('public_comments_enabled', LuqmaConfig.defaults.publicCommentsEnabled);
  late bool _onlinePayment =
      _flag('online_payment_enabled', LuqmaConfig.defaults.onlinePaymentEnabled);

  late final _acceptTimeout = _intField(
      'accept_timeout_minutes', LuqmaConfig.defaults.acceptTimeoutMinutes);
  late final _push = _intField(
      'marketing_push_per_week', LuqmaConfig.defaults.marketingPushPerWeek);
  late final _rejection = _intField(
      'rejection_ban_threshold', LuqmaConfig.defaults.rejectionBanThreshold);
  late final _minRatings = _intField(
      'min_ratings_to_show', LuqmaConfig.defaults.minRatingsToShow);
  late final _feeMin = _moneyField(
      'delivery_fee_min', LuqmaConfig.defaults.deliveryFeeMin);
  late final _feeMax = _moneyField(
      'delivery_fee_max', LuqmaConfig.defaults.deliveryFeeMax);
  late final _splash = _intField(
      'splash_min_millis', LuqmaConfig.defaults.splashMinMillis);
  late final _minVersion = _textField('min_supported_version');
  late final _updateMessage = _textField('update_message');
  late final _whatsapp = _textField('support_whatsapp');

  bool _busy = false;

  // Each field falls back to the compiled-in default when the key is absent from the
  // table — the admin sees the full current state, not a form of blanks to guess at.
  bool _flag(String key, bool fallback) =>
      widget.initial[key] is bool ? widget.initial[key] as bool : fallback;

  TextEditingController _intField(String key, int fallback) {
    final value = widget.initial[key];
    return TextEditingController(
      text: (value is num ? value.toInt() : fallback).toString(),
    );
  }

  TextEditingController _moneyField(String key, int fallback) {
    final value = widget.initial[key];
    return TextEditingController(
      text: Money.format(value is num ? value.toInt() : fallback),
    );
  }

  TextEditingController _textField(String key) => TextEditingController(
        text: widget.initial[key] is String ? widget.initial[key] as String : '',
      );

  @override
  void dispose() {
    for (final c in [
      _acceptTimeout, _push, _rejection, _minRatings, _feeMin, _feeMax,
      _splash, _minVersion, _updateMessage, _whatsapp,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// An integer field that refuses a blank or a non-integer. Nothing is rounded.
  String? _validInt(TextEditingController c) {
    final text = c.text.trim();
    if (text.isEmpty || int.tryParse(text) == null) return 'اكتب رقم صحيح';
    return null;
  }

  /// A money field, through the same reader the menu editor uses — refused rather than
  /// rounded, so a fee the app cannot read exactly is not saved.
  String? _validMoney(TextEditingController c) {
    final text = c.text.trim();
    if (text.isEmpty || Money.parse(text) == null) return 'اكتب سعر صحيح';
    return null;
  }

  Future<void> _save() async {
    if (!_valid()) return;

    setState(() => _busy = true);
    final result = await ref.read(configActionsProvider.notifier).save({
      'otp_enabled': _otp,
      'admob_enabled': _admob,
      'public_comments_enabled': _publicComments,
      'online_payment_enabled': _onlinePayment,
      'accept_timeout_minutes': int.parse(_acceptTimeout.text.trim()),
      'marketing_push_per_week': int.parse(_push.text.trim()),
      'rejection_ban_threshold': int.parse(_rejection.text.trim()),
      'min_ratings_to_show': int.parse(_minRatings.text.trim()),
      'delivery_fee_min': Money.parse(_feeMin.text.trim())!,
      'delivery_fee_max': Money.parse(_feeMax.text.trim())!,
      'splash_min_millis': int.parse(_splash.text.trim()),
      'min_supported_version': _minVersion.text.trim(),
      'update_message': _updateMessage.text.trim(),
      'support_whatsapp': _whatsapp.text.trim(),
    });
    if (!mounted) return;
    setState(() => _busy = false);

    if (result case Err(:final failure)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_sentence(failure))),
      );
    }
  }

  String _sentence(Failure failure) => switch (failure) {
        OfflineFailure() => 'مفيش نت — جرّب تاني.',
        PermissionFailure() => 'مش مسموح ليك تعدّل الإعدادات.',
        _ => 'مقدرناش نحفظ. جرّب تاني.',
      };

  bool _valid() {
    final errors = [
      _validInt(_acceptTimeout),
      _validInt(_push),
      _validInt(_rejection),
      _validInt(_minRatings),
      _validMoney(_feeMin),
      _validMoney(_feeMax),
      _validInt(_splash),
    ];
    if (errors.any((e) => e != null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('في خانة فيها رقم غلط — راجعها.')),
      );
      return false;
    }
    // The pair is validated together: a max below a min describes no valid fee at all.
    if (Money.parse(_feeMin.text.trim())! >
        Money.parse(_feeMax.text.trim())!) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أقصى رسوم أقل من أقل رسوم — راجعهم.')),
      );
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // SingleChildScrollView, not ListView: the whole form is built eagerly so every
    // field is reachable, and the save button is not hidden behind lazy construction.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        _Section(
          title: 'الميزات',
          children: [
            SwitchListTile(
              title: const Text('تفعيل الـ OTP'),
              subtitle: const Text('التحقق بالرقم عند الطلب'),
              value: _otp,
              onChanged: (v) => setState(() => _otp = v),
            ),
            SwitchListTile(
              title: const Text('إعلانات AdMob'),
              value: _admob,
              onChanged: (v) => setState(() => _admob = v),
            ),
            SwitchListTile(
              title: const Text('التعليقات العامة'),
              value: _publicComments,
              onChanged: (v) => setState(() => _publicComments = v),
            ),
            SwitchListTile(
              title: const Text('الدفع أونلاين'),
              value: _onlinePayment,
              onChanged: (v) => setState(() => _onlinePayment = v),
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        _Section(
          title: 'الحدود',
          children: [
            _IntTile(controller: _acceptTimeout, label: 'مهلة قبول الطلب (دقايق)'),
            _IntTile(fieldKey: ConfigScreen.pushKey, controller: _push, label: 'إشعارات التسويق أسبوعيًا'),
            _IntTile(controller: _rejection, label: 'الرفض قبل الحظر'),
            _IntTile(controller: _minRatings, label: 'أقل تقييمات لعرض النجوم'),
            _IntTile(controller: _feeMin, label: 'أقل رسوم توصيل (جنيه)'),
            _IntTile(controller: _feeMax, label: 'أقصى رسوم توصيل (جنيه)'),
            _IntTile(controller: _splash, label: 'مدة الشاشة الافتتاحية (مللي ثانية)'),
          ],
        ),
        const SizedBox(height: Space.lg),
        _Section(
          title: 'الدعم والتحديث',
          children: [
            _TextTile(controller: _whatsapp, label: 'رقم واتساب الدعم', fieldKey: ConfigScreen.whatsappKey),
            _TextTile(controller: _minVersion, label: 'أقل نسخة مدعومة (مثال 1.4.0)'),
            _TextTile(controller: _updateMessage, label: 'رسالة التحديث', maxLines: 3),
          ],
        ),
        const SizedBox(height: Space.xl),
        FilledButton.icon(
          key: ConfigScreen.saveKey,
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.save_outlined, size: Sizes.iconSm),
          label: Text(_busy ? 'جاري…' : 'احفظ الإعدادات'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(Sizes.minTarget),
          ),
        ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: Space.sm),
        // Material rather than a coloured Container: ListTile paints its ink on the
        // nearest Material ancestor, and a DecoratedBox in between hides it.
        Material(
          color: colors.card,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: Radii.cardAll,
            side: BorderSide(color: colors.hairline),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _IntTile extends StatelessWidget {
  const _IntTile({
    required this.controller,
    required this.label,
    this.fieldKey,
  });

  final TextEditingController controller;
  final String label;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: SizedBox(
        width: 140,
        child: TextField(
          key: fieldKey,
          controller: controller,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: const InputDecoration(isDense: true),
        ),
      ),
    );
  }
}

class _TextTile extends StatelessWidget {
  const _TextTile({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.fieldKey,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: TextField(
        key: fieldKey,
        controller: controller,
        maxLines: maxLines,
        decoration: const InputDecoration(isDense: true),
      ),
    );
  }
}
