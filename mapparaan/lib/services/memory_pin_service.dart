import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MemoryPin {
  final String id;
  final String placeName;
  final String address;
  final LatLng coordinates;
  final String imageUrl;
  final String? imagePath;

  MemoryPin({
    required this.id,
    required this.placeName,
    required this.address,
    required this.coordinates,
    required this.imageUrl,
    required this.imagePath,
  });
}

LatLng parseMemoryPinPoint(Object? geometry) {
  if (geometry is Map) {
    if (geometry['type'] != 'Point') {
      throw const FormatException('Memory geometry is not a point');
    }

    final coordinates = geometry['coordinates'];
    if (coordinates is! List ||
        coordinates.length < 2 ||
        coordinates[0] is! num ||
        coordinates[1] is! num) {
      throw const FormatException('Invalid GeoJSON point coordinates');
    }
    return LatLng(
      (coordinates[1] as num).toDouble(),
      (coordinates[0] as num).toDouble(),
    );
  }

  if (geometry is! String) {
    throw const FormatException('Unsupported point geometry encoding');
  }

  final point = MemoryPinService._parsePointString(geometry);
  return point;
}

class MemoryPinService {
  static SupabaseClient? get _clientOrNull {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static final ValueNotifier<List<MemoryPin>> pins = ValueNotifier([]);

  static Future<void> loadMemoryPins() async {
    final client = _clientOrNull;
    final userId = client?.auth.currentUser?.id;
    if (userId == null) {
      pins.value = [];
      return;
    }

    late final List<dynamic> response;
    var includesImagePath = true;
    try {
      response = await client!
          .from('memory_pins')
          .select('id, place_name, address, geom, image_url, image_path')
          .eq('user_id', userId);
    } on PostgrestException catch (error) {
      final missingImagePath =
          error.code == '42703' ||
          (error.message.contains('image_path') &&
              (error.message.contains('column') ||
                  error.message.contains('schema cache')));
      if (!missingImagePath) rethrow;
      includesImagePath = false;
      response = await client!
          .from('memory_pins')
          .select('id, place_name, address, geom, image_url')
          .eq('user_id', userId);
    }

    final loadedPins = await Future.wait(
      response.map((row) async {
        final coordinates = parseMemoryPinPoint(row['geom']);

        final imagePath =
            (includesImagePath ? row['image_path'] as String? : null) ??
            _pathFromLegacyPublicUrl(row['image_url'] as String?);
        var imageUrl = '';
        if (imagePath != null) {
          try {
            imageUrl = await _signedImageUrl(userId, imagePath);
          } catch (error, stackTrace) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                context: ErrorDescription(
                  'while creating a signed URL for memory photo ${row['id']}',
                ),
              ),
            );
          }
        }

        return MemoryPin(
          id: row['id'].toString(),
          placeName: row['place_name'] as String? ?? '',
          address: row['address'] as String? ?? '',
          coordinates: coordinates,
          imageUrl: imageUrl,
          imagePath: imagePath,
        );
      }),
    );

    pins.value = loadedPins;
  }

  static Future<void> addPin({
    required String placeName,
    required String address,
    required LatLng coordinates,
    required String fileName,
    required String contentType,
    required Uint8List imageBytes,
  }) async {
    final client = _clientOrNull;
    final userId = client?.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Sign in before uploading a memory photo');
    }

    final safeFileName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safeFileName.isEmpty || safeFileName == '.' || safeFileName == '..') {
      throw ArgumentError.value(fileName, 'fileName', 'Invalid image filename');
    }
    final filePath = '$userId/$safeFileName';

    await client!.storage
        .from('memory-photos')
        .uploadBinary(
          filePath,
          imageBytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );

    late String pinId;
    var hasPinId = false;
    late final String imageUrl;
    try {
      final inserted = await client
          .from('memory_pins')
          .insert({
            'user_id': userId,
            'place_name': placeName,
            'address': address,
            'geom': 'POINT(${coordinates.longitude} ${coordinates.latitude})',
            'image_path': filePath,
          })
          .select('id')
          .single();
      pinId = inserted['id'].toString();
      hasPinId = true;
      imageUrl = await _signedImageUrl(userId, filePath);
    } catch (error, stackTrace) {
      if (hasPinId) {
        try {
          await client.from('memory_pins').delete().eq('id', pinId);
        } catch (cleanupError, cleanupStackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: cleanupError,
              stack: cleanupStackTrace,
              context: ErrorDescription(
                'while cleaning up a failed memory photo upload',
              ),
            ),
          );
        }
      }
      try {
        await client.storage.from('memory-photos').remove([filePath]);
      } catch (cleanupError, cleanupStackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: cleanupError,
            stack: cleanupStackTrace,
            context: ErrorDescription(
              'while removing an orphaned memory photo upload',
            ),
          ),
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }

    final newPin = MemoryPin(
      id: pinId,
      placeName: placeName,
      address: address,
      coordinates: coordinates,
      imageUrl: imageUrl,
      imagePath: filePath,
    );

    pins.value = [...pins.value, newPin];
  }

  static Future<void> deletePin(String pinId) async {
    final client = _clientOrNull;
    final userId = client?.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Sign in before deleting a memory photo');
    }

    final row = await client!
        .from('memory_pins')
        .select('id, image_path, image_url')
        .eq('id', pinId)
        .eq('user_id', userId)
        .maybeSingle();

    if (row == null) {
      throw StateError('This memory photo was not found in your account');
    }

    final imagePath =
        row['image_path'] as String? ??
        _pathFromLegacyPublicUrl(row['image_url'] as String?);
    if (imagePath != null && _ownerIdFromPath(imagePath) != userId) {
      throw StateError('Memory photo path does not belong to the current user');
    }

    await client
        .from('memory_pins')
        .delete()
        .eq('id', pinId)
        .eq('user_id', userId);

    pins.value = pins.value.where((pin) => pin.id != pinId).toList();

    if (imagePath != null) {
      try {
        await client.storage.from('memory-photos').remove([imagePath]);
      } catch (_, stackTrace) {
        Error.throwWithStackTrace(
          StateError(
            'Memory removed from your account, but the photo file could not '
            'be deleted. Please contact support.',
          ),
          stackTrace,
        );
      }
    }
  }

  static Future<String> _signedImageUrl(String userId, String imagePath) {
    if (_ownerIdFromPath(imagePath) != userId) {
      throw StateError('Memory photo path does not belong to the current user');
    }
    final client = _clientOrNull;
    if (client == null) {
      throw StateError('Cloud services are not configured');
    }
    return client.storage
        .from('memory-photos')
        .createSignedUrl(imagePath, 3600);
  }

  static String? _pathFromLegacyPublicUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return null;
    final uri = Uri.tryParse(imageUrl);
    if (uri == null) return null;

    final segments = uri.pathSegments;
    final bucketIndex = segments.indexOf('memory-photos');
    if (bucketIndex < 0 || bucketIndex + 1 >= segments.length) return null;
    return segments.skip(bucketIndex + 1).join('/');
  }

  static String? _ownerIdFromPath(String path) {
    final segments = path.split('/');
    return segments.length >= 2 ? segments.first : null;
  }

  static LatLng _parsePointString(String geometry) {
    final wktMatch = RegExp(
      r'^POINT\s*\(\s*(-?[\d.eE+-]+)\s+(-?[\d.eE+-]+)\s*\)$',
      caseSensitive: false,
    ).firstMatch(geometry.trim());
    if (wktMatch != null) {
      return LatLng(
        double.parse(wktMatch.group(2)!),
        double.parse(wktMatch.group(1)!),
      );
    }

    final hex = geometry.trim();
    if (hex.length < 42 ||
        hex.length.isOdd ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
      throw FormatException('Unsupported point geometry encoding');
    }
    final bytes = Uint8List.fromList([
      for (var index = 0; index < hex.length; index += 2)
        int.parse(hex.substring(index, index + 2), radix: 16),
    ]);
    final data = ByteData.sublistView(bytes);
    final endian = bytes[0] == 1 ? Endian.little : Endian.big;
    if (bytes[0] != 0 && bytes[0] != 1) {
      throw FormatException('Invalid point geometry byte order');
    }

    final geometryType = data.getUint32(1, endian);
    if ((geometryType & 0x000000FF) != 1) {
      throw FormatException('Memory geometry is not a point');
    }
    final hasSrid = (geometryType & 0x20000000) != 0;
    final coordinateOffset = hasSrid ? 9 : 5;
    final longitude = data.getFloat64(coordinateOffset, endian);
    final latitude = data.getFloat64(coordinateOffset + 8, endian);
    return LatLng(latitude, longitude);
  }
}
