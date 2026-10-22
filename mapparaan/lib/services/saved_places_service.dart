import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SavedPlace {
  final String id;
  final String name;
  final String subtitle;
  final double latitude;
  final double longitude;

  const SavedPlace({
    this.id = '',
    required this.name,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
  });

  LatLng get coordinates => LatLng(latitude, longitude);
}

class SavedPlacesService {
  static SupabaseClient? get _clientOrNull {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static Future<List<SavedPlace>> load() => fetchSavedPlaces();

  static Future<List<SavedPlace>> fetchSavedPlaces() async {
    final client = _clientOrNull;
    final userId = client?.auth.currentUser?.id;
    if (userId == null) return [];

    final List<dynamic> response = await client!
        .from('saved_places')
        .select('id, name, subtitle, geom')
        .eq('user_id', userId);

    return response.map((row) {
      final geomStr = row['geom']?.toString() ?? '';
      double lat = 0.0;
      double lng = 0.0;

      final point = RegExp(
        r'POINT\s*\(\s*(-?[\d.]+)\s+(-?[\d.]+)\s*\)',
        caseSensitive: false,
      ).firstMatch(geomStr);
      if (point != null) {
        lng = double.tryParse(point.group(1)!) ?? 0;
        lat = double.tryParse(point.group(2)!) ?? 0;
      }

      return SavedPlace(
        id: row['id'],
        name: row['name'],
        subtitle: row['subtitle'] ?? '',
        latitude: lat,
        longitude: lng,
      );
    }).toList();
  }

  static Future<bool> toggle(SavedPlace place) => toggleSavedPlace(place);

  static Future<bool> toggleSavedPlace(SavedPlace place) async {
    final client = _clientOrNull;
    final userId = client?.auth.currentUser?.id;
    if (userId == null) return false;

    final existing = await client!
        .from('saved_places')
        .select('id')
        .eq('user_id', userId)
        .eq('name', place.name);

    if ((existing as List).isNotEmpty) {
      await client.from('saved_places').delete().eq('id', existing.first['id']);
      return false;
    } else {
      await client.from('saved_places').insert({
        'user_id': userId,
        'name': place.name,
        'subtitle': place.subtitle,
        'geom': 'POINT(${place.longitude} ${place.latitude})',
      });
      return true;
    }
  }
}
