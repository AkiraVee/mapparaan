/// App-wide constants for Mapparaan.
library;

class AppConstants {
  AppConstants._();

  // ── Map tile style ──────────────────────────────────────────────────────────
  /// OpenFreeMap liberty style — free, no API key required.
  /// Attribution is automatically added by MapLibre.
  /// See: https://openfreemap.org
  static const String mapStyleUrl =
      'https://tiles.openfreemap.org/styles/liberty';

  // ── Default camera ──────────────────────────────────────────────────────────
  /// Metro Manila center (Luneta Park).
  static const double defaultLat = 14.5995;
  static const double defaultLng = 120.9842;
  static const double defaultZoom = 12.0;

  // ── Nominatim search ────────────────────────────────────────────────────────
  /// Rough bounding box for Metro Manila (for search bias).
  static const String searchViewbox = '120.9,14.4,121.2,14.8';
  static const String searchCountryCodes = 'ph';
  static const int searchResultLimit = 8;
  static const int searchMinQueryLength = 3;
}
