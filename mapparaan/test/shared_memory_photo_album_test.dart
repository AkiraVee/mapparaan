import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapparaan/services/friend_sharing_service.dart';

void main() {
  test('groups shared photos by friend and location, newest album first', () {
    final earlier = _photo(
      photoId: 'earlier',
      ownerId: 'friend-a',
      placeName: 'University',
      latitude: 14.5995001,
      createdAt: DateTime(2026, 1, 1),
    );
    final later = _photo(
      photoId: 'later',
      ownerId: 'friend-a',
      placeName: 'University',
      latitude: 14.5995002,
      createdAt: DateTime(2026, 1, 2),
    );
    final otherFriend = _photo(
      photoId: 'other-friend',
      ownerId: 'friend-b',
      placeName: 'University',
      latitude: 14.5995001,
      createdAt: DateTime(2026, 1, 3),
    );
    final otherPlace = _photo(
      photoId: 'other-place',
      ownerId: 'friend-a',
      placeName: 'Rizal Park',
      latitude: 14.5996001,
      createdAt: DateTime(2026, 1, 4),
    );

    final albums = groupSharedMemoryPhotosByOwnerAndLocation([
      earlier,
      otherFriend,
      later,
      otherPlace,
    ]);

    expect(albums, hasLength(3));
    expect(albums[0].map((photo) => photo.photoId), ['other-place']);
    expect(albums[1].map((photo) => photo.photoId), ['other-friend']);
    expect(albums[2].map((photo) => photo.photoId), ['earlier', 'later']);
  });
}

SharedMemoryPhoto _photo({
  required String photoId,
  required String ownerId,
  required String placeName,
  required double latitude,
  required DateTime createdAt,
}) {
  return SharedMemoryPhoto(
    photoId: photoId,
    ownerId: ownerId,
    ownerName: ownerId,
    placeName: placeName,
    address: null,
    coordinates: LatLng(latitude, 120.9842),
    imageUrl: 'https://example.com/$photoId.jpg',
    createdAt: createdAt,
  );
}
