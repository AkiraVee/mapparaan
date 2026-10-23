import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_assistant_service.dart';
import 'route_planner_service.dart';
import 'transit_planner_service.dart';

/// Local-only saved commute shortcuts. These work without an account or API.
class SavedCommute {
  final String id;
  final String label;
  final String originName;
  final LatLng origin;
  final String destinationName;
  final LatLng destination;
  final RoutePreference preference;
  final PassengerType passengerType;

  const SavedCommute({
    required this.id,
    required this.label,
    required this.originName,
    required this.origin,
    required this.destinationName,
    required this.destination,
    this.preference = RoutePreference.fastest,
    this.passengerType = PassengerType.general,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'origin_name': originName,
    'origin': [origin.latitude, origin.longitude],
    'destination_name': destinationName,
    'destination': [destination.latitude, destination.longitude],
    'preference': preference.name,
    'passenger_type': passengerType.apiValue,
  };

  factory SavedCommute.fromJson(Map<String, dynamic> json) {
    final origin = _point(json['origin']);
    final destination = _point(json['destination']);
    return SavedCommute(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? 'Saved commute',
      originName: json['origin_name']?.toString() ?? 'Current location',
      origin: origin,
      destinationName: json['destination_name']?.toString() ?? 'Destination',
      destination: destination,
      preference: _preference(json['preference']),
      passengerType: _passenger(json['passenger_type']),
    );
  }

  static LatLng _point(Object? raw) {
    if (raw is List && raw.length >= 2 && raw[0] is num && raw[1] is num) {
      return LatLng((raw[0] as num).toDouble(), (raw[1] as num).toDouble());
    }
    return const LatLng(14.5943, 120.9721);
  }

  static RoutePreference _preference(Object? raw) {
    return RoutePreference.values.firstWhere(
      (item) => item.name == raw,
      orElse: () => RoutePreference.fastest,
    );
  }

  static PassengerType _passenger(Object? raw) {
    return PassengerType.values.firstWhere(
      (item) => item.apiValue == raw,
      orElse: () => PassengerType.general,
    );
  }
}

class SavedCommuteService {
  SavedCommuteService._();

  static const _key = 'mapparaan.saved_commutes.v1';

  static Future<List<SavedCommute>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getStringList(_key) ?? const [];
    return raw
        .map((item) {
          try {
            return SavedCommute.fromJson(
              jsonDecode(item) as Map<String, dynamic>,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<SavedCommute>()
        .toList();
  }

  static Future<void> save(SavedCommute commute) async {
    final existing = await load();
    final updated = [
      commute,
      ...existing.where((item) => item.id != commute.id),
    ].take(8).toList();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _key,
      updated.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  static Future<void> delete(String id) async {
    final preferences = await SharedPreferences.getInstance();
    final remaining = (await load()).where((item) => item.id != id);
    await preferences.setStringList(
      _key,
      remaining.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }
}
