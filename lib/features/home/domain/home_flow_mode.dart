import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which themed variant of Home is currently shown.
///
/// Added 2026-09-19 per explicit request ("like amazon and flipkart... by
/// choosing the top category like Groceries and Services let us render two
/// different home page cards, color theme and all"): tapping the
/// Groceries/Services quick-access card on Home no longer navigates away —
/// it switches which fully-themed version of the Home screen is rendered,
/// the same way Amazon's app switches between "Amazon"/"Fresh" or
/// Flipkart switches its top category tabs.
enum HomeFlowMode { services, groceries }

/// Defaults to [HomeFlowMode.groceries]: the app opens on the Groceries &
/// Vegetables home, and the customer can switch to Services from the top
/// card. In-memory only (resets to groceries on a fresh app launch).
final homeFlowModeProvider =
    StateProvider<HomeFlowMode>((ref) => HomeFlowMode.groceries);
