import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reports whether the device currently has *some* network interface up
/// (Wi-Fi / mobile data / ethernet / VPN).
///
/// Added for the "No Internet" screen (see [ConnectivityGate] /
/// [NoInternetScreen]). `connectivity_plus` was already a declared
/// dependency in pubspec.yaml but had never actually been wired into any
/// screen — every API-driven screen only ever found out it was offline
/// the hard way, from a failed request surfacing [NetworkError].
///
/// This is a link-layer check only: it answers "is there a route to the
/// network at all", not "can this app actually reach its backend". A
/// phone connected to a Wi-Fi network with no real internet behind it
/// (a captive portal, a dead router) will still read as "online" here —
/// that gap is exactly what [ErrorInterceptor]'s per-request
/// [NetworkError] already covers, and is deliberately left to it rather
/// than duplicated here.
final connectivityStatusProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  final initial = await connectivity.checkConnectivity();
  yield _isOnline(initial);
  yield* connectivity.onConnectivityChanged.map(_isOnline);
});

bool _isOnline(List<ConnectivityResult> results) =>
    results.any((result) => result != ConnectivityResult.none);
