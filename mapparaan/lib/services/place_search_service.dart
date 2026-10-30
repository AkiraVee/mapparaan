import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../constants.dart';

class PlaceResult {
  final String name;
  final String subtitle;
  final LatLng coordinates;

  const PlaceResult({
    required this.name,
    required this.subtitle,
    required this.coordinates,
  });
}

typedef PlaceSearch = Future<List<PlaceResult>> Function(String query);
typedef PlaceReverseGeocode = Future<PlaceResult?> Function(LatLng coordinates);

class PlaceSearchService {
  // Important: Nominatim requires a proper User-Agent
  static const String _userAgent =
      'Mapparaan/1.0 (Flutter; Metro Manila Commuter App)';

  static Future<List<PlaceResult>> search(String query) async {
    if (query.trim().length < AppConstants.searchMinQueryLength) return [];

    // bounded=1 restricts results to the Manila viewbox (no more results
    // from elsewhere in the Philippines).
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=${Uri.encodeComponent(query)}'
      '&format=json'
      '&addressdetails=1'
      '&limit=${AppConstants.searchResultLimit}'
      '&countrycodes=${AppConstants.searchCountryCodes}'
      '&viewbox=${AppConstants.searchViewbox}'
      '&bounded=1',
    );

    final response = await http
        .get(url, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw http.ClientException(
        'Place search returned HTTP ${response.statusCode}.',
        url,
      );
    }

    final decoded = json.decode(response.body);
    if (decoded is! List) {
      throw const FormatException('Place search returned an invalid response.');
    }

    return decoded.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Place search returned an invalid result.');
      }
      final latitude = double.tryParse(item['lat']?.toString() ?? '');
      final longitude = double.tryParse(item['lon']?.toString() ?? '');
      final displayName = item['display_name'];
      if (latitude == null || longitude == null || displayName is! String) {
        throw const FormatException(
          'Place search returned an incomplete result.',
        );
      }

      final parts = displayName.split(', ');
      final name = parts.isNotEmpty ? parts.first : displayName;
      final subtitle = parts.length > 1 ? parts.skip(1).join(', ') : '';
      return PlaceResult(
        name: name,
        subtitle: subtitle,
        coordinates: LatLng(latitude, longitude),
      );
    }).toList();
  }

  static Future<PlaceResult?> reverseGeocode(LatLng coordinates) async {
    final url = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': coordinates.latitude.toString(),
      'lon': coordinates.longitude.toString(),
      'format': 'jsonv2',
      'addressdetails': '1',
      'zoom': '18',
    });

    final response = await http
        .get(url, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Reverse geocoding returned HTTP ${response.statusCode}.',
        url,
      );
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Reverse geocoding returned an invalid response.',
      );
    }
    final displayName = decoded['display_name'];
    if (displayName is! String || displayName.trim().isEmpty) return null;

    final parts = displayName.split(', ');
    return PlaceResult(
      name: parts.first,
      subtitle: parts.length > 1 ? parts.skip(1).join(', ') : '',
      coordinates: coordinates,
    );
  }
}
