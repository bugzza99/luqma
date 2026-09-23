import 'dart:convert';
import 'dart:io';

import 'package:admin_app/src/merchants/merchants_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The row AdminApp sends when it adds a shop, pinned to a file the database tests read.
///
/// `merchants_start_with_nothing` (`20261101010000_a_moderator_cannot_move_money.sql`)
/// refuses a moderator a new shop with anything in its money columns, and the proof that it
/// still lets the real form through has to be made with the real form's row. A hand-written
/// imitation in the SQL test would pass the day `rowFor` started sending a `plan_id`, and
/// every moderator would then meet «مااتحفظتش» on the one shop-creation screen there is.
///
/// So the payload lives in `supabase/test/fixtures/admin_app_creates_a_shop.json`, the
/// PGlite and stack tests insert exactly that, and this test fails when it stops being what
/// `MerchantActions.create` hands `SupabaseMerchantRepository.rowFor`.
void main() {
  test('the fixture is the row the create form sends', () async {
    final fixture = Map<String, dynamic>.from(jsonDecode(
      File('../../supabase/test/fixtures/admin_app_creates_a_shop.json').readAsStringSync(),
    ) as Map);

    final container = ProviderContainer(overrides: [
      merchantRepositoryProvider.overrideWithValue(FakeMerchantRepository()),
    ]);
    addTearDown(container.dispose);

    final created = await container.read(merchantActionsProvider.notifier).create(
          id: fixture['id'] as String,
          name: fixture['name'] as String,
          phone: fixture['phone'] as String,
          zoneId: fixture['zone_id'] as String,
          type: MerchantType.restaurant,
        );

    // What `createMerchant` puts on the wire: the row, and the id the form minted.
    final sent = {
      ...SupabaseMerchantRepository.rowFor(created.valueOrNull!),
      'id': created.valueOrNull!.id,
    };

    expect(sent, fixture);
  });
}
