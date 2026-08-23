import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Whether a merchant can take an order right now is derived, never stored — three
/// fields answering one question is three fields that can disagree. Everything below is
/// the derivation.
void main() {
  // A Tuesday.
  DateTime at(int hour, int minute, {int day = 18}) =>
      DateTime(2026, 8, day, hour, minute);

  Merchant merchantWith({
    List<OpeningWindow> hours = const [],
    DateTime? pausedUntil,
    MerchantStatus status = MerchantStatus.approved,
  }) {
    return Merchant(
      id: 'm1',
      cityId: 'edku',
      type: MerchantType.restaurant,
      name: 'مطعم الشاطئ',
      zoneId: 'z1',
      phone: '01000000000',
      status: status,
      openingHours: hours,
      pausedUntil: pausedUntil,
    );
  }

  const tuesday = DateTime.tuesday;

  group('opening hours', () {
    test('closed when no hours are set at all', () {
      expect(merchantWith().acceptsOrdersAt(at(13, 0)), isFalse);
    });

    test('open inside the window', () {
      final m = merchantWith(hours: [
        const OpeningWindow(weekday: tuesday, openMinute: 12 * 60, closeMinute: 23 * 60),
      ]);
      expect(m.acceptsOrdersAt(at(13, 0)), isTrue);
    });

    test('closed before it opens and after it closes', () {
      final m = merchantWith(hours: [
        const OpeningWindow(weekday: tuesday, openMinute: 12 * 60, closeMinute: 23 * 60),
      ]);
      expect(m.acceptsOrdersAt(at(11, 59)), isFalse);
      expect(m.acceptsOrdersAt(at(23, 1)), isFalse);
    });

    test('a window belonging to another weekday does not apply', () {
      final m = merchantWith(hours: [
        const OpeningWindow(
          weekday: DateTime.friday,
          openMinute: 12 * 60,
          closeMinute: 23 * 60,
        ),
      ]);
      expect(m.acceptsOrdersAt(at(13, 0)), isFalse);
    });

    // The one that a naive `open <= now && now <= close` gets wrong, and the one that
    // matters most: late-night restaurants are the norm here.
    test('a window that crosses midnight stays open after midnight', () {
      final m = merchantWith(hours: [
        const OpeningWindow(weekday: tuesday, openMinute: 18 * 60, closeMinute: 2 * 60),
      ]);
      expect(m.acceptsOrdersAt(at(19, 0)), isTrue, reason: 'the evening it opened');
      expect(
        m.acceptsOrdersAt(at(0, 30, day: 19)),
        isTrue,
        reason: 'half past midnight belongs to Tuesday night, not Wednesday',
      );
      expect(m.acceptsOrdersAt(at(3, 0, day: 19)), isFalse, reason: 'after it closed');
    });

    test('an overnight window does not reopen the same morning', () {
      final m = merchantWith(hours: [
        const OpeningWindow(weekday: tuesday, openMinute: 18 * 60, closeMinute: 2 * 60),
      ]);
      expect(
        m.acceptsOrdersAt(at(1, 0)),
        isFalse,
        reason: 'Tuesday 1am is the tail of Monday night, which has no window',
      );
    });

    test('two windows in one day are both honoured', () {
      final m = merchantWith(hours: [
        const OpeningWindow(weekday: tuesday, openMinute: 9 * 60, closeMinute: 15 * 60),
        const OpeningWindow(weekday: tuesday, openMinute: 18 * 60, closeMinute: 23 * 60),
      ]);
      expect(m.acceptsOrdersAt(at(10, 0)), isTrue);
      expect(m.acceptsOrdersAt(at(16, 0)), isFalse, reason: 'the afternoon break');
      expect(m.acceptsOrdersAt(at(20, 0)), isTrue);
    });
  });

  group('the busy pause', () {
    final open = [
      const OpeningWindow(weekday: tuesday, openMinute: 0, closeMinute: 24 * 60),
    ];

    test('a pause in the future closes an otherwise open merchant', () {
      final m = merchantWith(hours: open, pausedUntil: at(14, 0));
      expect(m.acceptsOrdersAt(at(13, 30)), isFalse);
    });

    // The reason it is a timestamp and not a boolean: nobody has to remember to undo it.
    test('a pause that has elapsed reopens the merchant on its own', () {
      final m = merchantWith(hours: open, pausedUntil: at(14, 0));
      expect(m.acceptsOrdersAt(at(14, 1)), isTrue);
    });
  });

  group('status', () {
    final open = [
      const OpeningWindow(weekday: tuesday, openMinute: 0, closeMinute: 24 * 60),
    ];

    test('a merchant awaiting approval never accepts orders', () {
      final m = merchantWith(hours: open, status: MerchantStatus.pending);
      expect(m.acceptsOrdersAt(at(13, 0)), isFalse);
    });

    test('a suspended merchant never accepts orders', () {
      final m = merchantWith(hours: open, status: MerchantStatus.suspended);
      expect(m.acceptsOrdersAt(at(13, 0)), isFalse);
    });
  });
}
