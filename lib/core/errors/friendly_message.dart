/// Turns anything that reaches a customer-facing toast, banner or snackbar into plain, kind language.
///
/// Messages the server wrote for people ("Maximum of 10 saved addresses allowed.") pass through
/// untouched. Anything that looks technical (exception names, status codes, schema or config
/// complaints) is replaced, so customers never see developer text.
abstract final class FriendlyMessage {
  FriendlyMessage._();

  static const String offline = "We couldn't reach SEVO. Please check your internet connection and try again.";
  static const String server = 'Something went wrong on our side. Please try again in a moment.';
  static const String generic = "We couldn't complete that. Please try again.";
  static const String unavailable = "This isn't available right now. Please try again a little later.";

  static String polish(String raw) {
    var m = raw.trim();
    // "UnknownError: foo", "Exception: foo", "ValidationError(foo)" -> "foo"
    for (var i = 0; i < 2; i++) {
      m = m.replaceFirst(RegExp(r'^[A-Za-z]*(?:Error|Exception)\s*:\s*'), '').trim();
    }
    final wrapped = RegExp(r'^[A-Za-z]+Error\((.*)\)$', dotAll: true).firstMatch(m);
    if (wrapped != null) m = (wrapped.group(1) ?? '').trim();
    if (m.isEmpty) return generic;

    final l = m.toLowerCase();
    bool has(List<String> words) => words.any(l.contains);

    // Connectivity
    if (has(['socketexception', 'failed host lookup', 'connection refused', 'connection reset', 'handshake', 'network is unreachable', 'connection error', 'connection closed'])) {
      return offline;
    }
    if (has(['timed out', 'timeout'])) return 'This is taking longer than usual. Please check your connection and try again.';
    if (l == 'request was cancelled.' || l == 'request cancelled.') return generic;

    // Server-side trouble
    if (has(['internal server error', 'bad gateway', 'service unavailable', 'gateway time']) || RegExp(r'status code of 5\d\d').hasMatch(l)) {
      return server;
    }

    // Setup / configuration complaints that mean nothing to a customer
    if (has(['company context', 'operating company', 'company_context_required'])) return unavailable;
    if (has(['not configured', 'not been configured', 'configuration'])) return unavailable;
    if (has(['not found on production server', 'resource was not found', 'resource not found'])) {
      return "We couldn't find that. It may have been removed or is no longer available.";
    }
    if (l == 'bad request.' || l == 'bad request') return 'Some details need your attention. Please check and try again.';

    // Session / access
    if (has(['session expired', 'token expired', 'token is invalid', 'credentials were not provided'])) {
      return 'Your session has ended. Please sign in again.';
    }
    if (has(['you do not have permission', 'not permitted'])) return "This account can't do that. Please contact support if you think this is a mistake.";

    // Whole-message OTP phrasing
    if (RegExp(r'^(invalid|incorrect|wrong) (otp|code)\.?$').hasMatch(l)) return "That code doesn't look right. Please check it and try again.";
    if (RegExp(r'^(otp|code) (has )?expired\.?$').hasMatch(l)) return 'That code has expired. Tap Resend to get a new one.';
    if (has(['request was throttled', 'too many requests', 'rate limit'])) return 'Too many attempts. Please wait a moment and try again.';

    // Developer text
    if (has(['dioexception', 'status code', 'is not a subtype', 'null check', 'nosuchmethod', 'formatexception', 'unexpected character', 'unexpected response', 'unexpected product', 'unexpected basket', 'unexpected notifications', 'api contract', 'traceback', 'stack trace', 'type \'', 'instance of'])) {
      return generic;
    }
    if (RegExp(r'[{}<>]').hasMatch(m)) return generic;
    if (has(['failed to load', 'failed to fetch', 'failed to get'])) return "We couldn't load that. Please pull down to refresh or try again.";
    if (m.length > 220) return generic;
    return m;
  }

  /// Same as [polish] for any thrown object.
  static String of(Object? error, {String? message}) {
    if (message != null) return polish(message);
    return polish(error?.toString() ?? '');
  }
}
