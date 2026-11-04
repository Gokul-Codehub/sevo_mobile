import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/errors/api_error.dart';
import '../../coverage/data/coverage_repository.dart';

enum PlaceSearchStatus {
  /// Nothing typed yet (or fewer than [PlaceSearch.minChars] characters).
  idle,
  loading,
  results,

  /// The proxy answered but found nothing for this text.
  empty,

  /// The proxy could not be reached or refused (key off, rate limit, offline).
  unavailable,
}

String _randomToken() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = Random.secure();
  return List.generate(24, (_) => chars[r.nextInt(chars.length)]).join();
}

/// Place suggestions while the customer types an address, through our own proxy (never Google directly).
///
///  * Starts at [minChars] characters and waits [debounce] after the last keystroke.
///  * ONE fresh session token per search: every autocomplete call of that search and the final details call of the
///    chosen suggestion share it (Google bills them as one session). After a pick, or once the box is cleared, the
///    next search gets a new token.
///  * A late answer for text the customer has since changed is ignored.
///  * Never throws: if the proxy fails the status becomes [PlaceSearchStatus.unavailable] and the screen's manual
///    address entry carries on.
class PlaceSearch extends ChangeNotifier {
  PlaceSearch({
    required this.autocomplete,
    required this.details,
    this.debounce = const Duration(milliseconds: 300),
    this.minChars = 3,
    String Function()? newToken,
  }) : _newToken = newToken ?? _randomToken;

  final Future<Result<List<PlaceSuggestion>>> Function(String text, String session, double? lat, double? lng) autocomplete;
  final Future<Result<PlaceDetails>> Function(PlaceSuggestion suggestion, String session) details;
  final Duration debounce;
  final int minChars;
  final String Function() _newToken;

  PlaceSearchStatus _status = PlaceSearchStatus.idle;
  List<PlaceSuggestion> _suggestions = const [];
  String? _session;
  Timer? _timer;
  int _seq = 0;
  bool _disposed = false;

  PlaceSearchStatus get status => _status;
  List<PlaceSuggestion> get suggestions => _suggestions;

  /// The token of the search in progress, if any (exposed for tests).
  String? get session => _session;

  void _set(PlaceSearchStatus status, [List<PlaceSuggestion> suggestions = const []]) {
    if (_disposed) return;
    _status = status;
    _suggestions = suggestions;
    notifyListeners();
  }

  /// Call on every change of the search box.
  void onChanged(String text, {double? lat, double? lng}) {
    final q = text.trim();
    _timer?.cancel();
    _seq++; // anything still in flight is now stale
    if (q.length < minChars) {
      _session = null; // the search ended: the next one starts a new session
      _set(PlaceSearchStatus.idle);
      return;
    }
    _session ??= _newToken();
    final session = _session!;
    final mine = _seq;
    _timer = Timer(debounce, () async {
      _set(PlaceSearchStatus.loading, _suggestions);
      final result = await autocomplete(q, session, lat, lng);
      if (_disposed || mine != _seq) return;
      switch (result) {
        case Success(:final data):
          _set(data.isEmpty ? PlaceSearchStatus.empty : PlaceSearchStatus.results, data);
        case Failure():
          _set(PlaceSearchStatus.unavailable);
      }
    });
  }

  /// Fetches the chosen place with the SAME session token, then ends the session.
  /// Null when the details could not be fetched (the screen then keeps manual entry).
  Future<PlaceDetails?> select(PlaceSuggestion suggestion) async {
    _timer?.cancel();
    _seq++;
    final session = _session ?? _newToken();
    final result = await details(suggestion, session);
    _session = null;
    switch (result) {
      case Success(:final data):
        _set(PlaceSearchStatus.idle);
        return data;
      case Failure():
        _set(PlaceSearchStatus.unavailable);
        return null;
    }
  }

  /// Clears suggestions and ends the session (box emptied, screen left).
  void reset() {
    _timer?.cancel();
    _seq++;
    _session = null;
    _set(PlaceSearchStatus.idle);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
