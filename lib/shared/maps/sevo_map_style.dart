import '../../config/env.dart';

/// SEVO's own map look ("calm light navy"), used by every Google Map in the
/// app: live tracking, the address pin picker, the drop-location picker.
///
/// Added 2026-10-29. Cream land and soft white roads so the screen matches
/// the app's cream + navy cards; navy labels; light-blue water; muted green
/// parks; shop / business pins hidden so the technician marker, the route
/// and the customer's pin are the only strong colours on screen (the same
/// idea as Rapido's clean ride map).
///
/// Two ways to use it:
/// 1. Built in (default): [kSevoMapStyle] below is applied to each map.
/// 2. Cloud styling: if a Map ID is set in [Env.sevoMapId] (created in the
///    Google Cloud console > Map Management, with a Map Style attached), the
///    maps use that instead, and the look can be changed from the console
///    without releasing a new app. The built-in style is then ignored.
class SevoMap {
  SevoMap._();

  /// Map ID from the Google Cloud console, or null to use [kSevoMapStyle].
  static String? get cloudMapId =>
      Env.sevoMapId.trim().isEmpty ? null : Env.sevoMapId.trim();

  /// JSON style to pass to `GoogleMap(style: ...)`; null when a cloud Map ID
  /// is in use (the two cannot be combined).
  static String? get style => cloudMapId == null ? kSevoMapStyle : null;
}

/// Google Maps JSON style. Colours: cream land #F6F2EB, roads white with a
/// soft navy outline, highways pale navy #DCE5F4, labels navy #1F2D4D /
/// slate #5A6884, water #CFE2F3, parks #DCEBD9.
const String kSevoMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#f6f2eb"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#5a6884"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#fbf9f5"}, {"weight": 3}]},
  {"elementType": "labels.icon", "stylers": [{"saturation": -70}, {"lightness": 15}]},

  {"featureType": "administrative", "elementType": "geometry.stroke", "stylers": [{"color": "#c3cbd9"}]},
  {"featureType": "administrative.land_parcel", "stylers": [{"visibility": "off"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#1f2d4d"}]},
  {"featureType": "administrative.neighborhood", "elementType": "labels.text.fill", "stylers": [{"color": "#3b4a6b"}]},

  {"featureType": "landscape.man_made", "elementType": "geometry", "stylers": [{"color": "#f1ece3"}]},
  {"featureType": "landscape.man_made", "elementType": "geometry.stroke", "stylers": [{"color": "#e6dfd3"}]},
  {"featureType": "landscape.natural", "elementType": "geometry", "stylers": [{"color": "#eef0e6"}]},

  {"featureType": "poi", "elementType": "labels.text.fill", "stylers": [{"color": "#7a8499"}]},
  {"featureType": "poi.business", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.attraction", "elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.place_of_worship", "elementType": "labels.icon", "stylers": [{"saturation": -100}, {"lightness": 20}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#dcebd9"}]},
  {"featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{"color": "#5f8a62"}]},
  {"featureType": "poi.medical", "elementType": "geometry", "stylers": [{"color": "#f3e4e4"}]},
  {"featureType": "poi.school", "elementType": "geometry", "stylers": [{"color": "#ece8f3"}]},

  {"featureType": "road", "elementType": "geometry.fill", "stylers": [{"color": "#ffffff"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#e1e6ef"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#4a5878"}]},
  {"featureType": "road", "elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"featureType": "road.arterial", "elementType": "geometry.stroke", "stylers": [{"color": "#d6deeb"}]},
  {"featureType": "road.highway", "elementType": "geometry.fill", "stylers": [{"color": "#dce5f4"}]},
  {"featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{"color": "#b9c7df"}]},
  {"featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{"color": "#1f2d4d"}]},
  {"featureType": "road.highway", "elementType": "labels.icon", "stylers": [{"visibility": "simplified"}, {"saturation": -60}]},
  {"featureType": "road.local", "elementType": "labels.text.fill", "stylers": [{"color": "#7a8499"}]},

  {"featureType": "transit", "elementType": "geometry", "stylers": [{"color": "#e3e0ea"}]},
  {"featureType": "transit.station", "elementType": "labels.icon", "stylers": [{"saturation": -80}, {"lightness": 10}]},
  {"featureType": "transit.line", "elementType": "labels", "stylers": [{"visibility": "off"}]},

  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#cfe2f3"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#5b80a8"}]}
]
''';
