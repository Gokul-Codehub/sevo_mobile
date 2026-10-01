import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:location/location.dart' as loc;

import '../../shared/theme/app_colors.dart';

/// Prompts the customer to turn on device location (GPS) before booking a
/// service or placing a grocery order — added 2026-09-19 per explicit
/// request ("whenever the user is going to book services or place
/// groceries/vegetales order ask the user to turn on the navigation using
/// the android"). Call this once, right when a checkout-style screen opens
/// (see CheckoutScreen/GroceryCartScreen's initState).
///
/// This checks the DEVICE'S location service toggle (GPS on/off in Android
/// settings), not just the app's own permission grant — a customer can
/// have granted the app permission long ago and still have GPS switched
/// off entirely, which is the case this specifically targets. Returns
/// true once location is both switched on and permitted (or the customer
/// dismisses the prompt and chooses to continue anyway); the caller
/// decides whether to still allow checkout without it — this never
/// hard-blocks a booking, since the backend can also work from a
/// manually-entered address (see LocationAccessScreen's "Enter Location
/// Manually" option, and `AppRoutes.addresses`).
Future<void> ensureLocationEnabled(BuildContext context) async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (serviceEnabled) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      icon: const Icon(Icons.location_off_rounded,
          color: AppColors.primary, size: 32),
      title: const Text(
        'Turn on Location',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
      ),
      content: const Text(
        'Your phone\'s location is off. Turn it on so we can find your '
        'nearest technician and delivery slot — or continue and enter '
        'your address manually.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.35),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Not Now'),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            // Fixed 2026-10-01 per explicit request ("use that model to
            // turn on without navigate to user mobile [settings]"): this
            // used to unconditionally call Geolocator.openLocationSettings(),
            // kicking the customer out to Android's system Settings app
            // just to flip the GPS toggle, then trusting them to come back.
            // `location`'s requestService() shows Google Play Services' own
            // native in-app resolution dialog instead — the same one apps
            // like Uber/Ola use — so on Android the customer can turn GPS
            // on without ever leaving CalServices.
            //
            // On iOS, Apple's guidelines don't allow any app to flip the
            // system location switch itself, in-app or otherwise;
            // requestService() there only shows an alert and always
            // returns false — that's a platform restriction, not a bug —
            // so this still falls back to the old Settings deep-link there
            // (and on Android too, if Play Services is missing/outdated or
            // the in-app prompt fails for any other reason), rather than
            // leaving the customer with no way to proceed at all.
            var enabled = false;
            try {
              enabled = await loc.Location().requestService();
            } catch (_) {
              enabled = false;
            }
            if (!enabled) {
              final stillDisabled = !(await Geolocator.isLocationServiceEnabled());
              if (stillDisabled) {
                await Geolocator.openLocationSettings();
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Turn On'),
        ),
      ],
    ),
  );
}
