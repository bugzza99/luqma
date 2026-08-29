import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:url_launcher/url_launcher.dart';

part 'external_links.g.dart';

/// Handing a URL to the phone, and admitting when the phone will not take it.
///
/// `launchUrl` fails two different ways and three of the four call sites in this
/// product ignored both. It returns `false` when nothing on the device handled the URL,
/// and it *throws* `PlatformException` when no activity is registered for the scheme at
/// all — a handset with no dialer, a WhatsApp link with no WhatsApp, a web build.
///
/// The expensive one was the courier: `tel:` from the delivery screen, on a device that
/// refuses it, produced no call, no error and no sign anything had happened. The person
/// is standing at somebody's door holding their food.
abstract interface class ExternalLinks {
  /// True when the phone took it. Never throws.
  Future<bool> open(Uri url);
}

class PhoneExternalLinks implements ExternalLinks {
  const PhoneExternalLinks();

  @override
  Future<bool> open(Uri url) async {
    try {
      // `externalApplication` for all of it: a `tel:` or a `whatsapp:` has nowhere else
      // to go, and a social link opened in an in-app webview is a worse browser than
      // the one the person already chose.
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } on Exception {
      // Classified as "the phone said no", which is what the caller tells the person.
      // There is nothing here worth crashing over and nothing worth reporting.
      return false;
    }
  }
}

/// Records what it was asked to open, and can refuse.
@visibleForTesting
class FakeExternalLinks implements ExternalLinks {
  FakeExternalLinks({this.answer = true});

  /// What the phone says. False is the device with no dialer.
  bool answer;

  final opened = <Uri>[];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return answer;
  }
}

@Riverpod(keepAlive: true)
ExternalLinks externalLinks(Ref ref) => const PhoneExternalLinks();

/// Opens [url], and says so on the screen when nothing on the phone can.
///
/// The sentence is the point. Silence after a tap is indistinguishable from a button
/// that is broken, and the person's next move — tap it again — makes it no better.
Future<void> openExternalLink(
  BuildContext context,
  WidgetRef ref,
  Uri url, {
  required String whenUnavailable,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final opened = await ref.read(externalLinksProvider).open(url);
  if (opened || messenger == null) return;
  messenger.showSnackBar(SnackBar(content: Text(whenUnavailable)));
}
