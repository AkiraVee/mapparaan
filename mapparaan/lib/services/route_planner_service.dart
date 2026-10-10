import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

enum RoutePreference { fastest, cheapest, fewestTransfers }

class RouteOption {
  final String title;
  final String summary;
  final String modeLabel;
  final int etaMinutes;
  final int fare;
  final int transfers;
  final RoutePreference preference;

  const RouteOption({
    required this.title,
    required this.summary,
    required this.modeLabel,
    required this.etaMinutes,
    required this.fare,
    required this.transfers,
    required this.preference,
  });
}

/// Real route geometry returned by OSRM
class RouteGeometry {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final String profile; // "foot" or "driving"

  const RouteGeometry({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.profile,
  });
}

class RoutePlannerService {
  const RoutePlannerService._();

  // Public demo OSRM server (free, no key needed)
  static const String _osrmBase = 'https://router.project-osrm.org';

  /// Fetches a real walking or driving route
  static Future<RouteGeometry?> fetchRoute({
    required LatLng origin,
    required LatLng destination,
    required String profile, // "foot" or "driving"
  }) async {
    final url = Uri.parse(
      '$_osrmBase/route/v1/$profile/'
      '${origin.longitude},${origin.latitude};'
      '${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      if (data['code'] != 'Ok') return null;

      final route = data['routes'][0];
      final coordinates = route['geometry']['coordinates'] as List;

      final points = coordinates
          .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
          .toList();

      return RouteGeometry(
        points: points,
        distanceMeters: (route['distance'] as num).toDouble(),
        durationSeconds: (route['duration'] as num).toDouble(),
        profile: profile,
      );
    } catch (e) {
      debugPrint('OSRM error: $e');
      return null;
    }
  }

  /// Mock multimodal options (we will improve these later)
  static List<RouteOption> generateRouteOptions({
    required LatLng destination,
    required LatLng? userLocation,
    RoutePreference preference = RoutePreference.fastest,
  }) {
    final origin = userLocation ?? const LatLng(14.5943, 120.9721);
    final distanceKm = const Distance().as(
      LengthUnit.Kilometer,
      origin,
      destination,
    );

    final options = <RouteOption>[
      RouteOption(
        title: 'Fastest route',
        summary: 'Direct jeepney ride with a brief walk',
        modeLabel: 'Jeep + walk',
        etaMinutes: (distanceKm * 7.2).round() + 12,
        fare: 30,
        transfers: 1,
        preference: preference,
      ),
      RouteOption(
        title: 'Cheapest route',
        summary: 'Budget-friendly with one transfer',
        modeLabel: 'Jeep + train',
        etaMinutes: (distanceKm * 9.5).round() + 18,
        fare: 18,
        transfers: 2,
        preference: preference,
      ),
      RouteOption(
        title: 'Fewest transfers',
        summary: 'Comfortable route with the least switching',
        modeLabel: 'UV express',
        etaMinutes: (distanceKm * 8.4).round() + 16,
        fare: 40,
        transfers: 0,
        preference: preference,
      ),
    ];

    switch (preference) {
      case RoutePreference.fastest:
        options.sort((a, b) => a.etaMinutes.compareTo(b.etaMinutes));
        break;
      case RoutePreference.cheapest:
        options.sort((a, b) => a.fare.compareTo(b.fare));
        break;
      case RoutePreference.fewestTransfers:
        options.sort((a, b) => a.transfers.compareTo(b.transfers));
        break;
    }

    return options;
  }
}