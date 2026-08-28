import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// The merchant's own menu.
///
/// The editor itself is `MenuEditor` from `luqma_core`, the same widget AdminApp uses
/// when the owner types a menu in during onboarding. Only the source of `merchantId`
/// differs — a merchant edits their own, an admin picks whose. Two copies of a form this
/// fiddly would drift within a month.
class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  static const noMerchantKey = Key('menu.noMerchant');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchantId = ref.watch(staffIdentityProvider).merchantId;
    final colors = Theme.of(context).luqma;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('المنيو')),
      body: merchantId == null
          ? const Center(
              key: noMerchantKey,
              child: Text('الحساب ده مش مربوط بمطعم'),
            )
          : MenuEditor(merchantId: merchantId),
    );
  }
}
