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
  static final SupabaseClient _client = Supabase.instance.client;

  static Future<List<SavedPlace>> load() => fetchSavedPlaces();

  static Future<List<SavedPlace>> fetchSavedPlaces() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final List<dynamic> response = await _client
        .from('saved_places')
        .select('id, name, subtitle, geom')
        .eq('user_id', userId);

    return response.map((row) {
      final geomStr = row['geom'] as String? ?? '';
      double lat = 0.0;
      double lng = 0.0;

      if (geomStr.contains('POINT(')) {
        final rawCoords = geomStr.split('POINT(')[1].replaceFirst(')', '').split(' ');
        lng = double.parse(rawCoords[0]);
        lat = double.parse(rawCoords[1]);
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
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final existing = await _client
        .from('saved_places')
        .select('id')
        .eq('user_id', userId)
        .eq('name', place.name);

    if ((existing as List).isNotEmpty) {
      await _client.from('saved_places').delete().eq('id', existing.first['id']);
      return false;
    } else {
      await _client.from('saved_places').insert({
        'user_id': userId,
        'name': place.name,
        'subtitle': place.subtitle,
        'geom': 'POINT(${place.longitude} ${place.latitude})',
      });
      return true;
    }
  }
}