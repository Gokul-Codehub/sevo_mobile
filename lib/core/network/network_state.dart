import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../foundation/foundation_controller.dart';
import '../services/connectivity_service.dart';

/// What the customer can actually rely on right now.
///  * offline            - the phone has no network at all (the existing No Internet screen covers this)
///  * serverUnreachable  - the phone is online but SEVO's server could not be reached (slim banner, app stays usable)
///  * online             - everything normal
enum NetworkState { online, offline, serverUnreachable }

final networkStateProvider = Provider<NetworkState>((ref) {
  final link = ref.watch(connectivityStatusProvider).valueOrNull;
  if (link == false) return NetworkState.offline;
  final serverOk = ref.watch(foundationControllerProvider.select((s) => s.lastFetchOk));
  if (serverOk == false) return NetworkState.serverUnreachable;
  return NetworkState.online;
});
