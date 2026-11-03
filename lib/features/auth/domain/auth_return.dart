import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/app_router.dart';

/// True while the sign-in screens were opened OVER another screen (a booking form, checkout, a list that needs an
/// account...), so that finishing sign-in puts the customer back exactly where they were, with what they had typed.
/// False when sign-in is the start of a journey (first launch): they go Home.
final returnAfterLoginProvider = StateProvider<bool>((ref) => false);

/// Names of the pages that make up the sign-in flow (the route names in app_router.dart).
const _authPageNames = {'login', 'otp-verify', 'profile-complete'};

/// "You need an account for this": opens sign-in over the current screen and remembers to come back.
/// Use this instead of `context.push('/login')` at every login gate.
void requireLogin(BuildContext context, WidgetRef ref) => requireLoginWith(GoRouter.of(context), ref);

/// Same as [requireLogin] for callers that no longer hold a usable context (for example after closing a sheet).
void requireLoginWith(GoRouter router, WidgetRef ref) {
  ref.read(returnAfterLoginProvider.notifier).state = true;
  router.push(AppRoutes.login);
}

/// The sign-in is done. Back to the screen that asked for it (state intact), or to [fallback] when sign-in was not
/// opened over anything.
void finishSignIn(BuildContext context, WidgetRef ref, {String fallback = AppRoutes.home}) {
  final back = ref.read(returnAfterLoginProvider);
  ref.read(returnAfterLoginProvider.notifier).state = false;
  if (!back) {
    context.go(fallback);
    return;
  }
  // Pop only the sign-in pages that were pushed over the original screen.
  final navigator = rootNavigatorKey.currentState;
  if (navigator == null) {
    context.go(fallback);
    return;
  }
  navigator.popUntil((route) => !_authPageNames.contains(route.settings.name));
}
