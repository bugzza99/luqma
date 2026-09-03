import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The control plane is the one place where a typo made in AdminApp reaches every phone
/// at once. So the contract is narrow on purpose: a value is used only if it is present,
/// the right type, and inside a range the app can actually operate in. Anything else
/// falls back to the value compiled into the binary.
void main() {
  LuqmaConfig configFrom(Map<String, Object> values) =>
      LuqmaConfig.from(MapConfigSource(values));

  group('cold start', () {
    test('an empty source yields the compiled-in defaults', () {
      final config = configFrom({});
      expect(config.acceptTimeoutMinutes, 5);
      expect(config.marketingPushPerWeek, 0);
      expect(config.rejectionBanThreshold, 3);
      expect(config.minRatingsToShow, 10);
    });

    test('the flags that were decided to ship off are off by default', () {
      final config = configFrom({});
      expect(config.otpEnabled, isFalse);
      expect(config.admobEnabled, isFalse);
      expect(config.publicCommentsEnabled, isFalse);
      expect(config.onlinePaymentEnabled, isFalse);
    });

    test('marketing push is closed until a real delivery pipeline ships', () {
      expect(LuqmaConfig.defaults.marketingPushPerWeek, 0);
    });
  });

  group('remote values', () {
    test('a present value replaces its default', () {
      final config = configFrom({'accept_timeout_minutes': 8});
      expect(config.acceptTimeoutMinutes, 8);
    });

    test('a flag can be switched on remotely', () {
      final config = configFrom({'otp_enabled': true});
      expect(config.otpEnabled, isTrue);
    });

    group('support WhatsApp compatibility', () {
      test('reads the canonical key', () {
        expect(configFrom({'support_whatsapp': '010'}).supportWhatsapp, '010');
      });

      test('falls back to the legacy key', () {
        expect(configFrom({'supportWhatsapp': '011'}).supportWhatsapp, '011');
      });

      test('prefers the canonical key when both exist', () {
        expect(
          configFrom({
            'support_whatsapp': '010',
            'supportWhatsapp': '011',
          }).supportWhatsapp,
          '010',
        );
      });

      test('defaults to empty when neither key exists', () {
        expect(configFrom({}).supportWhatsapp, '');
      });
    });
  });

  group('bad values never reach the app', () {
    test('a value of the wrong type is ignored', () {
      final config = configFrom({'accept_timeout_minutes': 'خمسة'});
      expect(config.acceptTimeoutMinutes, 5);
    });

    // Zero would move every order to needsAttention the instant it was placed, and
    // there would be no way to undo it from the phone that caused it.
    test('an accept timeout of zero is rejected, not obeyed', () {
      final config = configFrom({'accept_timeout_minutes': 0});
      expect(config.acceptTimeoutMinutes, 5);
    });

    test('an absurdly long accept timeout is rejected', () {
      final config = configFrom({'accept_timeout_minutes': 600});
      expect(config.acceptTimeoutMinutes, 5);
    });

    test('a negative push cap is rejected', () {
      final config = configFrom({'marketing_push_per_week': -1});
      expect(config.marketingPushPerWeek, 0);
    });

    test('a rejection threshold below one is rejected', () {
      // Zero would auto-block every customer on their first refused delivery.
      final config = configFrom({'rejection_ban_threshold': 0});
      expect(config.rejectionBanThreshold, 3);
    });

    test('a delivery fee range with max below min is ignored entirely', () {
      final config = configFrom({
        'delivery_fee_min': 3000,
        'delivery_fee_max': 500,
      });
      expect(config.deliveryFeeMin, LuqmaConfig.defaults.deliveryFeeMin);
      expect(config.deliveryFeeMax, LuqmaConfig.defaults.deliveryFeeMax);
    });

    test('one bad key does not discard the good keys beside it', () {
      final config = configFrom({
        'accept_timeout_minutes': 0,
        'marketing_push_per_week': 5,
      });
      expect(config.acceptTimeoutMinutes, 5, reason: 'rejected');
      expect(config.marketingPushPerWeek, 5, reason: 'accepted');
    });
  });

  group('force update', () {
    test('no minimum version means no update is required', () {
      final config = configFrom({});
      expect(config.requiresUpdate('1.0.0'), isFalse);
    });

    test('an older build is asked to update', () {
      final config = configFrom({'min_supported_version': '1.4.0'});
      expect(config.requiresUpdate('1.3.9'), isTrue);
    });

    test('the exact minimum build is not asked to update', () {
      final config = configFrom({'min_supported_version': '1.4.0'});
      expect(config.requiresUpdate('1.4.0'), isFalse);
    });

    test('a newer build is not asked to update', () {
      final config = configFrom({'min_supported_version': '1.4.0'});
      expect(
        config.requiresUpdate('1.10.0'),
        isFalse,
        reason:
            '1.10 is above 1.4 — comparing as text would get this backwards',
      );
    });

    test('an unparseable minimum version blocks nobody', () {
      final config = configFrom({'min_supported_version': 'الإصدار الأخير'});
      expect(config.requiresUpdate('1.0.0'), isFalse);
    });

    test('an app-specific floor wins over the legacy global floor', () {
      final config = configFrom({
        'min_supported_version': '9.0.0',
        'customer_min_supported_version': '1.4.0',
      });

      expect(config.requiresUpdateFor(LuqmaApp.customer, '1.4.0'), isFalse);
      expect(config.requiresUpdateFor(LuqmaApp.merchant, '1.4.0'), isTrue);
    });

    test('each app falls back to the legacy global floor', () {
      final config = configFrom({'min_supported_version': '2.0.0'});

      for (final app in LuqmaApp.values) {
        expect(config.requiresUpdateFor(app, '1.9.9'), isTrue);
      }
    });

    test('configured update URL wins for its app', () {
      final config = configFrom({
        'customer_update_url': 'https://updates.example/customer.apk',
      });

      expect(
        config.updateUrlFor(LuqmaApp.customer).toString(),
        'https://updates.example/customer.apk',
      );
    });

    test('customer and merchant have compiled Play defaults', () {
      final config = configFrom({});

      expect(
        config.updateUrlFor(LuqmaApp.customer).toString(),
        contains('com.luqma.customer'),
      );
      expect(
        config.updateUrlFor(LuqmaApp.merchant).toString(),
        contains('com.luqma.merchant'),
      );
    });

    test('admin has no compiled update destination', () {
      expect(configFrom({}).updateUrlFor(LuqmaApp.admin), isNull);
    });
  });

  test('configBounds contains the exact numeric contract', () {
    expect(configBounds['accept_timeout_minutes']?.min, 1);
    expect(configBounds['accept_timeout_minutes']?.max, 60);
    expect(configBounds['marketing_push_per_week']?.min, 0);
    expect(configBounds['marketing_push_per_week']?.max, 21);
    expect(configBounds['rejection_ban_threshold']?.min, 1);
    expect(configBounds['rejection_ban_threshold']?.max, 50);
    expect(configBounds['min_ratings_to_show']?.min, 0);
    expect(configBounds['min_ratings_to_show']?.max, 1000);
    expect(configBounds['splash_min_millis']?.min, 0);
    expect(configBounds['splash_min_millis']?.max, 5000);
    expect(configBounds['delivery_fee_min']?.min, 0);
    expect(configBounds['delivery_fee_max']?.max, 100000);
  });
}
