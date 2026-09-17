import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/coupon.dart';
import '../models/merchant.dart';
import '../models/money.dart';
import '../result.dart';
import '../theme/dimens.dart';
import '../theme/colors.dart';
import '../l10n/money.dart';
import '../util/arabic_digits.dart';

/// A coupon's offer in the words a shop owner uses: «15% بحد أقصى 30 ج», «خصم 20 ج»,
/// «توصيل مجاني». [price] formats piastres the way the rest of the app does.
String couponOffer(Coupon coupon, String Function(int piastres) price) {
  return switch (coupon.type) {
    CouponType.percentage =>
      '${_percent(coupon.value)}% بحد أقصى ${price(coupon.maxDiscount ?? 0)}',
    CouponType.fixedAmount => 'خصم ${price(coupon.value)}',
    CouponType.freeDelivery => 'توصيل مجاني',
  };
}

/// Basis points as a percentage without a trailing zero: 1500 → 15, 1250 → 12.5.
String _percent(int basisPoints) {
  final whole = basisPoints ~/ 100;
  final rest = basisPoints % 100;
  if (rest == 0) return '$whole';
  return '$whole.${rest.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '')}';
}

/// The form a shop owner and an admin both make a coupon with.
///
/// Shared for the reason `MenuEditor` is: two copies of the rules for what a valid coupon
/// is would drift, and the one that drifted would be the one the server refuses. The
/// server is still the authority — this only saves a round trip for the obvious mistakes.
///
/// A shop passes [merchantId] and gets a coupon on that shop, paid for by the shop. An
/// admin passes [adminExtras] and chooses the shop (or the whole platform) and who pays.
class CouponForm extends StatefulWidget {
  const CouponForm({
    super.key,
    required this.cityId,
    required this.onSave,
    this.initial,
    this.merchantId,
    this.adminExtras = false,
    this.shops = const [],
    this.clock = DateTime.now,
  });

  /// Where "today" comes from for the date pickers. Screens pass `clockProvider`'s clock.
  final DateTime Function() clock;

  /// The city a platform-wide coupon belongs to. A shop coupon takes its shop's city.
  final String cityId;

  /// Editing this coupon, or null to make a new one.
  final Coupon? initial;

  /// The shop a shop owner's coupon belongs to. Ignored with [adminExtras].
  final String? merchantId;
  final bool adminExtras;

  /// The shops an admin can pick from, by name.
  final List<Merchant> shops;

  /// Saves the draft and answers null on success or the failure to explain.
  final Future<Failure?> Function(Coupon draft) onSave;

  static const codeKey = Key('coupon.code');
  static const typePercentKey = Key('coupon.type.percentage');
  static const typeFixedKey = Key('coupon.type.fixed');
  static const typeFreeDeliveryKey = Key('coupon.type.freeDelivery');
  static const valueKey = Key('coupon.value');
  static const maxDiscountKey = Key('coupon.maxDiscount');
  static const minOrderKey = Key('coupon.minOrder');
  static const firstOrderOnlyKey = Key('coupon.firstOrderOnly');
  static const perUserLimitKey = Key('coupon.perUserLimit');
  static const totalLimitKey = Key('coupon.totalLimit');
  static const validFromKey = Key('coupon.validFrom');
  static const validUntilKey = Key('coupon.validUntil');
  static const scopeKey = Key('coupon.scope');
  static const fundedByKey = Key('coupon.fundedBy');
  static const errorKey = Key('coupon.error');
  static const saveKey = Key('coupon.save');

  @override
  State<CouponForm> createState() => _CouponFormState();
}

class _CouponFormState extends State<CouponForm> {
  final _code = TextEditingController();
  final _value = TextEditingController();
  final _maxDiscount = TextEditingController();
  final _minOrder = TextEditingController();
  final _perUser = TextEditingController();
  final _total = TextEditingController();

  CouponType _type = CouponType.percentage;
  bool _firstOrderOnly = false;
  DateTime? _validFrom;
  DateTime? _validUntil;
  String? _shopId;
  CouponFunder _fundedBy = CouponFunder.merchant;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    if (widget.adminExtras) _fundedBy = CouponFunder.platform;
    if (c == null) return;
    _code.text = c.code;
    _type = c.type;
    _value.text = switch (c.type) {
      CouponType.percentage => _percent(c.value),
      CouponType.fixedAmount => _pounds(c.value),
      CouponType.freeDelivery => '',
    };
    if (c.maxDiscount != null) _maxDiscount.text = _pounds(c.maxDiscount!);
    if (c.minOrder > 0) _minOrder.text = _pounds(c.minOrder);
    if (c.perUserLimit > 0) _perUser.text = '${c.perUserLimit}';
    if (c.totalLimit > 0) _total.text = '${c.totalLimit}';
    _firstOrderOnly = c.firstOrderOnly;
    _validFrom = c.validFrom;
    _validUntil = c.validUntil;
    _shopId = c.merchantId;
    _fundedBy = c.fundedBy;
  }

  @override
  void dispose() {
    for (final c in [_code, _value, _maxDiscount, _minOrder, _perUser, _total]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _pounds(int piastres) =>
      piastres % 100 == 0 ? '${piastres ~/ 100}' : (piastres / 100).toStringAsFixed(2);

  /// A typed percentage into basis points: "15" → 1500, "12.5" → 1250. Null when it is not
  /// a number between 0 and 100 with at most two decimals.
  static int? _basisPoints(String raw) {
    final text = ArabicDigits.fold(raw)
        .replaceAll(ArabicDigits.decimalSeparator, '.')
        .replaceAll('%', '')
        .trim();
    if (!RegExp(r'^\d{1,3}(\.\d{1,2})?$').hasMatch(text)) return null;
    final bp = (double.parse(text) * 100).round();
    return bp > 0 && bp <= 10000 ? bp : null;
  }

  /// An optional count: empty is 0 («بلا حد»), anything else a whole number that fits the
  /// column — a Postgres `integer`, so above 2147483647 the save would fail on the server.
  static int? _count(String raw) {
    final text = ArabicDigits.fold(raw).trim();
    if (text.isEmpty) return 0;
    final value = int.tryParse(text);
    return value == null || value > 2147483647 ? null : value;
  }

  Future<void> _save() async {
    final (message, draft) = _validate();
    if (draft == null) {
      setState(() => _error = message);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    final failure = await widget.onSave(draft);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = switch (failure) {
        null => null,
        ConflictFailure() => 'الكود ده مستخدم قبل كده',
        OfflineFailure() => 'مفيش نت. جرّب تاني.',
        PermissionFailure() => 'مش مسموح لك تعمل ده.',
        ValidationFailure() => 'في حاجة مش مظبوطة في الكوبون. راجع الأرقام.',
        _ => 'مقدرناش نحفظ الكوبون. جرّب تاني.',
      };
    });
  }

  /// Either the sentence to show, or the draft to save.
  (String?, Coupon?) _validate() {
    final code = Coupon.normalizeCode(_code.text);
    if (code.isEmpty) return ('اكتب الكود', null);
    if (code.contains(' ')) return ('الكود مايكونش فيه مسافات', null);

    var value = 0;
    int? maxDiscount;
    switch (_type) {
      case CouponType.percentage:
        final bp = _basisPoints(_value.text);
        if (bp == null) return ('النسبة لازم تكون رقم من 1 لـ 100', null);
        value = bp;
        maxDiscount = Money.parse(_maxDiscount.text);
        if (maxDiscount == null || maxDiscount <= 0) {
          return ('النسبة لازم يكون ليها أقصى خصم', null);
        }
      case CouponType.fixedAmount:
        final amount = Money.parse(_value.text);
        if (amount == null || amount <= 0) return ('اكتب قيمة الخصم بالجنيه', null);
        value = amount;
      case CouponType.freeDelivery:
        value = 0;
    }

    var minOrder = 0;
    if (_minOrder.text.trim().isNotEmpty) {
      final parsed = Money.parse(_minOrder.text);
      if (parsed == null) return ('أقل طلب لازم يكون مبلغ بالجنيه', null);
      minOrder = parsed;
    }

    final perUser = _count(_perUser.text);
    final total = _count(_total.text);
    if (perUser == null || perUser < 0 || total == null || total < 0) {
      return ('عدد المرات لازم يكون رقم صحيح', null);
    }

    if (_validFrom != null && _validUntil != null && !_validUntil!.isAfter(_validFrom!)) {
      return ('تاريخ النهاية لازم يكون بعد البداية', null);
    }

    final merchantId = widget.adminExtras ? _shopId : widget.merchantId;
    final shopCity = widget.shops.where((m) => m.id == merchantId).firstOrNull?.cityId;

    return (
      null,
      Coupon(
        id: widget.initial?.id ?? '',
        code: code,
        cityId: widget.initial?.cityId ?? shopCity ?? widget.cityId,
        type: _type,
        value: value,
        maxDiscount: maxDiscount,
        minOrder: minOrder,
        merchantId: merchantId,
        firstOrderOnly: _firstOrderOnly,
        perUserLimit: perUser,
        totalLimit: total,
        usedCount: widget.initial?.usedCount ?? 0,
        isActive: widget.initial?.isActive ?? true,
        validFrom: _validFrom,
        validUntil: _validUntil,
        // Only an admin decides who pays; a shop's own coupon is always the shop's, and a
        // platform-wide coupon has no shop to charge.
        fundedBy: !widget.adminExtras
            ? CouponFunder.merchant
            : (merchantId == null ? CouponFunder.platform : _fundedBy),
        createdByUid: widget.initial?.createdByUid,
      ),
    );
  }

  Future<void> _pickDate({required bool from}) async {
    final now = widget.clock();
    final current = from ? _validFrom : _validUntil;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _validFrom = DateTime(picked.year, picked.month, picked.day);
      } else {
        // «لحد» a day means through the end of it.
        _validUntil = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final editingExisting = widget.initial != null;

    Widget field(
      Key key,
      TextEditingController controller,
      String label, {
      String? hint,
      TextInputType keyboard = TextInputType.number,
      TextDirection? direction,
    }) =>
        TextField(
          key: key,
          controller: controller,
          keyboardType: keyboard,
          textDirection: direction,
          decoration: InputDecoration(labelText: label, hintText: hint),
        );

    String dateLabel(DateTime? d, String empty) =>
        d == null ? empty : '${d.day}/${d.month}/${d.year}';

    return Padding(
      padding: const EdgeInsets.all(Space.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field(
            CouponForm.codeKey,
            _code,
            'الكود',
            hint: 'EID15',
            keyboard: TextInputType.text,
            direction: TextDirection.ltr,
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final (key, type, label) in const [
                (CouponForm.typePercentKey, CouponType.percentage, 'نسبة'),
                (CouponForm.typeFixedKey, CouponType.fixedAmount, 'مبلغ ثابت'),
                (CouponForm.typeFreeDeliveryKey, CouponType.freeDelivery, 'توصيل مجاني'),
              ])
                ChoiceChip(
                  key: key,
                  label: Text(label),
                  selected: _type == type,
                  onSelected: (_) => setState(() => _type = type),
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          if (_type == CouponType.percentage) ...[
            field(CouponForm.valueKey, _value, 'النسبة %', hint: '15'),
            const SizedBox(height: Space.md),
            field(CouponForm.maxDiscountKey, _maxDiscount, 'أقصى خصم بالجنيه', hint: '30'),
            const SizedBox(height: Space.md),
          ] else if (_type == CouponType.fixedAmount) ...[
            field(CouponForm.valueKey, _value, 'قيمة الخصم بالجنيه', hint: '20'),
            const SizedBox(height: Space.md),
          ],
          field(CouponForm.minOrderKey, _minOrder, 'أقل طلب بالجنيه (اختياري)'),
          const SizedBox(height: Space.md),
          SwitchListTile(
            key: CouponForm.firstOrderOnlyKey,
            contentPadding: EdgeInsets.zero,
            title: const Text('أول طلب بس'),
            subtitle: const Text('للعملاء اللي أول مرة يطلبوا'),
            value: _firstOrderOnly,
            onChanged: (v) => setState(() => _firstOrderOnly = v),
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Expanded(
                child: field(
                  CouponForm.perUserLimitKey,
                  _perUser,
                  'مرات لكل عميل',
                  hint: 'بلا حد',
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: field(
                  CouponForm.totalLimitKey,
                  _total,
                  'إجمالي المرات',
                  hint: 'بلا حد',
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: CouponForm.validFromKey,
                  onPressed: () => _pickDate(from: true),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(Sizes.minTarget),
                  ),
                  child: Text('من: ${dateLabel(_validFrom, 'دلوقتي')}'),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: OutlinedButton(
                  key: CouponForm.validUntilKey,
                  onPressed: () => _pickDate(from: false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(Sizes.minTarget),
                  ),
                  child: Text('لحد: ${dateLabel(_validUntil, 'مفتوح')}'),
                ),
              ),
            ],
          ),
          if (widget.adminExtras) ...[
            const SizedBox(height: Space.lg),
            DropdownButtonFormField<String?>(
              key: CouponForm.scopeKey,
              initialValue: _shopId,
              decoration: const InputDecoration(labelText: 'الكوبون على'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('المنصة كلها')),
                for (final shop in widget.shops)
                  DropdownMenuItem<String?>(value: shop.id, child: Text(shop.name)),
              ],
              // A coupon cannot move between shops once made — the server refuses it.
              onChanged: editingExisting ? null : (v) => setState(() => _shopId = v),
            ),
            const SizedBox(height: Space.md),
            DropdownButtonFormField<CouponFunder>(
              key: CouponForm.fundedByKey,
              initialValue: _shopId == null ? CouponFunder.platform : _fundedBy,
              decoration: const InputDecoration(labelText: 'مين بيدفع الخصم'),
              items: const [
                DropdownMenuItem(value: CouponFunder.platform, child: Text('المنصة')),
                DropdownMenuItem(value: CouponFunder.merchant, child: Text('المحل')),
              ],
              onChanged: _shopId == null
                  ? null
                  : (v) => setState(() => _fundedBy = v ?? CouponFunder.platform),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: Space.md),
            Text(
              _error!,
              key: CouponForm.errorKey,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.danger),
            ),
          ],
          const SizedBox(height: Space.lg),
          FilledButton(
            key: CouponForm.saveKey,
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(Sizes.minTarget),
            ),
            child: Text(editingExisting ? 'احفظ' : 'اعمل الكوبون'),
          ),
        ],
      ),
    );
  }
}

/// One coupon in a list: the code, whose it is, the offer, how much it has been used, and
/// a switch that pauses it.
class CouponTile extends StatelessWidget {
  const CouponTile({
    super.key,
    required this.coupon,
    required this.onTap,
    required this.onActiveChanged,
    this.owner,
  });

  final Coupon coupon;

  /// «المنصة» or a shop's name, on the admin's list. Null on a shop's own list.
  final String? owner;
  final VoidCallback onTap;
  final ValueChanged<bool> onActiveChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    final used = coupon.totalLimit > 0
        ? 'اتستخدم ${coupon.usedCount} من ${coupon.totalLimit}'
        : 'اتستخدم ${coupon.usedCount}';
    String date(DateTime d) => '${d.day}/${d.month}/${d.year}';
    final window = switch ((coupon.validFrom, coupon.validUntil)) {
      (null, null) => null,
      (final from?, null) => 'من ${date(from)}',
      (null, final until?) => 'لحد ${date(until)}',
      (final from?, final until?) => 'من ${date(from)} لحد ${date(until)}',
    };

    return Material(
      color: colors.card,
      borderRadius: Radii.cardAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.cardAll,
        child: Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
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
                      coupon.code,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.titleLarge,
                    ),
                    if (owner != null)
                      Text(
                        owner!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.textSecondary),
                      ),
                    const SizedBox(height: Space.xs),
                    Text(
                      couponOffer(coupon, strings.price),
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      [
                        if (coupon.minOrder > 0) 'أقل طلب ${strings.price(coupon.minOrder)}',
                        if (coupon.firstOrderOnly) 'أول طلب بس',
                        used,
                        ?window,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: coupon.isActive,
                onChanged: onActiveChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
