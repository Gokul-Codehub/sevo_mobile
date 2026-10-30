import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../routing/app_router.dart' show rootNavigatorKey;
import '../../../shared/theme/app_colors.dart';
import '../../booking/domain/cart_notifier.dart' show isUserAuthenticatedProvider;
import '../domain/app_update_controller.dart';
import '../domain/app_update_models.dart';
import 'update_widgets.dart';

/// Mounted once above the whole routed app (main.dart). It
///  * checks for an update at start, on resume (throttled) and after sign-in -
///    in the background, so startup never waits on it;
///  * covers the app with [MandatoryUpdateScreen] while the installed build is
///    below the supported minimum (and blocks Android back);
///  * offers the optional update dialog once per session / snooze window.
class AppUpdateGate extends ConsumerStatefulWidget {
  const AppUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends ConsumerState<AppUpdateGate> with WidgetsBindingObserver {
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(appUpdateControllerProvider.notifier).check(CheckReason.startup);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      // Also re-reads the installed build, so coming back from the Play Store
      // after updating unlocks the app only if the build really changed.
      ref.read(appUpdateControllerProvider.notifier).check(CheckReason.resume);
    }
  }

  void _maybeShowOptionalDialog(AppUpdateState state) {
    if (!state.optionalPromptPending || _dialogOpen || state.isMandatory) return;
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    _dialogOpen = true;
    ref.read(appUpdateControllerProvider.notifier).optionalPromptShown();
    showDialog<void>(context: context, builder: (_) => const OptionalUpdateDialog()).whenComplete(() => _dialogOpen = false);
  }

  void _maybeShowRestartPrompt(AppUpdateState state) {
    if (!state.flexibleDownloaded || state.isMandatory) return;
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Update ready', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)),
        content: const Text('The new version has been downloaded. Restart SEVO to finish updating.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Later')),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(appUpdateControllerProvider.notifier).installDownloadedUpdate();
            },
            child: const Text('Restart now'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppUpdateState>(appUpdateControllerProvider, (previous, next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybeShowOptionalDialog(next);
        if (previous?.flexibleDownloaded != true && next.flexibleDownloaded) _maybeShowRestartPrompt(next);
      });
    });
    ref.listen<bool>(isUserAuthenticatedProvider, (previous, next) {
      if (next && previous != true) ref.read(appUpdateControllerProvider.notifier).check(CheckReason.afterLogin);
    });

    final mandatory = ref.watch(appUpdateControllerProvider.select((s) => s.isMandatory));
    return PopScope(
      canPop: !mandatory, // no Android-back out of the required-update screen
      child: Stack(
        children: [
          widget.child,
          if (mandatory) const Positioned.fill(child: MandatoryUpdateScreen()),
        ],
      ),
    );
  }
}
