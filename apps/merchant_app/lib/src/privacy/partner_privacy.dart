import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// The partner policy, and the way a partner asks for their account to be removed.
///
/// MerchantApp is one APK for two kinds of account — a shop owner and a rider — and both
/// are created by the platform rather than by the person tapping "sign up". Neither can
/// be deleted from the phone on its own: a shop may still owe commission or have orders
/// in flight, and a rider may be holding cash. Google Play still requires an in-app path,
/// so the path is an explicit request that names the account and hands it to the owner
/// with the context needed to act on it. The policy page says the same thing in public.
abstract final class PartnerAccountKeys {
  static const deletionDialog = Key('partnerAccount.deletionDialog');
  static const confirmDeletion = Key('partnerAccount.confirmDeletion');
}

/// The public partner policy, with the compiled page as the last resort.
Uri partnerPrivacyUri(LuqmaConfig config) =>
    config.privacyUrlFor(LuqmaApp.merchant) ??
    Uri.parse(LuqmaConfig.compiledPrivacyUrls[LuqmaApp.merchant]!);

/// The policy for the public page. Kept here so the app and the web copy cannot drift
/// apart on the one thing a reviewer taps.
const partnerDeletionPageUrl =
    'https://luqma-gules.vercel.app/privacy/partner/delete';

/// The published support line, used only when the control plane has no usable number.
///
/// The old behaviour hid the WhatsApp row when `support_whatsapp` was blank. That is
/// right for a "contact us" row and wrong for a deletion path: Play requires the path to
/// exist, and the owner has already published this number on the policy page.
const _publishedSupportWhatsapp = '01032210681';

String partnerSupportWhatsapp(LuqmaConfig config) {
  final configured = config.supportWhatsapp.trim();
  return Phone.toWhatsapp(configured).isEmpty
      ? _publishedSupportWhatsapp
      : configured;
}

Future<void> openPartnerPrivacy(BuildContext context, WidgetRef ref) async {
  final uri = partnerPrivacyUri(ref.read(appConfigProvider));
  await openExternalLink(
    context,
    ref,
    uri,
    whenUnavailable:
        'مفيش متصفح على التليفون ده. افتح الرابط من أي متصفح: $uri',
  );
}

/// Asks once, then opens WhatsApp with a message the owner can act on.
///
/// [accountLabel] is «صاحب مطعم» or «مندوب», [shopName] is the business the account
/// acts for, and [phone] is the account's own number when the app knows it. Nothing
/// sensitive is pre-filled beyond what the person is already looking at.
Future<void> showPartnerAccountDeletionRequest(
  BuildContext context,
  WidgetRef ref, {
  required String accountLabel,
  String? shopName,
  String? phone,
}) async {
  final config = ref.read(appConfigProvider);
  final support = partnerSupportWhatsapp(config);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: PartnerAccountKeys.deletionDialog,
      title: const Text('طلب حذف الحساب'),
      content: const SingleChildScrollView(
        child: Text(
          'حساب الشريك مش بيتحذف من التليفون لوحده، لأن المحل ممكن يكون عليه '
          'أوردرات أو مستحقات، والمندوب ممكن يكون معاه تحصيل لسه مااتسلّمش.\n\n'
          'لما تطلب الحذف، بنتأكد من صاحب الحساب، وبعدها بنحذف حساب الدخول وبياناتك '
          'الشخصية خلال ٣٠ يوم. سجل الأوردرات والفلوس بيفضل من غير اسمك ورقمك.\n\n'
          'تحب نفتح واتساب ونبعت الطلب؟',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('رجوع'),
        ),
        FilledButton(
          key: PartnerAccountKeys.confirmDeletion,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('افتح واتساب'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  final lines = <String>[
    'طلب حذف حساب شريك',
    'نوع الحساب: $accountLabel',
    if (shopName != null && shopName.trim().isNotEmpty)
      'المحل: ${shopName.trim()}',
    if (phone != null && phone.trim().isNotEmpty)
      'رقم التواصل: ${phone.trim()}',
    'أرجو تأكيد الحذف ومسح بياناتي الشخصية.',
  ];
  final message = lines.join('\n');
  final uri = Uri.parse(
    'https://wa.me/${Phone.toWhatsapp(support)}'
    '?text=${Uri.encodeComponent(message)}',
  );

  await openExternalLink(
    context,
    ref,
    uri,
    whenUnavailable:
        'مفيش واتساب على التليفون ده. كلّم الإدارة على $support أو افتح '
        '$partnerDeletionPageUrl',
  );
}
