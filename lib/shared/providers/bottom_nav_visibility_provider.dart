import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the bottom nav bar (AppShell's footer) should currently be
/// shown, driven by Home's own scroll direction.
///
/// Added 2026-09-30 per explicit request ("In the Home page of both
/// Groceries and Services only the footer should show otherwise hidden
/// (while hidden and hidden out make it smooth animation)"): Home listens
/// to its own scroll and toggles this — hidden while scrolling down
/// (more room to browse the list), shown again while scrolling up or at
/// rest. [AppShell] is the only place this is read; it only honors it
/// while the Home tab is active, so every other tab's nav bar is
/// unaffected and always visible.
final bottomNavVisibleProvider = StateProvider<bool>((ref) => true);
