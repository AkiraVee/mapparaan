import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../constants.dart';

class PlaceResult {
  final String name;
  final String subtitle;
  final LatLng coordinates;

  PlaceResult({
    required this.name,
    required this.subtitle,
    required this.coordinates,
  });
}

class PlaceSearchService {
  // Important: Nominatim requires a proper User-Agent
  static const String _userAgent = 'Mapparaan/1.0 (Flutter; Metro Manila Commuter App)';

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

    try {
      final response = await http.get(
        url,
        headers: {
          'User-Agent': _userAgent,
        },
      );

      if (response.statusCode != 200) return [];

      final List data = json.decode(response.body);

      return data.map((item) {
        final lat = double.parse(item['lat']);
        final lon = double.parse(item['lon']);
        final displayName = item['display_name'] as String;

        // Make a cleaner name + subtitle
        final parts = displayName.split(', ');
        final name = parts.isNotEmpty ? parts[0] : displayName;
        final subtitle = parts.length > 1 ? parts.sublist(1).join(', ') : '';

        return PlaceResult(
          name: name,
          subtitle: subtitle,
          coordinates: LatLng(lat, lon),
        );
      }).toList();
    } catch (e) {
      debugPrint('Search error: $e');
      return [];
    }
  }
}