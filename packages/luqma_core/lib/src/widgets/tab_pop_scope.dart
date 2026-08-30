import 'package:flutter/material.dart';

/// Makes system back return to the first tab of a shell before it is allowed to exit
/// the app.
///
/// Every tabbed shell in this product shows the next tab in place — an `IndexedStack`,
/// never a pushed route — so scroll position and loaded data survive the switch. What
/// that costs: once somebody is on a tab other than the first, the root `Navigator`'s
/// stack still holds exactly one entry, the shell itself. System back finds nothing to
/// pop, and Android falls through to closing the app, which reads exactly like a crash
/// to someone who meant to go back one tab, not out of it entirely.
///
/// Wraps the shell rather than the tab bar, and reads the current index rather than
/// owning it — the shell already knows which tab is showing (a provider, a local
/// `_tab`, whatever it happens to be), and this widget's whole job is to intercept the
/// one thing none of them do on their own: a back press with nowhere to pop to.
class LuqmaTabPopScope extends StatelessWidget {
  const LuqmaTabPopScope({
    super.key,
    required this.currentIndex,
    required this.onHome,
    required this.child,
  });

  /// The tab index currently showing.
  final int currentIndex;

  /// Returns to the first tab. Called only when [currentIndex] is not already 0 — from
  /// there, back is let through, which is the correct place for it to actually exit.
  final VoidCallback onHome;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        onHome();
      },
      child: child,
    );
  }
}
