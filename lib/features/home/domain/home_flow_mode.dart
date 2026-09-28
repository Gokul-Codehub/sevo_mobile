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

/// Defaults to [HomeFlowMode.services] per explicit decision — booking
/// services is this app's primary business line, matching what the app
/// already showed before this redesign. In-memory only for now (resets to
/// services on a fresh app launch, doesn't persist across restarts); that's
/// a deliberate, smaller first cut — swap this for a
/// SharedPreferences-backed provider later if "remember my last choice" is
/// wanted.
final homeFlowModeProvider =
    StateProvider<HomeFlowMode>((ref) => HomeFlowMode.services);
