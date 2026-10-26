import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'route_planner_service.dart';
import 'transit_planner_service.dart';

/// A walking route that follows real streets.
class WalkRoute {
  final List<LatLng> points;
  final double distanceMeters;

  const WalkRoute({required this.points, required this.distanceMeters});
}

/// Looks up the walking route between two points. Tests pass a fake one.
typedef WalkRouteFetcher = Future<WalkRoute?> Function(LatLng from, LatLng to);

/// The planner draws each walking leg as a straight line from point to point,
/// so a walk can cut across a river or a building. This service asks a street
/// router for the real path and updates the leg's drawing, distance and time.
class WalkRouteService {
  const WalkRouteService._();

  /// Same walking speed as the planner (WALK_SPEED_MPS in gtfs_planner.py).
  static const double walkSpeedMps = 1.2;

  /// Legs shorter than this are left as they are.
  static const double minStraightMeters = 30;

  static const Duration timeout = Duration(seconds: 6);

  /// Walking-only OSRM instance run by the OpenStreetMap community. Its path
  /// uses the name "driving" for every profile. If it is unreachable, the
  /// OSRM demo server used elsewhere in the app is tried next.
  static const String footBase = 'https://routing.openstreetmap.de/routed-foot';

  static const Distance _distance = Distance();
  static final Map<String, WalkRoute> _cache = {};

  /// True for a walking leg the planner drew as a bare straight line.
  static bool legNeedsSnapping(TransitLeg leg) {
    if (!leg.isWalk || leg.path.length != 2) return false;
    return _distance.as(LengthUnit.Meter, leg.path.first, leg.path.last) >=
        minStraightMeters;
  }

  static bool needsSnapping(TransitPlanOption option) =>
      !option.isMock && option.legs.any(legNeedsSnapping);

  /// Returns a copy of [option] whose walking legs follow streets, or null if
  /// nothing could be updated. Never throws.
  static Future<TransitPlanOption?> snapOption(
    TransitPlanOption option, {
    WalkRouteFetcher fetcher = fetchWalkRoute,
  }) async {
    if (!needsSnapping(option)) return null;
    try {
      final routes = await Future.wait<WalkRoute?>([
        for (final leg in option.legs)
          if (legNeedsSnapping(leg))
            fetcher(leg.path.first, leg.path.last)
          else
            Future<WalkRoute?>.value(null),
      ]);
      return applyWalkRoutes(option, routes);
    } catch (error) {
      debugPrint('Walk route update failed (${error.runtimeType}).');
      return null;
    }
  }

  /// Applies [routes] (one entry per leg, null where a leg is unchanged).
  /// Walking time comes from the real distance at the planner's walking speed,
  /// not from the router's own duration, which may assume a car. The total
  /// time and the "Walk N min" parts of the summary are adjusted to match.
  /// Fares do not depend on walking, so they are not touched.
  static TransitPlanOption? applyWalkRoutes(
    TransitPlanOption option,
    List<WalkRoute?> routes,
  ) {
    if (routes.length != option.legs.length) return null;

    var changed = false;
    var etaChange = 0;
    final legs = <TransitLeg>[];
    final walkMinutes = <int>[];

    for (var i = 0; i < option.legs.length; i++) {
      final leg = option.legs[i];
      final route = routes[i];
      if (!leg.isWalk) {
        legs.add(leg);
        continue;
      }
      if (route == null || leg.path.length < 2) {
        legs.add(leg);
        walkMinutes.add(leg.minutes);
        continue;
      }
      final minutes = math.max(
        1,
        (route.distanceMeters / walkSpeedMps / 60).round(),
      );
      legs.add(
        leg.copyWith(
          minutes: minutes,
          meters: route.distanceMeters.round(),
          // Keep the exact start and end so the line still meets the stop.
          path: [leg.path.first, ...route.points, leg.path.last],
        ),
      );
      etaChange += minutes - leg.minutes;
      walkMinutes.add(minutes);
      changed = true;
    }
    if (!changed) return null;

    return option.copyWith(
      summary: _updateSummary(option.summary, walkMinutes),
      etaMinutes: math.max(1, option.etaMinutes + etaChange),
      legs: legs,
    );
  }

  static final RegExp _walkPart = RegExp(r'Walk (\d+) min');

  /// Rewrites each "Walk N min" in order. If the summary does not have one per
  /// walking leg, it is left alone rather than guessed.
  static String _updateSummary(String summary, List<int> walkMinutes) {
    if (_walkPart.allMatches(summary).length != walkMinutes.length) {
      return summary;
    }
    var next = 0;
    return summary.replaceAllMapped(
      _walkPart,
      (_) => 'Walk ${walkMinutes[next++]} min',
    );
  }

  /// Walking route from [from] to [to], or null if no router answered.
  static Future<WalkRoute?> fetchWalkRoute(LatLng from, LatLng to) async {
    final key =
        '${from.latitude.toStringAsFixed(5)},${from.longitude.toStringAsFixed(5)};'
        '${to.latitude.toStringAsFixed(5)},${to.longitude.toStringAsFixed(5)}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final route =
        await _fetchFromFootServer(from, to) ?? await _fetchFromDemoServer(from, to);
    if (route != null) {
      if (_cache.length >= 200) _cache.remove(_cache.keys.first);
      _cache[key] = route;
    }
    return route;
  }

  static Future<WalkRoute?> _fetchFromFootServer(LatLng from, LatLng to) async {
    final uri = Uri.parse(
      '$footBase/route/v1/driving/'
      '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
      '?overview=full&geometries=geojson',
    );
    try {
      final response = await http.get(uri).timeout(timeout);
      if (response.statusCode != 200) return null;
      final data = json.decode(response.body);
      if (data is! Map || data['code'] != 'Ok') return null;
      final routes = data['routes'];
      if (routes is! List || routes.isEmpty) return null;
      final route = routes.first as Map;
      final coordinates = (route['geometry'] as Map)['coordinates'] as List;
      final points = [
        for (final c in coordinates)
          LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ];
      final meters = (route['distance'] as num).toDouble();
      if (points.length < 2 || meters <= 0) return null;
      return WalkRoute(points: points, distanceMeters: meters);
    } catch (error) {
      debugPrint('Walking route lookup failed (${error.runtimeType}).');
      return null;
    }
  }

  static Future<WalkRoute?> _fetchFromDemoServer(LatLng from, LatLng to) async {
    try {
      final geometry = await RoutePlannerService.fetchRoute(
        origin: from,
        destination: to,
        profile: 'foot',
      ).timeout(timeout);
      if (geometry == null ||
          geometry.points.length < 2 ||
          geometry.distanceMeters <= 0) {
        return null;
      }
      return WalkRoute(
        points: geometry.points,
        distanceMeters: geometry.distanceMeters,
      );
    } catch (error) {
      debugPrint('Fallback walking route lookup failed (${error.runtimeType}).');
      return null;
    }
  }
}