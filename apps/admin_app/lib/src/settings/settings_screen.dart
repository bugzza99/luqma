import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:luqma_core/luqma_core.dart';

import '../auth/admin_access.dart';
import '../shell/layout.dart';

/// The settings hub.
///
/// Config, plans and the "حول لقمة" content are set once, not every day, so they live
/// behind one door rather than crowding the rail the owner uses hourly. Each pushes a
/// route so the back affordance returns here.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const configKey = Key('settings.config');
  static const plansKey = Key('settings.plans');
  static const aboutKey = Key('settings.about');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: AdminContent(
        child: ListView(
          padding: const EdgeInsets.all(Space.gutter),
          children: [
            _Tile(
              key: configKey,
              icon: Icons.tune_rounded,
              title: 'الإعدادات',
              subtitle: 'الميزات والحدود والتحديثات',
              onTap: () => context.push(Routes.config),
            ),
            const SizedBox(height: Space.sm),
            _Tile(
              key: plansKey,
              icon: Icons.sell_outlined,
              title: 'الخطط والأسعار',
              subtitle: 'أسعار الاشتراك وحدود الميزات',
              onTap: () => context.push(Routes.plans),
            ),
            const SizedBox(height: Space.sm),
            _Tile(
              key: aboutKey,
              icon: Icons.info_outline,
              title: 'حول لقمة',
              subtitle: 'صورة المالك والروابط والوصف',
              onTap: () => context.push(Routes.about),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return InkWell(
      onTap: onTap,
      borderRadius: Radii.cardAll,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        constraints: const BoxConstraints(minHeight: Sizes.minTarget),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: Radii.cardAll,
          border: Border.all(color: colors.hairline),
        ),
        child: Row(
          children: [
            Icon(icon, color: colors.brand, size: Sizes.iconMd),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_left_rounded,
              color: colors.textSecondary,
              size: Sizes.iconMd,
            ),
          ],
        ),
      ),
    );
  }
}
