import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

enum RoutePreference { fastest, cheapest, fewestTransfers }

class RouteOption {
  final String title;
  final String summary;
  final String modeLabel;
  final int etaMinutes;

  /// Lowest regular fare, with the highest in [fareMax] (modern / aircon).
  final double fare;
  final double? fareMax;

  /// Student / senior / PWD fare, lowest and highest.
  final double fareDiscounted;
  final double? fareDiscountedMax;
  final int transfers;
  final RoutePreference preference;

  const RouteOption({
    required this.title,
    required this.summary,
    required this.modeLabel,
    required this.etaMinutes,
    required this.fare,
    this.fareMax,
    required this.fareDiscounted,
    this.fareDiscountedMax,
    required this.transfers,
    required this.preference,
  });
}

/// Rough road fares for the offline fallback only. The real planner reads
/// data/reference/fare_config.json; these constants copy its LTFRB rates
/// (effective 2026-09-28), so update both together.
class FareEstimator {
  const FareEstimator._();

  // base fare, base km, per km beyond base: regular, then student/senior/PWD
  static const _jeepney = _Rate(14.0, 4, 2.0, 11.2, 1.6);
  static const _modernJeepney = _Rate(17.0, 4, 2.4, 13.6, 1.92);
  static const _bus = _Rate(15.0, 5, 2.49, 12.0, 1.99);
  static const _airconBus = _Rate(18.0, 5, 2.98, 14.4, 2.38);

  /// Straight-line distance to rough road distance, same as the planner.
  static const double roadFactor = 1.3;

  static double _round(double value) =>
      ((value / 0.25) + 0.5 + 1e-9).floorToDouble() * 0.25;

  static double _fare(_Rate r, double km, {required bool discounted}) {
    final base = discounted ? r.discBase : r.base;
    final perKm = discounted ? r.discPerKm : r.perKm;
    return _round(base + perKm * math.max(0.0, km - r.baseKm));
  }

  /// Traditional jeepney (lowest) or modern jeepney (highest).
  static double jeepney(double km, {bool modern = false, bool discounted = false}) =>
      _fare(modern ? _modernJeepney : _jeepney, km, discounted: discounted);

  /// Ordinary bus (lowest) or aircon bus (highest).
  static double bus(double km, {bool aircon = false, bool discounted = false}) =>
      _fare(aircon ? _airconBus : _bus, km, discounted: discounted);
}

class _Rate {
  final double base;
  final double baseKm;
  final double perKm;
  final double discBase;
  final double discPerKm;
  const _Rate(this.base, this.baseKm, this.perKm, this.discBase, this.discPerKm);
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
    } catch (error) {
      debugPrint('Route lookup failed (${error.runtimeType}).');
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

    // Offline samples only: fares come from the distance, using the same
    // LTFRB rates as the planner, and are shown as rough estimates.
    final roadKm = distanceKm * FareEstimator.roadFactor;
    RouteOption jeepney({
      required String title,
      required String summary,
      required int etaMinutes,
      required RoutePreference preference,
    }) => RouteOption(
      title: title,
      summary: summary,
      modeLabel: 'Jeepney',
      etaMinutes: etaMinutes,
      fare: FareEstimator.jeepney(roadKm),
      fareMax: FareEstimator.jeepney(roadKm, modern: true),
      fareDiscounted: FareEstimator.jeepney(roadKm, discounted: true),
      fareDiscountedMax: FareEstimator.jeepney(
        roadKm,
        modern: true,
        discounted: true,
      ),
      transfers: 0,
      preference: preference,
    );

    final options = <RouteOption>[
      RouteOption(
        title: 'Fastest route',
        summary: 'Sample bus trip (offline estimate)',
        modeLabel: 'Bus',
        etaMinutes: (distanceKm * 7.2).round() + 12,
        fare: FareEstimator.bus(roadKm),
        fareMax: FareEstimator.bus(roadKm, aircon: true),
        fareDiscounted: FareEstimator.bus(roadKm, discounted: true),
        fareDiscountedMax: FareEstimator.bus(
          roadKm,
          aircon: true,
          discounted: true,
        ),
        transfers: 0,
        preference: RoutePreference.fastest,
      ),
      jeepney(
        title: 'Cheapest route',
        summary: 'Sample jeepney trip (offline estimate)',
        etaMinutes: (distanceKm * 9.5).round() + 18,
        preference: RoutePreference.cheapest,
      ),
      jeepney(
        title: 'Fewest transfers',
        summary: 'Sample direct jeepney trip (offline estimate)',
        etaMinutes: (distanceKm * 8.4).round() + 16,
        preference: RoutePreference.fewestTransfers,
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
