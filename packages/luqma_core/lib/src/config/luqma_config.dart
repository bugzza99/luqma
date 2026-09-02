import 'package:flutter/foundation.dart';

/// Where remote values come from. An interface so the parsing and validation below can
/// be tested without Firebase, and so a source can be swapped later without touching
/// any of the rules.
abstract interface class ConfigSource {
  Object? read(String key);
}

/// A plain map. Used by tests, and as the empty source on the very first cold start.
class MapConfigSource implements ConfigSource {
  const MapConfigSource(this._values);

  final Map<String, Object> _values;

  @override
  Object? read(String key) => _values[key];
}

/// Every value the owner can change without shipping an update.
///
/// The defaults here are the app's real behaviour: they are compiled into the binary, so
/// a phone with no network on first launch still runs a correct app rather than an
/// unconfigured one. A remote value only replaces a default when it is present, of the
/// right type, and inside a range the app can actually operate in — the control plane
/// reaches every phone at once, and an admin typo must not be able to brick them.
@immutable
class LuqmaConfig {
  const LuqmaConfig({
    required this.otpEnabled,
    required this.admobEnabled,
    required this.publicCommentsEnabled,
    required this.onlinePaymentEnabled,
    required this.acceptTimeoutMinutes,
    required this.marketingPushPerWeek,
    required this.rejectionBanThreshold,
    required this.minRatingsToShow,
    required this.deliveryFeeMin,
    required this.deliveryFeeMax,
    required this.splashMinMillis,
    required this.minSupportedVersion,
    required this.updateMessage,
    required this.supportWhatsapp,
    this.aboutPhotoMediaId,
    this.aboutFacebook,
    this.aboutWhatsapp,
    this.aboutInstagram,
    this.aboutDescription,
  });

  /// Phone verification. Built, and off until order volume makes it worth the SMS cost.
  final bool otpEnabled;

  /// Google's ad network. Built, and off: merchant-sold promotions come first.
  final bool admobEnabled;

  /// Opens rating comments to the public. Off for roughly the first six months.
  final bool publicCommentsEnabled;
  final bool onlinePaymentEnabled;

  /// How long a merchant has to accept before the order is flagged to the admin.
  final int acceptTimeoutMinutes;
  final int marketingPushPerWeek;

  /// Refused deliveries before a customer is blocked automatically.
  final int rejectionBanThreshold;

  /// A merchant's stars stay hidden until it has this many ratings, so one bad review
  /// cannot sink a new merchant in a town where everyone knows everyone.
  final int minRatingsToShow;

  /// Bounds, in piastres, on what a merchant may set its own delivery fee to.
  final int deliveryFeeMin;
  final int deliveryFeeMax;

  final int splashMinMillis;
  final String? minSupportedVersion;
  final String updateMessage;
  final String supportWhatsapp;

  /// The "حول لقمة" content, edited from AdminApp and stored on the same config table.
  /// An icon with no link set is not drawn, so each of these is nullable.
  final String? aboutPhotoMediaId;
  final String? aboutFacebook;
  final String? aboutWhatsapp;
  final String? aboutInstagram;
  final String? aboutDescription;

  static const defaults = LuqmaConfig(
    otpEnabled: false,
    admobEnabled: false,
    publicCommentsEnabled: false,
    onlinePaymentEnabled: false,
    acceptTimeoutMinutes: 5,
    // Contained at launch: approval currently records a campaign but no sender queues
    // it. A non-zero default advertises a paid capability that does not exist yet.
    marketingPushPerWeek: 0,
    rejectionBanThreshold: 3,
    minRatingsToShow: 10,
    deliveryFeeMin: 500,
    deliveryFeeMax: 2000,
    splashMinMillis: 1500,
    minSupportedVersion: null,
    updateMessage: '',
    supportWhatsapp: '',
  );

  static LuqmaConfig from(ConfigSource source) {
    bool flag(String key, bool fallback) {
      final value = source.read(key);
      return value is bool ? value : fallback;
    }

    /// Reads an integer, rejecting anything outside the range the app can run in.
    /// A rejected value falls back on its own and leaves its neighbours alone — one
    /// bad key must not discard a whole config.
    int ranged(String key, int fallback, {required int min, required int max}) {
      final value = source.read(key);
      if (value is! int) return fallback;
      if (value < min || value > max) return fallback;
      return value;
    }

    String? text(String key) {
      final value = source.read(key);
      return value is String && value.isNotEmpty ? value : null;
    }

    // The fee bounds are validated as a pair: a max below a min describes no valid fee
    // at all, so neither half of a contradictory range is trusted.
    var feeMin = ranged(
      'delivery_fee_min',
      defaults.deliveryFeeMin,
      min: 0,
      max: 100000,
    );
    var feeMax = ranged(
      'delivery_fee_max',
      defaults.deliveryFeeMax,
      min: 0,
      max: 100000,
    );
    if (feeMax < feeMin) {
      feeMin = defaults.deliveryFeeMin;
      feeMax = defaults.deliveryFeeMax;
    }

    return LuqmaConfig(
      otpEnabled: flag('otp_enabled', defaults.otpEnabled),
      admobEnabled: flag('admob_enabled', defaults.admobEnabled),
      publicCommentsEnabled: flag(
        'public_comments_enabled',
        defaults.publicCommentsEnabled,
      ),
      onlinePaymentEnabled: flag(
        'online_payment_enabled',
        defaults.onlinePaymentEnabled,
      ),
      acceptTimeoutMinutes: ranged(
        'accept_timeout_minutes',
        defaults.acceptTimeoutMinutes,
        min: 1,
        max: 60,
      ),
      marketingPushPerWeek: ranged(
        'marketing_push_per_week',
        defaults.marketingPushPerWeek,
        min: 0,
        max: 21,
      ),
      rejectionBanThreshold: ranged(
        'rejection_ban_threshold',
        defaults.rejectionBanThreshold,
        min: 1,
        max: 50,
      ),
      minRatingsToShow: ranged(
        'min_ratings_to_show',
        defaults.minRatingsToShow,
        min: 0,
        max: 1000,
      ),
      deliveryFeeMin: feeMin,
      deliveryFeeMax: feeMax,
      splashMinMillis: ranged(
        'splash_min_millis',
        defaults.splashMinMillis,
        min: 0,
        max: 5000,
      ),
      minSupportedVersion: text('min_supported_version'),
      updateMessage: text('update_message') ?? defaults.updateMessage,
      supportWhatsapp: text('support_whatsapp') ?? defaults.supportWhatsapp,
      aboutPhotoMediaId: text('about_photo_media_id'),
      aboutFacebook: text('about_facebook'),
      aboutWhatsapp: text('about_whatsapp'),
      aboutInstagram: text('about_instagram'),
      aboutDescription: text('about_description'),
    );
  }

  /// Whether [currentVersion] is below the minimum the backend still supports.
  ///
  /// Compared segment by segment as numbers. Comparing the strings would put 1.10
  /// below 1.4 and lock out the newest build in the field.
  bool requiresUpdate(String currentVersion) {
    final minimum = _parseVersion(minSupportedVersion);
    if (minimum == null) return false;
    final current = _parseVersion(currentVersion);
    if (current == null) return false;

    for (var i = 0; i < 3; i++) {
      if (current[i] != minimum[i]) return current[i] < minimum[i];
    }
    return false;
  }

  static List<int>? _parseVersion(String? raw) {
    if (raw == null) return null;
    final parts = raw.split('.');
    if (parts.isEmpty || parts.length > 3) return null;
    final numbers = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0) return null;
      numbers.add(value);
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return numbers;
  }
}
