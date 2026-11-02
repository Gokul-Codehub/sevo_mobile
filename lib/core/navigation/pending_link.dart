/// A screen the customer was heading to (from a notification tap) before they had to sign in.
/// After sign-in the app continues there. Only account-specific in-app paths are ever stored.
class PendingLink {
  PendingLink._();

  static String? _route;

  /// Paths that belong to the signed-in customer's own data.
  static bool needsSignIn(String route) {
    final path = route.split('?').first;
    return path.startsWith('/bookings') || path.startsWith('/tracking') || path.startsWith('/orders') || path.startsWith('/notifications');
  }

  static void set(String route) => _route = route;

  /// Returns the stored route once, then forgets it.
  static String? take() {
    final r = _route;
    _route = null;
    return r;
  }

  static bool get hasPending => _route != null;
}
