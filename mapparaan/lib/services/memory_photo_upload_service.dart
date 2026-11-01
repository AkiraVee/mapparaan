import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'auth_service.dart';
import 'friend_sharing_service.dart';
import 'memory_photo_compression_service.dart';
import 'memory_pin_service.dart';
import 'place_search_service.dart';
import '../widgets/photo_sharing_dialog.dart';

enum MemoryPhotoUploadOutcome { private, shared, privateSharingFailed }

class MemoryPhotoUploadService {
  MemoryPhotoUploadService._();

  static Future<MemoryPhotoUploadOutcome?> upload(
    BuildContext context,
    PlaceResult place,
  ) async {
    if (!AuthService.isLoggedIn.value) {
      throw StateError('Sign in before uploading a memory photo.');
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return null;

    final pickedFile = await ImagePicker().pickImage(
      source: source,
      maxWidth: MemoryPhotoCompressionService.maxDimension.toDouble(),
      maxHeight: MemoryPhotoCompressionService.maxDimension.toDouble(),
      imageQuality: 100,
    );
    if (pickedFile == null || !context.mounted) return null;

    final imageBytes = await MemoryPhotoCompressionService.compress(
      await pickedFile.readAsBytes(),
    );

    List<CommuterFriend> friends = [];
    String? friendLoadMessage;
    try {
      friends = await FriendSharingService.listFriends();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('while loading photo sharing options'),
        ),
      );
      friendLoadMessage = 'Accepted friends could not be loaded. This photo can only be kept private right now.';
    }
    if (!context.mounted) return null;

    final sharing = await showDialog<PhotoShareSelection>(
      context: context,
      builder: (_) => PhotoSharingDialog(
        friends: friends,
        informationMessage: friendLoadMessage,
      ),
    );
    if (sharing == null || !context.mounted) return null;

    final pinId = await MemoryPinService.addPin(
      placeName: place.name,
      address: place.subtitle,
      coordinates: place.coordinates,
      fileName: 'memory-${const Uuid().v4()}.jpg',
      contentType: 'image/jpeg',
      imageBytes: imageBytes,
    );

    if (sharing.friendIds.isEmpty) return MemoryPhotoUploadOutcome.private;
    try {
      await FriendSharingService.setPhotoShares(
        photoId: pinId,
        friendIds: sharing.friendIds,
      );
      return MemoryPhotoUploadOutcome.shared;
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('while sharing a memory photo'),
        ),
      );
      return MemoryPhotoUploadOutcome.privateSharingFailed;
    }
  }
}
