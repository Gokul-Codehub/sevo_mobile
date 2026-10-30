import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Non-identifying facts about the phone, shown to admins in the Devices page.
class DeviceFacts {
  const DeviceFacts({this.model = '', this.osVersion = ''});
  final String model; // e.g. "Samsung SM-A546E"
  final String osVersion; // e.g. "Android 14"
}

abstract class DeviceFactsReader {
  Future<DeviceFacts> read();
}

class DeviceInfoFactsReader implements DeviceFactsReader {
  const DeviceInfoFactsReader();

  static String _title(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Future<DeviceFacts> read() async {
    try {
      if (kIsWeb) return const DeviceFacts();
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final i = await plugin.androidInfo;
        final maker = _title(i.manufacturer);
        final model = i.model.toLowerCase().startsWith(i.manufacturer.toLowerCase()) ? i.model : '$maker ${i.model}';
        return DeviceFacts(model: model.trim(), osVersion: 'Android ${i.version.release}');
      }
      if (Platform.isIOS) {
        final i = await plugin.iosInfo;
        return DeviceFacts(model: i.utsname.machine, osVersion: 'iOS ${i.systemVersion}');
      }
    } catch (_) {}
    return const DeviceFacts();
  }
}
