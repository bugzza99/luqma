import 'package:flutter/material.dart';

import 'merchant_screen.dart';

/// Opens [merchantId]'s screen.
///
/// One function rather than a callback threaded down through the section registry: the
/// registry builds sections from a fixed map keyed by a server-chosen string, and it has
/// no navigation to hand them. Every list that shows a merchant opens it the same way.
Future<void> openMerchant(BuildContext context, String merchantId) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MerchantScreen(merchantId: merchantId),
    ),
  );
}
