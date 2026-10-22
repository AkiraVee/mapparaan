/// App-wide constants for Mapparaan.
library;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  AppConstants._();

  static String get supabaseUrl => _requiredEnv('SUPABASE_URL');
  static String get supabaseClientKey =>
      _optionalEnv('SUPABASE_PUBLISHABLE_KEY') ??
      _requiredEnv('SUPABASE_ANON_KEY');

  static String get cartoApiKey => _optionalEnv('CARTO_API_KEY') ?? '';
  static String get transitApiBaseUrl =>
      _optionalEnv('TRANSIT_API_URL') ?? 'http://127.0.0.1:8080';

  static String _requiredEnv(String name) {
    final value = _optionalEnv(name);
    if (value == null || value.isEmpty) {
      throw StateError('Missing required environment variable: $name');
    }
    return value;
  }

  static String? _optionalEnv(String name) {
    if (!dotenv.isInitialized) return null;
    final value = dotenv.env[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  // ── Map tiles ───────────────────────────────────────────────────────────────
  static String get mapTileUrl => cartoApiKey.isEmpty
      ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
      : 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png?key=$cartoApiKey';

  static const List<String> mapTileSubdomains = ['a', 'b', 'c', 'd'];
  static const String appPackageName = 'com.example.mapparaan';
  static const String mapAttribution = '© OpenStreetMap contributors © CARTO';

  // ── Default camera ──────────────────────────────────────────────────────────
  static const double defaultLat = 14.59;
  static const double defaultLng = 120.976;
  static const double defaultZoom = 14.0;
  static const double minZoom = 12.0;
  static const double maxZoom = 18.0;

  // ── Manila-only bounds ──────────────────────────────────────────────────────
  static const double boundsSouth = 14.35;
  static const double boundsWest = 120.90;
  static const double boundsNorth = 14.80;
  static const double boundsEast = 121.17;

  static final LatLngBounds manilaBounds = LatLngBounds(
    const LatLng(boundsSouth, boundsWest),
    const LatLng(boundsNorth, boundsEast),
  );

  // ── Nominatim search ────────────────────────────────────────────────────────
  static const String searchViewbox =
      '$boundsWest,$boundsNorth,$boundsEast,$boundsSouth';
  static const String searchCountryCodes = 'ph';
  static const int searchResultLimit = 8;
  static const int searchMinQueryLength = 3;
}
