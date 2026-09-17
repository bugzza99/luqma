import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// حول لقمة.
///
/// The product, and only the product: the mark, what Luqma is, and the way to reach it.
///
/// It used to be the owner's page as well — their photo in place of the logo and their
/// personal links under the description — which made "about Luqma" read as a biography.
/// The owner asked for the two apart, and the person has a page of their own now,
/// reached from حسابي.
///
/// The build number used to sit at the bottom of this, directly under the description
/// with nothing between them, which made a technical detail read as part of the product.
/// It is a footer on حسابي.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  static const descriptionKey = Key('about.description');
  static const contactKey = Key('about.contact');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final description = config.aboutDescription?.trim() ?? '';
    final support = config.supportWhatsapp.trim();

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('حول لقمة')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.lg,
          Space.gutter,
          Space.xxxl,
        ),
        children: [
          const Center(child: LuqmaLockup(logo: LuqmaLogo.stacked, height: 150)),
          const SizedBox(height: Space.lg),
          if (description.isNotEmpty) ...[
            Text(
              description,
              key: AboutScreen.descriptionKey,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.xl),
          ],
          // The same number حسابي offers, because the question somebody has after reading
          // this page is usually a question for a person. Not drawn while it is blank.
          if (support.isNotEmpty)
            Center(
              child: OutlinedButton.icon(
                key: AboutScreen.contactKey,
                onPressed: () => openExternalLink(
                  context,
                  ref,
                  Uri.parse('https://wa.me/${Phone.toWhatsapp(support)}'),
                  whenUnavailable: 'مفيش واتساب على التليفون ده. الرقم $support',
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: Sizes.iconSm),
                label: const Text('كلّمنا على واتساب'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, Sizes.minTarget),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
