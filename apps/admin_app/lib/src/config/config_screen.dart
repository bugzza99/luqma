import 'dart:async';

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
  static const commissionKey = Key('config.commission');
  static const commissionAlertKey = Key('config.commissionAlert');
  static const saveCommissionKey = Key('config.saveCommission');
  static const unavailableKey = Key('config.unavailable');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(adminConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: AdminContent(
        child: LuqmaAsyncView(
          value: config,
          onRetry: () => ref.invalidate(adminConfigProvider),
          builder: (context, value) =>
              _ConfigForm(key: ObjectKey(value), initial: value),
        ),
      ),
    );
  }
}

class _ConfigForm extends ConsumerStatefulWidget {
  const _ConfigForm({super.key, required this.initial});

  final Map<String, Object> initial;

  @override
  ConsumerState<_ConfigForm> createState() => _ConfigFormState();
}

class _ConfigFormState extends ConsumerState<_ConfigForm> {
  late final _acceptTimeout = _intField(
    'accept_timeout_minutes',
    LuqmaConfig.defaults.acceptTimeoutMinutes,
  );
  late final _push = _intField(
    'marketing_push_per_week',
    LuqmaConfig.defaults.marketingPushPerWeek,
  );
  late final _rejection = _intField(
    'rejection_ban_threshold',
    LuqmaConfig.defaults.rejectionBanThreshold,
  );
  late final _minRatings = _intField(
    'min_ratings_to_show',
    LuqmaConfig.defaults.minRatingsToShow,
  );
  late final _feeMin = _moneyField(
    'delivery_fee_min',
    LuqmaConfig.defaults.deliveryFeeMin,
  );
  late final _feeMax = _moneyField(
    'delivery_fee_max',
    LuqmaConfig.defaults.deliveryFeeMax,
  );
  late final _splash = _intField(
    'splash_min_millis',
    LuqmaConfig.defaults.splashMinMillis,
  );
  late final _customerMinVersion = _appVersionField(
    'customer_min_supported_version',
  );
  late final _merchantMinVersion = _appVersionField(
    'merchant_min_supported_version',
  );
  late final _adminMinVersion = _appVersionField('admin_min_supported_version');
  late final _customerUpdateUrl = _appUrlField(
    'customer_update_url',
    LuqmaApp.customer,
  );
  late final _merchantUpdateUrl = _appUrlField(
    'merchant_update_url',
    LuqmaApp.merchant,
  );
  late final _adminUpdateUrl = _appUrlField('admin_update_url', LuqmaApp.admin);
  late final _updateMessage = _textField('update_message');
  late final _commission = TextEditingController(
    text: _percentText(widget.initial['default_commission_percent']),
  );
  late final _commissionAlert = _intField(
    'commission_alert_pounds',
    LuqmaConfig.defaults.commissionAlertPounds,
  );
  final _errors = <TextEditingController, String?>{};
  bool _savingCommission = false;

  static String _percentText(Object? value) {
    final p = value is num ? value.toDouble() : LuqmaConfig.defaults.defaultCommissionPercent;
    return p == p.roundToDouble() ? p.toInt().toString() : p.toString();
  }
  late final _whatsapp = _textField('support_whatsapp');

  bool _busy = false;

  // Each field falls back to the compiled-in default when the key is absent from the
  // table — the admin sees the full current state, not a form of blanks to guess at.
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

  TextEditingController _appVersionField(String key) {
    final value = widget.initial[key];
    final legacy = widget.initial['min_supported_version'];
    return TextEditingController(
      text: value is String
          ? value
          : legacy is String
          ? legacy
          : '',
    );
  }

  TextEditingController _appUrlField(String key, LuqmaApp app) {
    final value = widget.initial[key];
    return TextEditingController(
      text: value is String ? value : LuqmaConfig.compiledUpdateUrls[app] ?? '',
    );
  }

  @override
  void dispose() {
    for (final c in [
      _acceptTimeout,
      _push,
      _rejection,
      _minRatings,
      _feeMin,
      _feeMax,
      _splash,
      _customerMinVersion,
      _merchantMinVersion,
      _adminMinVersion,
      _customerUpdateUrl,
      _merchantUpdateUrl,
      _adminUpdateUrl,
      _updateMessage,
      _whatsapp,
      _commission,
      _commissionAlert,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// An integer field that refuses a blank or a non-integer. Nothing is rounded.
  String? _validInt(String key, TextEditingController c) {
    final value = _int(c);
    final bounds = configBounds[key]!;
    final error = value == null || value < bounds.min || value > bounds.max
        ? 'اكتب رقم من ${bounds.min} لـ ${bounds.max}'
        : null;
    _errors[c] = error;
    return error;
  }

  /// A number typed on an Arabic keyboard is a number: `٥` is 5.
  static int? _int(TextEditingController c) =>
      int.tryParse(ArabicDigits.fold(c.text).trim());

  /// A money field, through the same reader the menu editor uses — refused rather than
  /// rounded, so a fee the app cannot read exactly is not saved.
  String? _validMoney(String key, TextEditingController c) {
    final text = c.text.trim();
    final value = Money.parse(text);
    final bounds = configBounds[key]!;
    final error = value == null || value < bounds.min || value > bounds.max
        ? 'اكتب سعر صحيح'
        : null;
    _errors[c] = error;
    return error;
  }

  Future<void> _save() async {
    if (!_valid()) return;

    setState(() => _busy = true);
    final result = await ref.read(configActionsProvider.notifier).save({
      // Phase 0 containment: these controls stay visible so an operator knows they were
      // considered, but they are not product capabilities yet and must not be written
      // into the control plane as if changing them changed the apps.
      'accept_timeout_minutes': _int(_acceptTimeout)!,
      // It was greyed out as «غير متاح في الإصدار الحالي» from before a sender existed, and
      // left so after marketing pushes started working — the owner could not change it.
      'marketing_push_per_week': _int(_push)!,
      'rejection_ban_threshold': _int(_rejection)!,
      'min_ratings_to_show': _int(_minRatings)!,
      'delivery_fee_min': Money.parse(_feeMin.text.trim())!,
      'delivery_fee_max': Money.parse(_feeMax.text.trim())!,
      'splash_min_millis': _int(_splash)!,
      'customer_min_supported_version': _customerMinVersion.text.trim(),
      'merchant_min_supported_version': _merchantMinVersion.text.trim(),
      'admin_min_supported_version': _adminMinVersion.text.trim(),
      'customer_update_url': _customerUpdateUrl.text.trim(),
      'merchant_update_url': _merchantUpdateUrl.text.trim(),
      'admin_update_url': _adminUpdateUrl.text.trim(),
      'update_message': _updateMessage.text.trim(),
      'support_whatsapp': _whatsapp.text.trim(),
    });
    if (!mounted) return;
    setState(() => _busy = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          Err(:final failure) => _sentence(failure),
          _ => 'اتحفظت الإعدادات',
        }),
      ),
    );
  }

  /// The one commission rate and the alert, saved on their own: changing the rate moves
  /// every shop that follows it, which is a bigger act than a timeout, and is confirmed.
  Future<void> _saveCommission() async {
    final percent = double.tryParse(ArabicDigits.fold(_commission.text).trim());
    final alert = _int(_commissionAlert);
    setState(() {
      _errors[_commission] =
          percent == null || percent < 0 || percent > 50 ? 'اكتب نسبة من 0 لـ 50' : null;
      _errors[_commissionAlert] = alert == null || alert < 0 ? 'اكتب مبلغ بالجنيه' : null;
    });
    if (_errors[_commission] != null || _errors[_commissionAlert] != null) return;

    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('النسبة الموحّدة'),
        content: Text(
          'كل المحلات اللي بتتبع النسبة الموحّدة هتتحاسب بـ ${_commission.text.trim()}% '
          'من الأوردر الجاي. المحلات اللي ليها نسبة خاصة مش هتتغير.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('احفظ'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() => _savingCommission = true);
    final result = await ref
        .read(configRepositoryProvider)
        .setCommissionPolicy(percent: percent!, alertPounds: alert!);
    if (!mounted) return;
    setState(() => _savingCommission = false);
    unawaited(ref.read(appConfigProvider.notifier).refresh());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          Ok(:final value) => 'اتحفظت العمولة — اتغيّرت على $value محل',
          Err(:final failure) => _sentence(failure),
        }),
      ),
    );
  }

  String _sentence(Failure failure) => switch (failure) {
    OfflineFailure() => 'مفيش نت — جرّب تاني.',
    PermissionFailure() => 'مش مسموح ليك تعدّل الإعدادات.',
    ValidationFailure() => 'قيمة غير صحيحة — راجع الخانات.',
    _ => 'مقدرناش نحفظ. جرّب تاني.',
  };

  bool _valid() {
    final errors = [
      _validInt('accept_timeout_minutes', _acceptTimeout),
      _validInt('rejection_ban_threshold', _rejection),
      _validInt('min_ratings_to_show', _minRatings),
      _validMoney('delivery_fee_min', _feeMin),
      _validMoney('delivery_fee_max', _feeMax),
      _validInt('splash_min_millis', _splash),
    ];
    final pushError = _validInt('marketing_push_per_week', _push);
    // Redrawn so each error shows beside its own field, not only in one far-away message.
    setState(() {});
    if (errors.any((e) => e != null) || pushError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('في خانة فيها رقم غلط — مكتوب تحتها.')),
      );
      return false;
    }
    // A minimum nobody can install walls every phone on that app out, with no way past
    // it — the gate is un-bypassable on purpose. All three apps share one version, so this
    // build's own is the newest that exists. The admin field is the one that matters most:
    // set above this build, it locks out the only app that could put it back.
    //
    // `appVersionProvider` reads like `0.9.0 (10)`; the version is the part before the
    // space. A build that cannot say what it is refuses nothing on a guess.
    final existing = ref.read(appVersionProvider).split(' ').first;
    for (final field in [_customerMinVersion, _merchantMinVersion, _adminMinVersion]) {
      if (LuqmaConfig.versionExceeds(field.text.trim(), existing)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'أحدث نسخة موجودة $existing. لو حطيت رقم أعلى منها، التطبيق هيقفل '
              'في وش كل اللي بيستخدموه ومفيش طريقة يتفتح غير بتحديث مش موجود.',
            ),
          ),
        );
        return false;
      }
    }

    // The pair is validated together: a max below a min describes no valid fee at all.
    if (Money.parse(_feeMin.text.trim())! > Money.parse(_feeMax.text.trim())!) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أقصى رسوم أقل من أقل رسوم — راجعهم.')),
      );
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    // SingleChildScrollView, not ListView: the whole form is built eagerly so every
    // field is reachable, and the save button is not hidden behind lazy construction.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A16 warning banner: modifying dynamic configuration impacts all running apps.
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.sm,
            ),
            decoration: BoxDecoration(
              color: colors.danger.withValues(alpha: 0.08),
              borderRadius: Radii.cardAll,
              border: Border.all(color: colors.danger.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: Sizes.iconSm,
                  color: colors.danger,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    // True as written: `admin_set_config` stamps an `audit_log` row with the actor. And
                    // not "at once" — the first draft said so, and a phone keeps the old value
                    // until the app starts or comes back to the foreground.
                    // Said in words rather than by naming the table.
                    'أي تعديل هنا بيوصل للتطبيقات أول ما تتفتح أو ترجع لها، وبيتسجّل مين عدّله.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.lg),
          _Section(
            title: 'العمولة',
            children: [
              ListTile(
                title: const Text('النسبة الموحّدة لكل المحلات (%)'),
                subtitle: const Text(
                  'على أكل كل أوردر يتسلّم، مش على التوصيل. المحل اللي ليه نسبة خاصة '
                  'بتتغير من صفحته.',
                ),
                trailing: SizedBox(
                  width: 110,
                  child: TextField(
                    key: ConfigScreen.commissionKey,
                    controller: _commission,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩.,]')),
                    ],
                    decoration: InputDecoration(
                      isDense: true,
                      errorText: _errors[_commission],
                      errorMaxLines: 2,
                    ),
                  ),
                ),
              ),
              _IntTile(
                fieldKey: ConfigScreen.commissionAlertKey,
                controller: _commissionAlert,
                label: 'نبّهني لما المستحق على محل يعدّي (جنيه)',
                subtitle: 'والمحل نفسه بيوصله تنبيه بالمبلغ.',
                errorText: _errors[_commissionAlert],
              ),
              Padding(
                padding: const EdgeInsets.all(Space.md),
                child: FilledButton(
                  key: ConfigScreen.saveCommissionKey,
                  onPressed: _savingCommission ? null : _saveCommission,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(Sizes.minTarget),
                  ),
                  child: const Text('احفظ العمولة'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          // Four switches that could not be switched, each titled with a database key,
          // used to open this screen. They are one sentence now: what does not exist yet.
          Text(
            'لسه مش شغالة: رسائل التأكيد على الموبايل، إعلانات جوجل، التعليقات العامة، '
            'الدفع أونلاين.',
            key: ConfigScreen.unavailableKey,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.lg),
          _Section(
            title: 'الحدود',
            children: [
              _IntTile(
                controller: _acceptTimeout,
                label: 'مهلة قبول الطلب (دقايق)',
                errorText: _errors[_acceptTimeout],
              ),
              _IntTile(
                fieldKey: ConfigScreen.pushKey,
                controller: _push,
                label: 'إشعارات العروض للعملاء في الأسبوع',
                subtitle: 'لكل المدينة مع بعض، مش لكل محل.',
                errorText: _errors[_push],
              ),
              _IntTile(
                controller: _rejection,
                label: 'الرفض قبل الحظر',
                errorText: _errors[_rejection],
              ),
              _IntTile(
                controller: _minRatings,
                label: 'أقل تقييمات لعرض النجوم',
                subtitle: 'نجوم المحل مش بتظهر غير لما ياخد العدد ده من التقييمات.',
                errorText: _errors[_minRatings],
              ),
              _IntTile(
                controller: _feeMin,
                label: 'أقل رسوم توصيل (جنيه)',
                errorText: _errors[_feeMin],
              ),
              _IntTile(
                controller: _feeMax,
                label: 'أقصى رسوم توصيل (جنيه)',
                errorText: _errors[_feeMax],
              ),
              _IntTile(
                controller: _splash,
                label: 'مدة الشاشة الافتتاحية (مللي ثانية)',
                errorText: _errors[_splash],
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          _Section(
            title: 'الدعم والتحديث',
            children: [
              _TextTile(
                controller: _whatsapp,
                label: 'رقم واتساب الدعم',
                fieldKey: ConfigScreen.whatsappKey,
              ),
              _TextTile(
                controller: _customerMinVersion,
                label: 'أقل نسخة مدعومة — العميل (مثال 1.4.0)',
              ),
              _TextTile(
                controller: _merchantMinVersion,
                label: 'أقل نسخة مدعومة — التاجر (مثال 1.4.0)',
              ),
              _TextTile(
                controller: _adminMinVersion,
                label: 'أقل نسخة مدعومة — الأدمن (مثال 1.4.0)',
              ),
              _TextTile(
                controller: _customerUpdateUrl,
                label: 'رابط تحديث تطبيق العميل (اختياري)',
              ),
              _TextTile(
                controller: _merchantUpdateUrl,
                label: 'رابط تحديث تطبيق التاجر (اختياري)',
              ),
              _TextTile(
                controller: _adminUpdateUrl,
                label: 'رابط تحديث تطبيق الأدمن (اختياري)',
              ),
              _TextTile(
                controller: _updateMessage,
                label: 'رسالة التحديث',
                maxLines: 3,
              ),
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
        Padding(
          padding: const EdgeInsets.only(
            left: Space.xs,
            right: Space.xs,
            bottom: Space.xs,
          ),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textSecondary,
            ),
          ),
        ),
        // Material rather than a coloured Container: ListTile paints its ink on the
        // nearest Material ancestor, and a DecoratedBox in between hides it.
        Material(
          color: colors.card,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: Radii.cardAll,
            side: BorderSide(color: colors.hairline),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, thickness: 1, color: colors.hairline),
                children[i],
              ],
            ],
          ),
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
    this.subtitle,
    this.errorText,
  });

  final TextEditingController controller;
  final String label;
  final Key? fieldKey;
  final String? subtitle;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return ListTile(
      title: Text(label),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
      trailing: SizedBox(
        width: 140,
        child: TextField(
          key: fieldKey,
          controller: controller,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩.,]')),
          ],
          // The title is the field's name for a screen reader too, not only on screen.
          decoration: InputDecoration(
            isDense: true,
            semanticCounterText: label,
            errorText: errorText,
            errorMaxLines: 2,
          ),
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
    // The label is the field's own, so a screen reader announces it on the field rather
    // than as loose text above it (QA review 2026-09-19).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
      child: TextField(
        key: fieldKey,
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, alignLabelWithHint: maxLines > 1),
      ),
    );
  }
}
