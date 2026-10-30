/// Server-driven app configuration (`GET /api/app/config/`).
///
/// Everything here is defensive: a missing, malformed or wrongly typed value
/// falls back to a compiled default and never throws. Only an explicit
/// `maintenance.enabled == true` can block the app (a config outage must never
/// lock customers out).
library;

class MaintenanceInfo {
  const MaintenanceInfo({
    this.enabled = false,
    this.title = '',
    this.message = '',
    this.eta,
    this.blockedModules = const [],
  });

  final bool enabled;
  final String title;
  final String message;
  final DateTime? eta;
  final List<String> blockedModules;

  /// Whole-app block (module-level blocks do not cover the app).
  bool get blocksApp => enabled && blockedModules.isEmpty;

  bool blocksModule(String module) => enabled && (blockedModules.isEmpty || blockedModules.contains(module));

  static MaintenanceInfo parse(Object? raw) {
    if (raw is! Map) return const MaintenanceInfo();
    return MaintenanceInfo(
      enabled: raw['enabled'] == true,
      title: _s(raw['title']),
      message: _s(raw['message']),
      eta: DateTime.tryParse(_s(raw['eta']))?.toLocal(),
      blockedModules: raw['blocked_modules'] is List
          ? [for (final m in raw['blocked_modules'] as List) if (m is String) m]
          : const [],
    );
  }
}

class AppAnnouncement {
  const AppAnnouncement({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.severity,
    required this.dismissible,
    this.ctaLabel,
    this.ctaRoute,
  });

  final int id;
  final String kind; // banner | modal | info
  final String title;
  final String body;
  final String severity; // info | warning | critical
  final bool dismissible;
  final String? ctaLabel;
  final String? ctaRoute;

  static AppAnnouncement? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = _s(raw['title']);
    if (id is! int || title.isEmpty) return null;
    final label = _s(raw['cta_label']);
    final route = _s(raw['cta_route']);
    return AppAnnouncement(
      id: id,
      kind: _s(raw['kind'], 'banner'),
      title: title,
      body: _s(raw['body']),
      severity: _s(raw['severity'], 'info'),
      dismissible: raw['dismissible'] != false,
      ctaLabel: label.isEmpty ? null : label,
      ctaRoute: route.isEmpty ? null : route,
    );
  }
}

/// Compiled defaults for every remote setting (kept identical to the server's catalogue).
const Map<String, Object> kSettingDefaults = {
  'api_connect_timeout_s': 10,
  'api_receive_timeout_s': 20,
  'api_upload_timeout_s': 30,
  'support_phone': '',
  'support_whatsapp': '',
  'terms_url': '',
  'privacy_url': '',
  'max_upload_mb': 10,
  'tracking_poll_interval_s': 10,
  'booking_poll_seconds': 15,
  'crash_reporting_enabled': true,
  'analytics_enabled': true,
  'soft_update_interval_hours': 24,
  'config_refresh_minutes': 15,
};

class FoundationConfig {
  const FoundationConfig({
    this.version = '',
    this.maintenance = const MaintenanceInfo(),
    this.flags = const {},
    this.settings = const {},
    this.announcements = const [],
  });

  /// Built-in defaults: no maintenance, no flag overrides, default settings.
  static const FoundationConfig defaults = FoundationConfig();

  final String version;
  final MaintenanceInfo maintenance;
  final Map<String, bool> flags;
  final Map<String, Object?> settings;
  final List<AppAnnouncement> announcements;

  /// A flag the server did not send resolves to [orElse] - callers pass the safe
  /// value (true for modules that exist today, so nothing disappears on an outage).
  bool flag(String name, {bool orElse = true}) => flags[name] ?? orElse;

  int intSetting(String key, {int? fallback}) {
    final v = settings[key];
    if (v is int) return v;
    final d = kSettingDefaults[key];
    return fallback ?? (d is int ? d : 0);
  }

  bool boolSetting(String key, {bool? fallback}) {
    final v = settings[key];
    if (v is bool) return v;
    final d = kSettingDefaults[key];
    return fallback ?? (d is bool ? d : false);
  }

  String stringSetting(String key, {String? fallback}) {
    final v = settings[key];
    if (v is String) return v;
    final d = kSettingDefaults[key];
    return fallback ?? (d is String ? d : '');
  }

  static FoundationConfig? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final flags = <String, bool>{};
    if (raw['flags'] is Map) {
      (raw['flags'] as Map).forEach((k, v) {
        if (k is String && v is bool) flags[k] = v;
      });
    }
    final settings = <String, Object?>{};
    if (raw['settings'] is Map) {
      (raw['settings'] as Map).forEach((k, v) {
        if (k is String) settings[k] = v;
      });
    }
    return FoundationConfig(
      version: _s(raw['config_version']),
      maintenance: MaintenanceInfo.parse(raw['maintenance']),
      flags: flags,
      settings: settings,
      announcements: raw['announcements'] is List
          ? [for (final a in raw['announcements'] as List) ?AppAnnouncement.tryParse(a)]
          : const [],
    );
  }
}

String _s(Object? v, [String fallback = '']) => v is String ? v : fallback;
