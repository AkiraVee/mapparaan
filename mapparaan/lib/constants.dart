/// App-wide constants for Mapparaan.
library;

class AppConstants {
  AppConstants._();

  // ── Map tiles ───────────────────────────────────────────────────────────────
  /// CARTO "Voyager" raster tiles (OpenStreetMap data) — free, no API key.
  /// Same basemap used by the AnoTara web app. `{s}` = subdomains a–d,
  /// `{r}` = "@2x" on high-density screens.
  static const String mapTileUrl =
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';
  static const List<String> mapTileSubdomains = ['a', 'b', 'c', 'd'];
  static const String appPackageName = 'com.example.mapparaan';

  /// Attribution required by OpenStreetMap and CARTO.
  static const String mapAttribution = '© OpenStreetMap contributors © CARTO';

  // ── Default camera ──────────────────────────────────────────────────────────
  /// Central Manila (matches the AnoTara web app).
  static const double defaultLat = 14.59;
  static const double defaultLng = 120.976;
  static const double defaultZoom = 14.0;
  static const double minZoom = 12.0;
  static const double maxZoom = 19.0;

  // ── Nominatim search ────────────────────────────────────────────────────────
  /// Rough bounding box for Metro Manila (for search bias).
  static const String searchViewbox = '120.9,14.4,121.2,14.8';
  static const String searchCountryCodes = 'ph';
  static const int searchResultLimit = 8;
  static const int searchMinQueryLength = 3;
}