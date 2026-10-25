import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'memory_pin_service.dart';

class CommuterFriend {
  final String id;
  final String name;

  const CommuterFriend({required this.id, required this.name});
}

class SharedMemoryPhoto {
  final String photoId;
  final String ownerId;
  final String ownerName;
  final String placeName;
  final String? address;
  final LatLng coordinates;
  final String imageUrl;
  final DateTime createdAt;

  const SharedMemoryPhoto({
    required this.photoId,
    required this.ownerId,
    required this.ownerName,
    required this.placeName,
    required this.address,
    required this.coordinates,
    required this.imageUrl,
    required this.createdAt,
  });
}

class MemoryPhotoShare {
  final String friendId;
  final String friendName;

  const MemoryPhotoShare({required this.friendId, required this.friendName});
}

class FriendSharingService {
  FriendSharingService._();

  static const int inviteValidityHours = 24;
  static final ValueNotifier<List<SharedMemoryPhoto>> sharedPhotos =
      ValueNotifier([]);

  static SupabaseClient get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw StateError('Cloud services are not configured.');
    }
  }

  static void _requireSignedIn() {
    if (_client.auth.currentUser == null) {
      throw StateError('Sign in to use friend sharing.');
    }
  }

  static Future<({String code, DateTime expiresAt})> createInvite() async {
    _requireSignedIn();
    final result = await _client.rpc('create_friend_invite');
    final row = (result as List).single as Map;
    return (
      code: row['invite_code'] as String,
      expiresAt: DateTime.parse(row['expires_at'] as String),
    );
  }

  static Future<void> acceptInvite(String code) async {
    _requireSignedIn();
    final normalized = code.trim();
    if (!RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(normalized)) {
      throw const FormatException(
        'Enter the complete 64-character invite code.',
      );
    }
    await _client.rpc(
      'accept_friend_invite',
      params: {'p_invite_code': normalized},
    );
  }

  static Future<List<CommuterFriend>> listFriends() async {
    _requireSignedIn();
    final result = await _client.rpc('list_friends') as List;
    return result.map((item) {
      final row = item as Map;
      final id = row['friend_id'];
      if (id is! String) {
        throw const FormatException(
          'Friend list contained an invalid account.',
        );
      }
      return CommuterFriend(
        id: id,
        name: row['friend_name'] as String? ?? 'Mapparaan commuter',
      );
    }).toList();
  }

  static Future<void> removeFriend(String friendId) async {
    _requireSignedIn();
    await _client.rpc('remove_friend', params: {'p_friend_id': friendId});
  }

  static Future<List<MemoryPhotoShare>> listPhotoShares(String photoId) async {
    _requireSignedIn();
    final result = await _client.rpc(
      'list_memory_pin_shares',
      params: {'p_memory_pin_id': photoId},
    ) as List;
    return result.map((item) {
      final row = item as Map;
      return MemoryPhotoShare(
        friendId: row['friend_id'] as String,
        friendName: row['friend_name'] as String? ?? 'Mapparaan commuter',
      );
    }).toList();
  }

  static Future<void> setPhotoShares({
    required String photoId,
    required List<String> friendIds,
  }) async {
    _requireSignedIn();
    await _client.rpc(
      'set_memory_pin_shares',
      params: {
        'p_memory_pin_id': photoId,
        'p_friend_ids': friendIds,
        'p_area_code': null,
      },
    );
  }

  static Future<List<SharedMemoryPhoto>> refreshSharedPhotos() async {
    final photos = await listSharedPhotos();
    sharedPhotos.value = photos;
    return photos;
  }

  static void clearSharedPhotos() {
    sharedPhotos.value = [];
  }

  static Future<List<SharedMemoryPhoto>> listSharedPhotos() async {
    _requireSignedIn();
    final result =
        await _client.rpc('list_shared_memory_photos_with_location') as List;
    return Future.wait(
      result.map((item) async {
        final row = item as Map;
        final ownerId = row['owner_id'] as String;
        final imagePath = row['image_path'] as String;
        final latitude = row['latitude'];
        final longitude = row['longitude'];
        if (latitude is! num ||
            longitude is! num ||
            !latitude.isFinite ||
            !longitude.isFinite ||
            latitude < -90 ||
            latitude > 90 ||
            longitude < -180 ||
            longitude > 180) {
          throw const FormatException(
            'Shared photo contains an invalid map location.',
          );
        }
        if (!imagePath.startsWith('$ownerId/')) {
          throw const FormatException('Shared photo path is invalid.');
        }
        final signedUrl = await MemoryPinService.signedSharedImageUrl(
          ownerId,
          imagePath,
        );
        return SharedMemoryPhoto(
          photoId: row['photo_id'] as String,
          ownerId: ownerId,
          ownerName: row['owner_name'] as String? ?? 'Mapparaan commuter',
          placeName: row['place_name'] as String,
          address: row['address'] as String?,
          coordinates: LatLng(latitude.toDouble(), longitude.toDouble()),
          imageUrl: signedUrl,
          createdAt: DateTime.parse(row['created_at'] as String),
        );
      }),
    );
  }
}
