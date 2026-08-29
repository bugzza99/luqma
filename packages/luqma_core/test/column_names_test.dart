import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The one translation between Postgres and the models.
///
/// The database is `snake_case` because unquoted identifiers in Postgres fold to lower
/// case — `merchantId` silently becomes `merchantid` — and quoting every identifier for
/// ever would poison every policy and every query typed by hand. The models keep the
/// camelCase JSON they already had, so nothing above this line learns that the backend
/// changed.
///
/// Fifteen lines, written once. Getting it wrong means a field arrives null and a screen
/// renders a blank where a price should be, which is why it is tested rather than assumed.
void main() {
  group('reading a row', () {
    test('a single word is unchanged', () {
      expect(ColumnNames.toModel({'name': 'كشري'}), {'name': 'كشري'});
    });

    test('two words become one camelCase key', () {
      expect(ColumnNames.toModel({'merchant_id': 'm1'}), {'merchantId': 'm1'});
    });

    test('three words too', () {
      expect(
        ColumnNames.toModel({'rejected_orders_count': 3}),
        {'rejectedOrdersCount': 3},
      );
    });

    test('values are untouched, whatever they are', () {
      final row = {
        'total_qty': 20,
        'rating_avg': 4.5,
        'is_active': true,
        'paused_until': null,
      };

      expect(ColumnNames.toModel(row), {
        'totalQty': 20,
        'ratingAvg': 4.5,
        'isActive': true,
        'pausedUntil': null,
      });
    });

    // `options`, `items`, `pricing` and the rest arrive as decoded JSON. Their *inner*
    // keys were written by the app and are already camelCase — renaming them again would
    // turn `unitPrice` into something no model knows.
    test('a nested map keeps the keys it was stored with', () {
      final row = {
        'menu_item': {'unitPrice': 1200, 'optionsTotal': 0},
      };

      expect(ColumnNames.toModel(row), {
        'menuItem': {'unitPrice': 1200, 'optionsTotal': 0},
      });
    });

    test('a list of maps is left alone too', () {
      final row = {
        'status_history': [
          {'status': 'placed', 'atMinute': 10},
        ],
      };

      expect(ColumnNames.toModel(row), {
        'statusHistory': [
          {'status': 'placed', 'atMinute': 10},
        ],
      });
    });
  });

  group('writing a row', () {
    test('camelCase becomes snake_case', () {
      expect(ColumnNames.toRow({'merchantId': 'm1'}), {'merchant_id': 'm1'});
    });

    test('a single word is unchanged', () {
      expect(ColumnNames.toRow({'name': 'كشري'}), {'name': 'كشري'});
    });

    test('a longer name splits at every hump', () {
      expect(
        ColumnNames.toRow({'defaultDeliveryFee': 800}),
        {'default_delivery_fee': 800},
      );
    });

    // The models carry `id` and the tables carry `id`. A round trip has to survive it.
    test('a round trip returns what went in', () {
      final model = {
        'id': 'z1',
        'cityId': 'edku',
        'defaultDeliveryFee': 800,
        'isActive': true,
        'sortOrder': 0,
      };

      expect(ColumnNames.toModel(ColumnNames.toRow(model)), model);
    });
  });

  group('what it refuses to mangle', () {
    // A key that is already snake_case on the way out would otherwise become
    // `merchant__id`, and the insert would fail on a column nobody has.
    test('a key that is already snake_case survives being written', () {
      expect(ColumnNames.toRow({'merchant_id': 'm1'}), {'merchant_id': 'm1'});
    });

    test('an empty map is an empty map', () {
      expect(ColumnNames.toModel(const {}), const <String, dynamic>{});
      expect(ColumnNames.toRow(const {}), const <String, dynamic>{});
    });
  });
}
