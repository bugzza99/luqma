import 'package:flutter/foundation.dart';

/// Where remote values come from. An interface so the parsing and validation below can
/// be tested without Firebase, and so a source can be swapped later without touching
/// any of the rules.
abstract interface class ConfigSource {
  Object? read(String key);
}

/// Which shipped Luqma client is resolving app-specific control-plane values.
enum LuqmaApp { customer, merchant, admin }

/// Inclusive bounds for one numeric config value.
@immutable
class ConfigBound {
  const ConfigBound(this.min, this.max);

  final int min;
  final int max;
}

/// The single Dart source of truth for numeric config validation.
///
/// The database mirrors these values in the validation migration so bad values are
/// rejected before they can reach any client.
const configBounds = <String, ConfigBound>{
  'accept_timeout_minutes': ConfigBound(1, 60),
  'marketing_push_per_week': ConfigBound(0, 21),
  'rejection_ban_threshold': ConfigBound(1, 50),
  'min_ratings_to_show': ConfigBound(0, 1000),
  'splash_min_millis': ConfigBound(0, 5000),
  'delivery_fee_min': ConfigBound(0, 100000),
  'delivery_fee_max': ConfigBound(0, 100000),
};

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
    required this.customerMinSupportedVersion,
    required this.merchantMinSupportedVersion,
    required this.adminMinSupportedVersion,
    required this.customerUpdateUrl,
    required this.merchantUpdateUrl,
    required this.adminUpdateUrl,
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

  /// The legacy global floor, kept for clients already in the field.
  final String? minSupportedVersion;
  final String? customerMinSupportedVersion;
  final String? merchantMinSupportedVersion;
  final String? adminMinSupportedVersion;
  final String? customerUpdateUrl;
  final String? merchantUpdateUrl;
  final String? adminUpdateUrl;
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
    customerMinSupportedVersion: null,
    merchantMinSupportedVersion: null,
    adminMinSupportedVersion: null,
    customerUpdateUrl: null,
    merchantUpdateUrl: null,
    adminUpdateUrl: null,
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
    int ranged(String key, int fallback) {
      final value = source.read(key);
      final bounds = configBounds[key]!;
      if (value is! int) return fallback;
      if (value < bounds.min || value > bounds.max) return fallback;
      return value;
    }

    String? text(String key) {
      final value = source.read(key);
      return value is String && value.isNotEmpty ? value : null;
    }

    // The fee bounds are validated as a pair: a max below a min describes no valid fee
    // at all, so neither half of a contradictory range is trusted.
    var feeMin = ranged('delivery_fee_min', defaults.deliveryFeeMin);
    var feeMax = ranged('delivery_fee_max', defaults.deliveryFeeMax);
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
      ),
      marketingPushPerWeek: ranged(
        'marketing_push_per_week',
        defaults.marketingPushPerWeek,
      ),
      rejectionBanThreshold: ranged(
        'rejection_ban_threshold',
        defaults.rejectionBanThreshold,
      ),
      minRatingsToShow: ranged(
        'min_ratings_to_show',
        defaults.minRatingsToShow,
      ),
      deliveryFeeMin: feeMin,
      deliveryFeeMax: feeMax,
      splashMinMillis: ranged('splash_min_millis', defaults.splashMinMillis),
      minSupportedVersion: text('min_supported_version'),
      customerMinSupportedVersion: text('customer_min_supported_version'),
      merchantMinSupportedVersion: text('merchant_min_supported_version'),
      adminMinSupportedVersion: text('admin_min_supported_version'),
      customerUpdateUrl: text('customer_update_url'),
      merchantUpdateUrl: text('merchant_update_url'),
      adminUpdateUrl: text('admin_update_url'),
      updateMessage: text('update_message') ?? defaults.updateMessage,
      supportWhatsapp:
          text('support_whatsapp') ??
          text('supportWhatsapp') ??
          defaults.supportWhatsapp,
      aboutPhotoMediaId: text('about_photo_media_id'),
      aboutFacebook: text('about_facebook'),
      aboutWhatsapp: text('about_whatsapp'),
      aboutInstagram: text('about_instagram'),
      aboutDescription: text('about_description'),
    );
  }

  /// Compiled destinations used until the control plane supplies an app-specific URL.
  /// AdminApp is distributed directly as an APK and deliberately has no store default.
  static const compiledUpdateUrls = <LuqmaApp, String>{
    LuqmaApp.customer:
        'https://play.google.com/store/apps/details?id=com.luqma.customer',
    LuqmaApp.merchant:
        'https://play.google.com/store/apps/details?id=com.luqma.merchant',
  };

  String? minSupportedVersionFor(LuqmaApp app) {
    final appMinimum = switch (app) {
      LuqmaApp.customer => customerMinSupportedVersion,
      LuqmaApp.merchant => merchantMinSupportedVersion,
      LuqmaApp.admin => adminMinSupportedVersion,
    };
    return appMinimum ?? minSupportedVersion;
  }

  Uri? updateUrlFor(LuqmaApp app) {
    final configured = switch (app) {
      LuqmaApp.customer => customerUpdateUrl,
      LuqmaApp.merchant => merchantUpdateUrl,
      LuqmaApp.admin => adminUpdateUrl,
    };
    final raw = configured ?? compiledUpdateUrls[app];
    if (raw == null) return null;
    final uri = Uri.tryParse(raw);
    return uri != null && uri.isAbsolute ? uri : null;
  }

  /// Whether [currentVersion] is below the minimum the backend still supports.
  ///
  /// Compared segment by segment as numbers. Comparing the strings would put 1.10
  /// below 1.4 and lock out the newest build in the field.
  bool requiresUpdate(String currentVersion) {
    return _requiresUpdate(minSupportedVersion, currentVersion);
  }

  bool requiresUpdateFor(LuqmaApp app, String currentVersion) {
    return _requiresUpdate(minSupportedVersionFor(app), currentVersion);
  }

  static bool _requiresUpdate(String? minimumVersion, String currentVersion) {
    final minimum = _parseVersion(minimumVersion);
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
