import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../about/about_screen.dart';
import '../developer/developer_screen.dart';
import '../address/address_editor_screen.dart';

/// حسابي — who the customer is, where they live, what reaches them, and the way out.
///
/// Four blocks against `design/customer/Account.dc.html`: the profile card; عناويني
/// inline — the addresses moved onto this screen off a tile that used to push a list;
/// a grouped الإشعارات card; and a grouped support card that ends in sign-out, with the
/// build number quiet underneath.
///
/// Two places the artboard could not be followed literally:
///
/// - **It draws two notification switches, and only one of them can exist.** The single
///   per-customer preference in this product is `marketing_push` — the offers. The three
///   order-status messages ride their own Android channel and are never gated on a
///   toggle, so a switch for them would be a control that does nothing every time the
///   screen is opened. That row is a statement instead, and the caption under the card
///   says as much in words.
///
/// - **It has no "delete account", and the screen must keep one.** Google Play requires
///   in-app deletion from any app that makes accounts. It sits below sign-out and
///   quieter than it — the act is rarer and more final, and its own dialog carries the
///   warning — rather than inheriting the artboard's absence.
///
/// The artboard's `تعديل` on the profile card is left off: CustomerApp has no writer for
/// a name, and the phone number is the account identity — folded into a synthetic
/// sign-in address — so it is deliberately not editable from a settings screen. Adding a
/// profile editor is a feature with its own provider work, not this redesign.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  static const signInKey = Key('account.signIn');
  static const signOutKey = Key('account.signOut');
  static const confirmSignOutKey = Key('account.confirmSignOut');
  static const deleteAccountKey = Key('account.deleteAccount');
  static const confirmDeleteAccountKey = Key('account.confirmDeleteAccount');
  static const deleteAccountErrorKey = Key('account.deleteAccountError');
  static const marketingKey = Key('account.marketing');
  static const appearanceKey = Key('account.appearance');
  static Key appearanceOptionKey(ThemeMode mode) =>
      Key('account.appearance.${mode.name}');
  static const addressesKey = Key('account.addresses');
  static const contactKey = Key('account.contact');
  static const aboutKey = Key('account.about');
  static const developerKey = Key('account.developer');
  static const nameKey = Key('account.name');
  static const phoneKey = Key('account.phone');
  static const passwordKey = Key('account.password');
  static const toggleModeKey = Key('account.toggleMode');
  static const errorKey = Key('account.error');
  static const versionKey = Key('account.version');
  static const profileKey = Key('account.profile');
  static const addAddressKey = Key('account.addAddress');

  /// The row that used to be a switch — see the class doc. Keyed so a test can prove it
  /// is not one.
  static const orderStatusNoticeKey = Key('account.orderStatusNotice');

  static Key addressCardKey(String id) => Key('account.address.$id');

  /// The artboard's 18 between blocks — one past [Space.lg], short of [Space.xl].
  static const _blockGap = Space.lg + 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(currentIdentityProvider).value;
    final colors = Theme.of(context).luqma;
    // `support_whatsapp` is carried from AdminApp; blank means the owner has not set a
    // number, and then there is no row — the same rule حول لقمة applies to its own icons.
    final support = ref.watch(appConfigProvider).supportWhatsapp.trim();
    final version = ref.watch(appVersionProvider);

    // Each block settles into place on its own short delay; a row or card answers a
    // press. Both are no-ops under reduced motion, and that is the whole of the movement
    // on a screen people open to do one thing and leave.
    final blocks = <Widget>[
      if (identity == null)
        const _SignInCard()
      else
        _ProfileCard(identity: identity),
      if (identity != null) const _AddressesBlock(key: addressesKey),
      if (identity != null) _NotificationsGroup(uid: identity.uid),
      _SupportGroup(
        identity: identity,
        support: support,
        onSignOut: () => _confirmSignOut(context, ref),
        onDeleteAccount: () => _confirmDeleteAccount(context, ref),
      ),
    ];

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
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0) const SizedBox(height: _blockGap),
            LuqmaEntrance(index: i, child: blocks[i]),
          ],
          // The build number, where every app puts it. It lived on حول لقمة under the
          // owner's photo, which read a technical detail as part of who they are — that
          // page is theirs, this one is the app's. Drawn signed out too: the person who
          // rings about a problem is often the one who cannot get in.
          if (version.isNotEmpty) ...[
            const SizedBox(height: _blockGap),
            Text(
              'نسخة $version',
              key: versionKey,
              textAlign: TextAlign.center,
              style: LuqmaType.caption.copyWith(color: colors.textSecondary),
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

  Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(authServiceProvider);
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DeleteAccountDialog(),
    );

    if (deleted ?? false) {
      // GoTrue does not retroactively remove the token already on this phone. Clearing
      // the local session is what makes the successful deletion return to the signed-out
      // face immediately instead of waiting for that token to expire.
      await auth.signOut();
    }
  }
}

/// The person, as an avatar drawn from their name plus the name and number themselves.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.identity});

  final LuqmaIdentity identity;

  /// The artboard's 52dp avatar, given to [CircleAvatar] as a radius.
  static const _avatarRadius = 26.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    final name = identity.name?.trim() ?? '';
    final hasName = name.isNotEmpty;

    return Container(
      key: AccountScreen.profileKey,
      padding: const EdgeInsets.all(_groupRowInset),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
        boxShadow: Elevations.card,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: _avatarRadius,
            backgroundColor: colors.surface,
            child: Text(
              // The first letter of the name they typed. An avatar image would be a
              // network fetch on a screen that has nothing else to wait for.
              hasName ? name.characters.first : '؟',
              style: theme.textTheme.titleLarge?.copyWith(color: colors.brand),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasName ? name : 'عميل لقمة',
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (identity.phone != null) ...[
                  const SizedBox(height: Space.xs / 2),
                  Text(
                    identity.phone!,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// عناويني, on the account screen rather than behind a tile.
///
/// The default address is outlined in the brand colour and carries the pill; the rest
/// are plain cards that a press promotes — the same act as tapping a row on the full
/// addresses screen, which still exists and is still reached from the home bar and from
/// checkout, where deleting an address also lives.
class _AddressesBlock extends ConsumerWidget {
  const _AddressesBlock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncAddresses = ref.watch(myAddressesProvider);
    // `.value`, not `.valueOrNull`. This codebase has both spellings in play: `Result`
    // carries `valueOrNull`, and `AsyncValue` carries a nullable `value` — reaching for
    // the repository's name on a provider's type is an easy slip and the analyzer is the
    // only thing that catches it.
    final chosen = ref.watch(chosenAddressProvider).value;
    final zones = ref.watch(zonesProvider).value ?? const <Zone>[];

    String zoneNameFor(Address a) =>
        zones.where((z) => z.id == a.zoneId).firstOrNull?.name ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GroupLabel('عناويني'),
        const SizedBox(height: Space.sm + 2),
        switch (asyncAddresses) {
          // One failed read is not a dead end: the shared error view carries a retry,
          // and the "أضف عنوان" button below still works.
          AsyncValue(hasError: true, :final error?) => LuqmaErrorView(
              failure: error,
              onRetry: () => ref.invalidate(myAddressesProvider),
              compact: true,
            ),
          AsyncValue(hasValue: true, :final value?) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final address in value) ...[
                  _AddressCard(
                    address: address,
                    zoneName: zoneNameFor(address),
                    isDefault: address.id == chosen?.id,
                  ),
                  const SizedBox(height: Space.sm),
                ],
              ],
            ),
          // A brief flash while the list loads: the button alone, no skeleton.
          _ => const SizedBox.shrink(),
        },
        const _AddAddressButton(),
      ],
    );
  }
}

class _AddressCard extends ConsumerWidget {
  const _AddressCard({
    required this.address,
    required this.zoneName,
    required this.isDefault,
  });

  final Address address;
  final String zoneName;
  final bool isDefault;

  /// The artboard's 1.5 on the default card. A plain card takes [Border.all]'s own 1.0.
  static const _selectedBorderWidth = 1.5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    final label = address.label?.trim();
    final heading = (label != null && label.isNotEmpty) ? label : 'عنوان';

    final card = Container(
      constraints: const BoxConstraints(minHeight: Sizes.minTarget),
      padding: const EdgeInsets.all(_groupRowInset),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(
          color: isDefault ? colors.brand : colors.hairline,
          width: isDefault ? _selectedBorderWidth : 1.0,
        ),
        boxShadow: Elevations.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: Space.xs / 2),
            child: Icon(
              Icons.place_outlined,
              size: Sizes.iconSm,
              color: isDefault ? colors.brand : colors.textSecondary,
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        heading,
                        style: LuqmaType.bodyStrong
                            .copyWith(color: colors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isDefault) ...[
                      const SizedBox(width: Space.sm),
                      const _DefaultPill(),
                    ],
                  ],
                ),
                const SizedBox(height: Space.xs / 2),
                Text(
                  address.format(zoneName: zoneName),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // The default has nothing to promote, so it does not answer a press.
    if (isDefault) {
      return KeyedSubtree(
        key: AccountScreen.addressCardKey(address.id),
        child: card,
      );
    }

    return LuqmaPressable(
      key: AccountScreen.addressCardKey(address.id),
      onTap: () => ref.read(addressActionsProvider).choose(address.id),
      child: card,
    );
  }
}

/// White on burgundy — the primary-button pair, pinned in `theme_test.dart`.
class _DefaultPill extends StatelessWidget {
  const _DefaultPill();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xs / 2,
      ),
      decoration: BoxDecoration(color: colors.brand, borderRadius: Radii.pillAll),
      child: Text(
        'الافتراضي',
        style: LuqmaType.caption.copyWith(
          color: colors.onBrand,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AddAddressButton extends StatelessWidget {
  const _AddAddressButton();

  static const _height = Sizes.minTarget;
  static const _strokeWidth = 1.5;
  static const _dashLength = 6.0;
  static const _dashGap = 4.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return LuqmaPressable(
      key: AccountScreen.addAddressKey,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AddressEditorScreen()),
      ),
      child: CustomPaint(
        // The strong interactive outline, not the decorative hairline — this is a
        // control, and `colors.hairline` scores 1.5:1 on the ground and reads as
        // not-there. There is no `BoxBorder` that dashes, hence the painter.
        painter: DashedBorderPainter(
          color: colors.border,
          radius: Radii.card.x,
          strokeWidth: _strokeWidth,
          dashLength: _dashLength,
          dashGap: _dashGap,
        ),
        child: ConstrainedBox(
          // A minimum, not a fixed height. The label scales with the reader's type size
          // and the box did not, so past about 2x the text was clipped by the dashes
          // around it — and somebody who turned the text up did so because they need it.
          constraints: const BoxConstraints(minHeight: _height),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: Sizes.iconSm, color: colors.brand),
                const SizedBox(width: Space.sm),
                Text(
                  'أضف عنوان',
                  style: LuqmaType.bodyStrong.copyWith(color: colors.brand),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a dashed rounded-rect outline — there is no `BoxBorder` that dashes.
///
/// Public, and its inputs kept as plain fields, so a test can read back the [color] it
/// was handed: the "أضف عنوان" control has to carry the strong interactive outline
/// rather than the decorative hairline, and a painted stroke is not something a widget
/// test can otherwise inspect.
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dashLength,
    required this.dashGap,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dashLength;
  final double dashGap;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in outline.computeMetrics()) {
      var start = 0.0;
      while (start < metric.length) {
        final end = math.min(start + dashLength, metric.length);
        canvas.drawPath(metric.extractPath(start, end), paint);
        start += dashLength + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dashLength != dashLength ||
      oldDelegate.dashGap != dashGap;
}

/// الإشعارات — one real switch and one row that only looks like it should be one.
class _NotificationsGroup extends StatelessWidget {
  const _NotificationsGroup({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GroupLabel('الإشعارات'),
        const SizedBox(height: Space.sm + 2),
        _GroupCard(
          // The offers row draws its own top divider so it can take the whole subtree —
          // divider included — with it when it cannot be read.
          dividers: false,
          rows: [
            const _OrderStatusNoticeRow(),
            _OffersRow(uid: uid),
          ],
        ),
        const SizedBox(height: Space.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xs),
          child: Text(
            'إشعارات حالة الطلب مبتتقفلش — دي اللي بتقولك إن طلبك خرج.',
            style: LuqmaType.caption.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// A statement, not a control.
///
/// Accepted, on the way, cancelled — those go out on their own Android channel and are
/// never gated on a toggle. A switch here would do nothing every time the screen opened,
/// which is the lie the caption under this card exists to deny. Same icon and label as
/// the artboard's switch, and a lock instead of the thumb.
class _OrderStatusNoticeRow extends StatelessWidget {
  const _OrderStatusNoticeRow();

  static const _minHeight = 52.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return KeyedSubtree(
      key: AccountScreen.orderStatusNoticeKey,
      child: Semantics(
        container: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _groupRowInset),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  size: Sizes.iconSm,
                  color: colors.brand,
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text('حالة الطلب', style: theme.textTheme.bodyLarge),
                ),
                Text(
                  // "مش بتتقفل من هنا", not "بتوصل دايمًا".
                  //
                  // What this row can honestly say is that the *app* has no switch for
                  // it. Whether the notification arrives is Android's to decide: the
                  // system permission can be refused, and Android remembers a refusal for
                  // ever. Promising delivery on a phone that has denied the permission is
                  // the screen telling somebody their order updates are guaranteed while
                  // they silently are not.
                  'مش بتتقفل من هنا',
                  style: LuqmaType.caption.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(width: Space.xs),
                Icon(
                  Icons.lock_outline_rounded,
                  size: Sizes.iconSm,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// عروض وخصومات — the one notification a customer can switch off.
///
/// Promotions on the `push` channel reach somebody who is not looking at the app, which
/// is what makes them worth selling and why there has to be a way out. The read, the
/// optimistic write and the roll-back on failure are unchanged from when this was a
/// standalone card; only the chrome around it moved into the grouped card.
class _OffersRow extends ConsumerStatefulWidget {
  const _OffersRow({required this.uid});

  final String uid;

  @override
  ConsumerState<_OffersRow> createState() => _OffersRowState();
}

class _OffersRowState extends ConsumerState<_OffersRow> {
  bool? _on;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final result = await ref
        .read(profileRepositoryProvider)
        .readMarketingPush(uid: widget.uid);
    // A failed read leaves the row undrawn rather than in a state nobody chose: the
    // offers keep arriving, which is the state the account was already in.
    if (mounted && result.valueOrNull != null) {
      setState(() => _on = result.valueOrNull);
    }
  }

  Future<void> _set(bool on) async {
    final was = _on;
    setState(() => _on = on);

    final result = await ref
        .read(profileRepositoryProvider)
        .setMarketingPush(uid: widget.uid, on: on);
    // Put back what the server still believes. A switch that stays where somebody left
    // it while the write failed is a switch that lies about what it did.
    if (mounted && result.failureOrNull != null) setState(() => _on = was);
  }

  @override
  Widget build(BuildContext context) {
    final on = _on;
    if (on == null) return const SizedBox.shrink();

    final colors = Theme.of(context).luqma;

    return Column(
      mainAxisSize: MainAxisSize.min,
      // Stretched so the divider it carries spans the card — this column sits inside a
      // stretch column but resets the cross axis for its own children otherwise.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _HairlineDivider(),
        SwitchListTile(
          key: AccountScreen.marketingKey,
          value: on,
          onChanged: _set,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: _groupRowInset,
          ),
          secondary: Icon(
            Icons.local_offer_outlined,
            size: Sizes.iconSm,
            color: colors.brand,
          ),
          title: const Text('عروض وخصومات'),
        ),
        const _HairlineDivider(),
        const _Appearance(),
      ],
    );
  }
}

/// Light, dark, or the phone's own setting.
///
/// Three choices rather than a switch, because "follow the phone" is a real answer and
/// the commonest one: somebody whose handset turns dark at sunset already made this
/// decision once, for everything they own. A two-state switch cannot express it — it can
/// only pin the app to one of them for ever, and then the person who wanted the app to
/// follow along has no way back.
class _Appearance extends ConsumerWidget {
  const _Appearance();

  static const _labels = {
    ThemeMode.system: 'حسب الموبايل',
    ThemeMode.light: 'فاتح',
    ThemeMode.dark: 'غامق',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final mode = ref.watch(themeModeProvider);

    return Padding(
      key: AccountScreen.appearanceKey,
      padding: const EdgeInsets.fromLTRB(
        _groupRowInset,
        Space.md,
        _groupRowInset,
        Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.brightness_6_outlined,
                  size: Sizes.iconSm, color: colors.brand),
              const SizedBox(width: Space.md),
              Expanded(child: Text('شكل التطبيق', style: theme.textTheme.bodyMedium)),
            ],
          ),
          const SizedBox(height: Space.sm),
          // `Wrap`, not three `Expanded` chips in a row. Equal thirds of a phone's width
          // are narrower than «حسب الموبايل», and the chip clips rather than shrinking —
          // so the option that needs explaining most read as «حسب». Here each chip is as
          // wide as its own words, and a narrow phone or a large type size moves the last
          // one to a second line instead of cutting it.
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final entry in _labels.entries)
                LuqmaChip(
                  key: AccountScreen.appearanceOptionKey(entry.key),
                  label: entry.value,
                  selected: mode == entry.key,
                  onTap: () =>
                      ref.read(themeModeProvider.notifier).set(entry.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// كلّمنا · عن لقمة · تسجيل الخروج, and the delete control the artboard leaves out.
class _SupportGroup extends ConsumerWidget {
  const _SupportGroup({
    required this.identity,
    required this.support,
    required this.onSignOut,
    required this.onDeleteAccount,
  });

  final LuqmaIdentity? identity;
  final String support;
  final VoidCallback onSignOut;
  final VoidCallback onDeleteAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).luqma;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupCard(
          rows: [
            // Reachable signed in or out: somebody with a problem needs a person, and a
            // problem is exactly the moment an account stops working.
            if (support.isNotEmpty)
              _NavRow(
                rowKey: AccountScreen.contactKey,
                icon: Icons.chat_bubble_outline_rounded,
                label: 'كلّمنا على واتساب',
                onTap: () => openExternalLink(
                  context,
                  ref,
                  Uri.parse('https://wa.me/${Phone.toWhatsapp(support)}'),
                  whenUnavailable: 'مفيش واتساب على التليفون ده. الرقم $support',
                ),
              ),
            _NavRow(
              rowKey: AccountScreen.aboutKey,
              icon: Icons.info_outline_rounded,
              label: 'عن لقمة',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
              ),
            ),
            // Its own row, not a section inside «عن لقمة»: the product and the person who
            // made it are two pages, at the owner's request.
            _NavRow(
              rowKey: AccountScreen.developerKey,
              icon: Icons.person_outline_rounded,
              label: 'عن المطور',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DeveloperScreen()),
              ),
            ),
            if (identity != null)
              _NavRow(
                rowKey: AccountScreen.signOutKey,
                icon: Icons.logout_rounded,
                label: 'تسجيل الخروج',
                onTap: onSignOut,
                danger: true,
                showChevron: false,
              ),
          ],
        ),
        if (identity != null) ...[
          const SizedBox(height: Space.md),
          Center(
            // Quieter than sign-out on purpose: rarer, more final, and the confirmation
            // dialog carries the warning. An inviting button here is one tapped by
            // mistake.
            child: TextButton(
              key: AccountScreen.deleteAccountKey,
              onPressed: onDeleteAccount,
              style: TextButton.styleFrom(
                foregroundColor: colors.textSecondary,
                textStyle: LuqmaType.bodySmall,
                minimumSize: const Size(Sizes.minTarget, Sizes.minTarget),
              ),
              child: const Text('حذف الحساب نهائيًا'),
            ),
          ),
        ],
      ],
    );
  }
}

/// The artboard insets every grouped row, and the dividers between them, by 13 — one
/// past [Space.md], short of [Space.lg].
const double _groupRowInset = Space.md + 1;

/// A white rounded card holding a column of rows, hairline-divided.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.rows, this.dividers = true});

  final List<Widget> rows;

  /// When false, a row draws its own separator if it wants one — used where a row can
  /// disappear and must take its divider with it.
  final bool dividers;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    // A `Material` carries the fill, not a `DecoratedBox` around it.
    //
    // The rows inside are `ListTile`s, and a `ListTile` paints its background and its ink
    // on the nearest `Material` ancestor. Wrapped in a coloured `DecoratedBox`, that ink
    // lands *behind* the fill and is never seen — Flutter asserts on exactly this
    // arrangement rather than letting it ship, which is why forty-five tests failed at
    // once on a screen whose logic was fine.
    //
    // The border and the corner move onto the `Material`'s own shape so there is still
    // one thing drawing the card, and `clipBehavior` keeps a pressed row's splash inside
    // the rounded corner instead of squaring it off.
    return Material(
      color: colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.cardAll,
        side: BorderSide(color: colors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: Radii.cardAll,
          boxShadow: Elevations.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (dividers && i > 0) const _HairlineDivider(),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _HairlineDivider extends StatelessWidget {
  const _HairlineDivider();

  static const _thickness = 1.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _thickness,
      margin: const EdgeInsets.symmetric(horizontal: _groupRowInset),
      color: Theme.of(context).luqma.hairline,
    );
  }
}

/// A grouped-card row that leads somewhere: an icon, a label, and a chevron unless it is
/// the last thing a row would do (sign out).
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.rowKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.showChevron = true,
    this.danger = false,
  });

  final Key rowKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool showChevron;
  final bool danger;

  /// The artboard's row; clears [Sizes.minTarget] with headroom.
  static const _minHeight = 52.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return LuqmaPressable(
      key: rowKey,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _minHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _groupRowInset),
          child: Row(
            children: [
              Icon(
                icon,
                size: Sizes.iconSm,
                color: danger ? colors.danger : colors.brand,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: danger ? colors.danger : colors.textPrimary,
                  ),
                ),
              ),
              if (showChevron)
                Icon(
                  Icons.chevron_left_rounded,
                  size: Sizes.iconSm,
                  color: colors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: Space.xs),
      child: Text(
        text,
        style: LuqmaType.caption.copyWith(
          color: Theme.of(context).luqma.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  bool _deleting = false;
  Failure? _failure;

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _failure = null;
    });

    final result = await ref.read(profileRepositoryProvider).deleteMyAccount();
    if (!mounted) return;

    final failure = result.failureOrNull;
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _deleting = false;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    final colors = Theme.of(context).luqma;

    return AlertDialog(
      title: const Text('حذف الحساب نهائيًا؟'),
      content: failure == null
          ? SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'بيانات حسابك واسمك ورقم موبايلك وعناوينك '
                    'وتقييماتك هيتحذفوا.\n\n'
                    'سجل الطلبات هيفضل محفوظ عشان حسابات الفلوس '
                    'اللي اتدفعت كاش بين المطعم ولقمة، لكن اسمك ورقمك '
                    'هيتشالوا منه.\n\n'
                    'الحذف نهائي ومفيش طريقة للرجوع. لو سجلت بنفس الرقم بعد '
                    'كده، هيتعمل حساب جديد من غير أي تاريخ قديم.',
                  ),
                  if (_deleting) ...[
                    const SizedBox(height: Space.lg),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            )
          : LuqmaErrorView(
              key: AccountScreen.deleteAccountErrorKey,
              failure: failure,
              onRetry: _delete,
              compact: true,
            ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.of(context).pop(false),
          child: Text(failure == null ? 'إلغاء' : 'اقفل'),
        ),
        if (failure == null)
          FilledButton(
            key: AccountScreen.confirmDeleteAccountKey,
            onPressed: _deleting ? null : _delete,
            style: FilledButton.styleFrom(backgroundColor: colors.danger),
            child: const Text('احذف حسابي'),
          ),
      ],
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
