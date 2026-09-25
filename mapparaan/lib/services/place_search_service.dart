import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';

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
    if (query.trim().length < 3) return [];

    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=${Uri.encodeComponent(query)}'
      '&format=json'
      '&addressdetails=1'
      '&limit=8'
      '&countrycodes=ph' // prioritize Philippines
      '&viewbox=120.9,14.4,121.2,14.8' // rough Metro Manila bias
      '&bounded=0',
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
      print('Search error: $e');
      return [];
    }
  }
}