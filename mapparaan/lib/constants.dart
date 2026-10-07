/// App-wide constants for Mapparaan.
library;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class AppConstants {
  AppConstants._();

  // ── Map tiles ───────────────────────────────────────────────────────────────
  /// CARTO raster tiles (OpenStreetMap data) — free, no API key.
  /// `{s}` = subdomains a–d,
  /// `{r}` = "@2x" on high-density screens.
  ///
  /// Using CARTO "Positron" (light_all): a muted, low-detail basemap so route
  /// lines and pins stand out. Swap `light_all` for `rastertiles/voyager` to
  /// get the more detailed, colorful style back.
  static const String mapTileUrl =
      'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png?key=cb1_4cq6_1_f6ab62f4a4ac2f3bf2d02649';
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
  static const double maxZoom = 18.0;

  // ── Manila-only bounds ──────────────────────────────────────────────────────
  /// The map can't be panned outside this box (Metro Manila). Tighten these
  /// four numbers if you want City of Manila only.
  static const double boundsSouth = 14.35;
  static const double boundsWest = 120.90;
  static const double boundsNorth = 14.80;
  static const double boundsEast = 121.17;

  static final LatLngBounds manilaBounds = LatLngBounds(
    const LatLng(boundsSouth, boundsWest),
    const LatLng(boundsNorth, boundsEast),
  );

  // ── Nominatim search ────────────────────────────────────────────────────────
  /// Metro Manila box; search results are restricted to it (bounded=1).
  static const String searchViewbox = '$boundsWest,$boundsNorth,$boundsEast,$boundsSouth';
  static const String searchCountryCodes = 'ph';
  static const int searchResultLimit = 8;
  static const int searchMinQueryLength = 3;
}