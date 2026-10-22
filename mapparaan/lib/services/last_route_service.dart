import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'transit_planner_service.dart';

/// Stores the most recent route so a commuter can still inspect it offline.
/// This is deliberately local and does not require an account.
class CachedRoute {
  final LatLng origin;
  final LatLng destination;
  final TransitPlanOption option;

  const CachedRoute({
    required this.origin,
    required this.destination,
    required this.option,
  });
}

class LastRouteService {
  LastRouteService._();

  static const _key = 'mapparaan.last_route.v1';

  static Future<void> save({
    required LatLng origin,
    required LatLng destination,
    required TransitPlanOption option,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      jsonEncode({
        'origin': [origin.latitude, origin.longitude],
        'destination': [destination.latitude, destination.longitude],
        'option': option.toJson(),
      }),
    );
  }

  static Future<CachedRoute?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final origin = _point(json['origin']);
      final destination = _point(json['destination']);
      final option = TransitPlanOption.fromJson(
        Map<String, dynamic>.from(json['option'] as Map),
      );
      if (origin == null || destination == null) return null;
      return CachedRoute(
        origin: origin,
        destination: destination,
        option: option,
      );
    } catch (_) {
      return null;
    }
  }

  static LatLng? _point(Object? value) {
    if (value is! List ||
        value.length < 2 ||
        value[0] is! num ||
        value[1] is! num) {
      return null;
    }
    return LatLng((value[0] as num).toDouble(), (value[1] as num).toDouble());
  }
}
