import 'dart:io';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MemoryPin {
  final String id;
  final String placeName;
  final String address;
  final LatLng coordinates;
  final String imageUrl;

  MemoryPin({
    required this.id,
    required this.placeName,
    required this.address,
    required this.coordinates,
    required this.imageUrl,
  });
}

class MemoryPinService {
  static final SupabaseClient _client = Supabase.instance.client;
  static final ValueNotifier<List<MemoryPin>> pins = ValueNotifier([]);

  static Future<void> loadMemoryPins() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    final List<dynamic> response = await _client
        .from('memory_pins')
        .select('id, place_name, address, geom, image_url')
        .eq('user_id', userId);

    final loadedPins = response.map((row) {
      final geomStr = row['geom'] as String? ?? '';
      double lat = 0.0;
      double lng = 0.0;

      if (geomStr.contains('POINT(')) {
        final rawCoords = geomStr.split('POINT(')[1].replaceFirst(')', '').split(' ');
        lng = double.parse(rawCoords[0]);
        lat = double.parse(rawCoords[1]);
      }

      return MemoryPin(
        id: row['id'],
        placeName: row['place_name'],
        address: row['address'] ?? '',
        coordinates: LatLng(lat, lng),
        imageUrl: row['image_url'],
      );
    }).toList();

    pins.value = loadedPins;
  }

  static Future<void> addPin({
    required String placeName,
    required String address,
    required LatLng coordinates,
    required File imageFile,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    final fileExt = imageFile.path.split('.').last;
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final filePath = '$userId/$fileName';

    await _client.storage.from('memory-photos').upload(filePath, imageFile);
    final imageUrl = _client.storage.from('memory-photos').getPublicUrl(filePath);

    final inserted = await _client.from('memory_pins').insert({
      'user_id': userId,
      'place_name': placeName,
      'address': address,
      'geom': 'POINT(${coordinates.longitude} ${coordinates.latitude})',
      'image_url': imageUrl,
    }).select().single();

    final newPin = MemoryPin(
      id: inserted['id'],
      placeName: placeName,
      address: address,
      coordinates: coordinates,
      imageUrl: imageUrl,
    );

    pins.value = [...pins.value, newPin];
  }
}