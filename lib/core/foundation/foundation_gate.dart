import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../routing/app_router.dart' show rootNavigatorKey;
import '../../shared/utils/app_toast.dart';
import '../network/network_state.dart';
import '../network/session_interceptors.dart';
import 'announcement_host.dart';
import 'foundation_controller.dart';
import 'foundation_models.dart';

/// Mounted above the routed app (main.dart). Loads the server config at start (cache first,
/// never waiting on the network), refreshes on resume, and covers the app with
/// [MaintenanceScreen] only while the server explicitly says maintenance is on.
class FoundationGate extends ConsumerStatefulWidget {
  const FoundationGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<FoundationGate> createState() => _FoundationGateState();
}

class _FoundationGateState extends ConsumerState<FoundationGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SessionNotice.message.addListener(_showSessionNotice);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(foundationControllerProvider.notifier).start());
    });
  }

  @override
  void dispose() {
    SessionNotice.message.removeListener(_showSessionNotice);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _showSessionNotice() {
    final text = SessionNotice.message.value;
    if (text == null) return;
    SessionNotice.message.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = rootNavigatorKey.currentContext;
      if (mounted && context != null) AppToast.show(context, text, type: AppToastType.error);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      unawaited(ref.read(foundationControllerProvider.notifier).refresh(FoundationRefresh.resume));
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = ref.watch(foundationControllerProvider.select((s) => s.maintenanceBlocksApp));
    final info = ref.watch(foundationControllerProvider.select((s) => s.config.maintenance));
    final hasAnnouncement = ref.watch(visibleAnnouncementsProvider.select((l) => l.isNotEmpty));
    final unreachable = ref.watch(networkStateProvider) == NetworkState.serverUnreachable;
    final hasBanner = hasAnnouncement || unreachable;
    return PopScope(
      canPop: !blocked,
      child: Stack(
        children: [
          Column(
            children: [
              const AnnouncementBanner(),
              if (unreachable) ServerUnreachableBanner(withSafeArea: !hasAnnouncement),
              Expanded(
                // The banner already covers the status bar, so the app below must not add it again.
                child: hasBanner ? MediaQuery.removePadding(context: context, removeTop: true, child: widget.child) : widget.child,
              ),
            ],
          ),
          if (blocked) Positioned.fill(child: MaintenanceScreen(info: info)),
        ],
      ),
    );
  }
}

class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key, required this.info});
  final MaintenanceInfo info;

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  Timer? _tick;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.info.eta != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String? _countdown() {
    final eta = widget.info.eta;
    if (eta == null) return null;
    final left = eta.difference(DateTime.now());
    if (left.isNegative) return 'Any moment now';
    final h = left.inHours, m = left.inMinutes.remainder(60), s = left.inSeconds.remainder(60);
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    await ref.read(foundationControllerProvider.notifier).refresh(FoundationRefresh.manual);
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final countdown = _countdown();
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(color: Color(0xFFEAF0F6), shape: BoxShape.circle),
                  child: const Icon(Icons.build_circle_outlined, size: 52, color: AppColors.navy),
                ),
                const SizedBox(height: 24),
                Text(
                  info.title.isEmpty ? 'We are upgrading SEVO' : info.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.navy),
                ),
                const SizedBox(height: 10),
                Text(
                  info.message.isEmpty ? 'We will be back shortly.' : info.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, height: 1.4, color: Colors.black54),
                ),
                if (countdown != null) ...[
                  const SizedBox(height: 18),
                  const Text('Back in', style: TextStyle(fontSize: 12, color: Colors.black45)),
                  Text(countdown, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.navy)),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _retrying ? null : _retry,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.navy, minimumSize: const Size.fromHeight(48)),
                    child: Text(_retrying ? 'Checking...' : 'Try again'),
                  ),
                ),
                const SizedBox(height: 10),
                const Text('We check automatically every 30 seconds.', style: TextStyle(fontSize: 12, color: Colors.black45)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Slim bar shown when the phone is online but SEVO's server cannot be reached. The app stays usable.
class ServerUnreachableBanner extends StatelessWidget {
  const ServerUnreachableBanner({super.key, this.withSafeArea = true});
  final bool withSafeArea;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: const [
          Icon(Icons.cloud_off_rounded, size: 16, color: Colors.white),
          SizedBox(width: 8),
          Expanded(
            child: Text('We could not reach SEVO. Retrying...', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return Material(
      color: const Color(0xFFB26A00),
      child: withSafeArea ? SafeArea(bottom: false, child: row) : row,
    );
  }
}
