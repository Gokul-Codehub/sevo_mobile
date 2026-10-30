/// In-memory queue of client errors, sent to `POST /api/app/errors/` when the server is reachable
/// (a fallback for when no crash service is configured). It never throws and never grows unbounded.
abstract final class ErrorReporter {
  ErrorReporter._();

  static const int maxQueued = 20;
  static final List<Map<String, String>> _queue = [];

  /// Records an error. Only the error type and a short, trimmed message are kept - never the stack's data.
  static void record(Object error, {String screen = '', String level = 'error'}) {
    try {
      final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      final message = '${error.runtimeType}: ${text.length > 200 ? text.substring(0, 200) : text}';
      if (_queue.isNotEmpty && _queue.last['message'] == message) return; // collapse repeats
      if (_queue.length >= maxQueued) _queue.removeAt(0);
      _queue.add({'message': message, 'screen': screen, 'level': level});
    } catch (_) {}
  }

  static int get pending => _queue.length;

  static List<Map<String, String>> drain() {
    final out = List<Map<String, String>>.from(_queue);
    _queue.clear();
    return out;
  }

  static void restore(List<Map<String, String>> items) {
    for (final i in items) {
      if (_queue.length < maxQueued) _queue.insert(0, i);
    }
  }

  static void clearForTest() => _queue.clear();
}
