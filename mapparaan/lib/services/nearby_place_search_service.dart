import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'place_search_service.dart';

typedef NearbyCategorySearch = Future<List<PlaceResult>> Function(
  String category,
  LatLng location,
);

class NearbyPlaceSearchService {
  NearbyPlaceSearchService._();

  static const double _searchRadiusMeters = 3000;
  static const int _resultLimit = 30;
  static const Map<String, List<String>> _categoryFilters = {
    'Mall': [
      r'shop~"^(mall|shopping_centre|shopping_center)$"',
      'building=shopping_mall',
      'amenity=shopping_mall',
    ],
    'Restaurant': [
      r'amenity~"^(restaurant|fast_food|cafe|food_court)$"',
      r'shop~"^(coffee|bakery|confectionery)$"',
    ],
    'Hospital': [
      'amenity=hospital',
      'amenity=clinic',
      'healthcare=hospital',
      'healthcare=clinic',
    ],
    'School': [
      r'amenity~"^(school|college|university|kindergarten)$"',
      'amenity=library',
    ],
    'LRT/MRT': [
      'railway=station',
      'railway=subway_entrance',
      'public_transport=station',
    ],
    'Park': [
      r'leisure~"^(park|garden|playground)$"',
      'amenity=park',
      'landuse=recreation_ground',
    ],
    'Market': [
      'amenity=marketplace',
      'shop=market',
      'shop=supermarket',
      'amenity=supermarket',
    ],
  };

  static final http.Client _client = http.Client();

  static Future<List<PlaceResult>> search(
    String category,
    LatLng location, {
    @visibleForTesting http.Client? client,
  }) async {
    final normalizedCategory = category.trim();
    final filters = _categoryFilters[normalizedCategory];
    if (filters == null) {
      throw ArgumentError.value(
        category,
        'category',
        'Unsupported nearby place category.',
      );
    }

    final query = _buildQuery(filters, location);
    final uri = Uri.https('overpass-api.de', '/api/interpreter', {
      'data': query,
    });
    final response = await (client ?? _client)
        .get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'Mapparaan/1.0 (Nearby Place Discovery)',
          },
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Nearby place search returned HTTP ${response.statusCode}.',
        uri,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['elements'] is! List) {
      throw const FormatException(
        'Nearby place search returned an invalid response.',
      );
    }

    final results = <({PlaceResult place, double distance})>[];
    final seen = <String>{};
    for (final element in decoded['elements'] as List) {
      final candidate = _candidateFromElement(element, normalizedCategory, location);
      if (candidate == null) continue;
      final key = '${element['type']}:${element['id']}';
      if (!seen.add(key)) continue;
      results.add(candidate);
    }

    results.sort((first, second) => first.distance.compareTo(second.distance));
    return results.take(_resultLimit).map((result) => result.place).toList();
  }

  static ({PlaceResult place, double distance})? _candidateFromElement(
    Object? element,
    String category,
    LatLng origin,
  ) {
    if (element is! Map<String, dynamic>) return null;
    final tags = element['tags'];
    if (tags is! Map<String, dynamic>) return null;
    final name = tags['name'];
    if (name is! String || name.trim().isEmpty) return null;

    final coordinates = _coordinatesFrom(element);
    if (coordinates == null) return null;

    final distance = const Distance().as(
      LengthUnit.Meter,
      origin,
      coordinates,
    );
    final address = _addressFrom(tags);
    final detail = address.isEmpty ? category : address;
    return (
      place: PlaceResult(
        name: name,
        subtitle: '$detail · ${_formatDistance(distance)} away',
        coordinates: coordinates,
      ),
      distance: distance,
    );
  }

  static String _addressFrom(Map<String, dynamic> tags) {
    return [
      tags['addr:street'],
      tags['addr:suburb'],
      tags['addr:city'],
    ]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(', ');
  }

  static String _buildQuery(List<String> filters, LatLng location) {
    final latitude = location.latitude.toStringAsFixed(6);
    final longitude = location.longitude.toStringAsFixed(6);
    final selectors = filters
        .map(
          (filter) =>
              '  nwr(around:${_searchRadiusMeters.toInt()},$latitude,$longitude)[$filter];',
        )
        .join('\n');
    return '[out:json][timeout:15];\n(\n$selectors\n);\nout center tags;';
  }

  static LatLng? _coordinatesFrom(Map<String, dynamic> element) {
    final center = element['center'];
    final rawLatitude =
        element['lat'] ?? (center is Map ? center['lat'] : null);
    final rawLongitude =
        element['lon'] ?? (center is Map ? center['lon'] : null);
    final latitude = rawLatitude is num ? rawLatitude.toDouble() : null;
    final longitude = rawLongitude is num ? rawLongitude.toDouble() : null;
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }
    return LatLng(latitude, longitude);
  }

  static String _formatDistance(double meters) => meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(1)} km';
}
