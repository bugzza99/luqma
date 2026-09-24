import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import 'developer_controller.dart';

/// عن المطور.
///
/// The person who made Luqma, on a page of their own: a photo, a name, a few sentences,
/// and the links they chose to share. It lived under «حول لقمة» until the owner asked for
/// it to stand apart, so that reading about the product is not reading a biography.
///
/// Every part is optional and the page draws only what is set — a link that goes nowhere
/// is worse than no link, and a blank where a name belongs reads as a screen that failed.
class DeveloperScreen extends ConsumerWidget {
  const DeveloperScreen({super.key});

  static const nameKey = Key('developer.name');
  static const bioKey = Key('developer.bio');
  static const facebookKey = Key('developer.facebook');
  static const whatsappKey = Key('developer.whatsapp');
  static const instagramKey = Key('developer.instagram');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final photo = ref.watch(developerPhotoProvider).value;
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final name = config.developerName?.trim() ?? '';
    final bio = config.developerBio?.trim() ?? '';

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('عن المطور')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.lg,
          Space.gutter,
          Space.xxxl,
        ),
        children: [
          Center(
            // A face in a circle is the one place a crop is meant: `cover` on purpose.
            child: photo == null
                ? CircleAvatar(
                    radius: 70,
                    backgroundColor: colors.surface,
                    child: Icon(Icons.person_outline_rounded,
                        size: 64, color: colors.textSecondary),
                  )
                : ClipOval(
                    child: Image(
                      image: LuqmaImage.providerFor(photo.url),
                      width: 140,
                      height: 140,
                      fit: BoxFit.cover,
                    ),
                  ),
          ),
          if (name.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            Text(
              name,
              key: DeveloperScreen.nameKey,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ],
          if (bio.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            Text(
              bio,
              key: DeveloperScreen.bioKey,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: Space.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_has(config.developerFacebook))
                _SocialIcon(
                  key: DeveloperScreen.facebookKey,
                  icon: Icons.facebook_rounded,
                  tooltip: 'فيسبوك',
                  url: config.developerFacebook!,
                ),
              if (_has(config.developerWhatsapp))
                _SocialIcon(
                  key: DeveloperScreen.whatsappKey,
                  icon: Icons.chat_rounded,
                  tooltip: 'واتساب',
                  url: config.developerWhatsapp!,
                ),
              if (_has(config.developerInstagram))
                _SocialIcon(
                  key: DeveloperScreen.instagramKey,
                  icon: Icons.photo_camera_outlined,
                  tooltip: 'انستجرام',
                  url: config.developerInstagram!,
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
