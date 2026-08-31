import 'package:flutter/material.dart';
import 'package:luqma_core/luqma_core.dart';

import 'sections/ad_slot_section.dart';
import 'sections/category_chips_section.dart';
import 'sections/home_kitchen_section.dart';
import 'sections/merchant_list_section.dart';
import 'sections/popular_items_section.dart';

/// The fixed map of section types the app is willing to draw.
///
/// This is the boundary that keeps a server-composed home from being server-driven UI.
/// The owner chooses which of these appear, their order, and their parameters; the app
/// owns what each one actually is. Adding a genuinely new kind of block is a release —
/// which is the right price for it, and far cheaper than a runtime that can render
/// anything and therefore has to be tested against everything.
abstract final class HomeSectionRegistry {
  const HomeSectionRegistry._();

  static final Map<String, Widget Function(HomeSection)> _builders = {
    'categoryChips': (s) => CategoryChipsSection(section: s),
    'adSlot': (s) => AdSlotSection(section: s),
    'homeKitchenToday': (s) => HomeKitchenSection(section: s),
    'mostOrdered': (s) => PopularItemsSection(section: s),
    'merchantList': (s) => MerchantListSection(section: s),
    'topRated': (s) => MerchantListSection(section: s, topRated: true),
  };

  static bool knows(String type) => _builders.containsKey(type);

  /// The sections to render, in order.
  ///
  /// Hidden ones are dropped, and so is anything naming a type this build does not have
  /// — a typo made in AdminApp reaches every phone at once, and it must cost that one
  /// block rather than the whole screen. The same filter also makes a build older than
  /// the config degrade gracefully instead of crashing.
  static List<HomeSection> plan(List<HomeSection> sections) {
    final usable = sections
        .where((s) => s.isVisible && knows(s.type))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return usable;
  }

  /// The widget for one section, or null if this build cannot draw it.
  ///
  /// Null rather than a placeholder: a block the app does not understand should leave no
  /// trace, not a gap that looks like something failed to load.
  static Widget? build(HomeSection section) => _builders[section.type]?.call(section);
}
