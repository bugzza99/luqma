import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import 'about_controller.dart';

/// حول لقمة.
///
/// The owner's page, and only the owner's: their photo, the links they set, and their
/// description. An icon with no link set is not drawn — an icon that goes nowhere is
/// worse than no icon.
///
/// The build number used to sit at the bottom of this, directly under the description
/// with nothing between them, which made a technical detail read as part of who the
/// owner is. It is a footer on حسابي now — the place every app puts it, and still one
/// tap away when somebody rings about a problem.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  static const facebookKey = Key('about.facebook');
  static const whatsappKey = Key('about.whatsapp');
  static const instagramKey = Key('about.instagram');
  static const descriptionKey = Key('about.description');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final photo = ref.watch(aboutPhotoProvider).value;
    final theme = Theme.of(context);
    final colors = theme.luqma;

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
          Center(
            child: photo == null
                ? const LuqmaLockup(logo: LuqmaLogo.stacked, height: 150)
                : ClipOval(
                    child: Image.network(
                      photo.url,
                      width: 140,
                      height: 140,
                      fit: BoxFit.cover,
                    ),
                  ),
          ),
          const SizedBox(height: Space.lg),
          if (config.aboutDescription != null &&
              config.aboutDescription!.trim().isNotEmpty) ...[
            Text(
              config.aboutDescription!.trim(),
              key: AboutScreen.descriptionKey,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.xl),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_has(config.aboutFacebook))
                _SocialIcon(
                  key: AboutScreen.facebookKey,
                  icon: Icons.facebook_rounded,
                  tooltip: 'فيسبوك',
                  url: config.aboutFacebook!,
                ),
              if (_has(config.aboutWhatsapp))
                _SocialIcon(
                  key: AboutScreen.whatsappKey,
                  icon: Icons.chat_rounded,
                  tooltip: 'واتساب',
                  url: config.aboutWhatsapp!,
                ),
              if (_has(config.aboutInstagram))
                _SocialIcon(
                  key: AboutScreen.instagramKey,
                  icon: Icons.photo_camera_outlined,
                  tooltip: 'انستجرام',
                  url: config.aboutInstagram!,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static bool _has(String? link) => link != null && link.trim().isNotEmpty;
}

class _SocialIcon extends ConsumerWidget {
  const _SocialIcon({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.url,
  });

  final IconData icon;
  final String tooltip;
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).luqma;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: colors.brand, size: Sizes.iconLg),
        // A phone with no Facebook app and no browser handler took this tap and did
        // nothing at all, which reads as a broken button rather than a missing app.
        onPressed: () => openExternalLink(
          context,
          ref,
          Uri.parse(url),
          whenUnavailable: 'مقدرناش نفتح $tooltip من التليفون ده.',
        ),
      ),
    );
  }
}
