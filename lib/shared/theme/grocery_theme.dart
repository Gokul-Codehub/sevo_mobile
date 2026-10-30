import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Wraps a Groceries & Vegetables screen in the green grocery theme, so its
/// default buttons, links, chips, inputs and spinners are green instead of
/// the app-wide Services blue/navy. Used on the grocery routes in
/// app_router.dart.
class GroceryTheme extends StatelessWidget {
  const GroceryTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Theme(data: AppTheme.grocery, child: child);
}
