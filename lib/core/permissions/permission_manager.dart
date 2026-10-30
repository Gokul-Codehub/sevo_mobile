import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../shared/theme/app_colors.dart';

enum AppPermission { location, notifications, camera, photos }

enum PermState { granted, denied, permanentlyDenied }

/// Seam over the operating system's permission APIs (so the flow is testable).
abstract class PermissionPlatform {
  Future<PermState> status(AppPermission permission);
  Future<PermState> request(AppPermission permission);
  Future<void> openSettings();
}

class SystemPermissionPlatform implements PermissionPlatform {
  const SystemPermissionPlatform();

  static PermState _fromGeo(LocationPermission p) => switch (p) {
        LocationPermission.always || LocationPermission.whileInUse => PermState.granted,
        LocationPermission.deniedForever => PermState.permanentlyDenied,
        _ => PermState.denied,
      };

  static PermState _fromPh(ph.PermissionStatus s) {
    if (s.isGranted || s.isLimited || s.isProvisional) return PermState.granted;
    if (s.isPermanentlyDenied || s.isRestricted) return PermState.permanentlyDenied;
    return PermState.denied;
  }

  static ph.Permission _ph(AppPermission p) => switch (p) {
        AppPermission.notifications => ph.Permission.notification,
        AppPermission.camera => ph.Permission.camera,
        AppPermission.photos => ph.Permission.photos,
        AppPermission.location => ph.Permission.locationWhenInUse,
      };

  @override
  Future<PermState> status(AppPermission permission) async {
    if (permission == AppPermission.location) return _fromGeo(await Geolocator.checkPermission());
    return _fromPh(await _ph(permission).status);
  }

  @override
  Future<PermState> request(AppPermission permission) async {
    if (permission == AppPermission.location) return _fromGeo(await Geolocator.requestPermission());
    return _fromPh(await _ph(permission).request());
  }

  @override
  Future<void> openSettings() async {
    await ph.openAppSettings();
  }
}

/// What to tell the customer before the system prompt.
class PermissionRationale {
  const PermissionRationale({required this.icon, required this.title, required this.body, required this.settingsHint});
  final IconData icon;
  final String title;
  final String body;
  final String settingsHint;

  static const Map<AppPermission, PermissionRationale> defaults = {
    AppPermission.location: PermissionRationale(
      icon: Icons.location_on_rounded,
      title: 'Allow location access',
      body: 'SEVO uses your location to fill in your address and find the nearest technician or delivery slot. '
          'You can also enter your address manually.',
      settingsHint: 'Location is turned off for SEVO. Open settings and allow location to use this feature, or enter your address manually.',
    ),
    AppPermission.notifications: PermissionRationale(
      icon: Icons.notifications_active_rounded,
      title: 'Stay updated',
      body: 'Get alerts when your technician is assigned, on the way, or when your order status changes.',
      settingsHint: 'Notifications are turned off for SEVO. Open settings to turn them on.',
    ),
    AppPermission.camera: PermissionRationale(
      icon: Icons.photo_camera_rounded,
      title: 'Allow camera access',
      body: 'SEVO needs the camera to take photos for your booking, such as the issue to be fixed.',
      settingsHint: 'Camera access is turned off for SEVO. Open settings to allow it, or choose a photo from your gallery.',
    ),
    AppPermission.photos: PermissionRationale(
      icon: Icons.photo_library_rounded,
      title: 'Allow photo access',
      body: 'SEVO needs access to your photos so you can attach them to a booking or message.',
      settingsHint: 'Photo access is turned off for SEVO. Open settings to allow it.',
    ),
  };
}

typedef RationalePrompt = Future<bool> Function(BuildContext context, PermissionRationale rationale);
typedef SettingsPrompt = Future<bool> Function(BuildContext context, PermissionRationale rationale);

/// Explain -> request -> recover. Never a dead end: if the customer says no, or the system will not
/// ask again, they are told how to fix it (Open Settings) and the caller keeps its fallback
/// (for example manual address entry).
class PermissionManager {
  PermissionManager({
    PermissionPlatform platform = const SystemPermissionPlatform(),
    RationalePrompt? askRationale,
    SettingsPrompt? askSettings,
  })  : _platform = platform,
        _askRationale = askRationale ?? _defaultRationale,
        _askSettings = askSettings ?? _defaultSettings;

  static final PermissionManager instance = PermissionManager();

  final PermissionPlatform _platform;
  final RationalePrompt _askRationale;
  final SettingsPrompt _askSettings;

  /// True when the permission is granted by the end of the flow.
  Future<bool> ensure(BuildContext context, AppPermission permission, {PermissionRationale? rationale}) async {
    final r = rationale ?? PermissionRationale.defaults[permission]!;
    var state = await _platform.status(permission);
    if (state == PermState.granted) return true;

    if (state == PermState.denied) {
      if (!context.mounted) return false;
      if (!await _askRationale(context, r)) return false;
      state = await _platform.request(permission);
      if (state == PermState.granted) return true;
    }

    if (state == PermState.permanentlyDenied) {
      if (!context.mounted) return false;
      if (await _askSettings(context, r)) await _platform.openSettings();
    }
    return false;
  }

  Future<PermState> status(AppPermission permission) => _platform.status(permission);

  static Future<bool> _defaultRationale(BuildContext context, PermissionRationale r) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _Sheet(icon: r.icon, title: r.title, body: r.body, primary: 'Continue', secondary: 'Not now'),
    );
    return ok == true;
  }

  static Future<bool> _defaultSettings(BuildContext context, PermissionRationale r) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _Sheet(icon: Icons.settings_rounded, title: 'Permission needed', body: r.settingsHint, primary: 'Open settings', secondary: 'Cancel'),
    );
    return ok == true;
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.icon, required this.title, required this.body, required this.primary, required this.secondary});
  final IconData icon;
  final String title;
  final String body;
  final String primary;
  final String secondary;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 28, backgroundColor: const Color(0xFFEAF0F6), child: Icon(icon, size: 28, color: AppColors.navy)),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.navy)),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black54)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(backgroundColor: AppColors.navy, minimumSize: const Size.fromHeight(48)),
                child: Text(primary),
              ),
            ),
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(secondary)),
          ],
        ),
      ),
    );
  }
}
