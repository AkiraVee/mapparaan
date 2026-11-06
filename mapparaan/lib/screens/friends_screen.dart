import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:share_plus/share_plus.dart';

import '../services/friend_sharing_service.dart';
import '../services/local_ui_preferences_service.dart';
import '../widgets/mapparaan_tile_layer.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late Future<_FriendsPageData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_FriendsPageData> _load() async {
    final results = await Future.wait([
      FriendSharingService.listFriends(),
      FriendSharingService.refreshSharedPhotos(),
    ]);
    return _FriendsPageData(
      friends: results[0] as List<CommuterFriend>,
      photos: results[1] as List<SharedMemoryPhoto>,
    );
  }

  void _reload() {
    setState(() => _data = _load());
  }

  Future<void> _refresh() async {
    final refreshed = _load();
    setState(() => _data = refreshed);
    await refreshed;
  }

  Future<void> _createInvite() async {
    try {
      final invite = await FriendSharingService.createInvite();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Friend invite created'),
          content: SelectableText(
            'Share this one-time code privately. It expires at '
            '${invite.expiresAt.toLocal()}.\n\n${invite.code}',
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: invite.code));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _showMessage('Invite code copied.');
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy code'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await SharePlus.instance.share(
                  ShareParams(
                    subject: 'Mapparaan friend invite',
                    text:
                        'Use this one-time Mapparaan friend invite code within 24 hours:\n${invite.code}',
                  ),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share code'),
            ),
          ],
        ),
      );
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'creating a friend invite');
      if (mounted) {
        _showMessage('Could not create an invite. Please try again.');
      }
    }
  }

  Future<void> _acceptInvite() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Accept friend invite'),
        content: TextField(
          controller: controller,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: '64-character invite code',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || !mounted) return;

    try {
      await FriendSharingService.acceptInvite(code);
      _reload();
      _showMessage(
        'Friend added. Shared photos are not restored automatically.',
      );
    } on FormatException catch (error) {
      _showMessage(error.message);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'accepting a friend invite');
      if (mounted) {
        _showMessage(
          'Invite could not be accepted. Check the code and try again.',
        );
      }
    }
  }

  Future<void> _removeFriend(CommuterFriend friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove friend?'),
        content: Text(
          'This removes ${friend.name} and revokes their access to photos you shared. It cannot recall a photo they already saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove friend'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await FriendSharingService.removeFriend(friend.id);
      _reload();
      _showMessage('Friend removed and photo sharing access revoked.');
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'removing a friend');
      if (mounted) {
        _showMessage('Could not remove this friend. Please try again.');
      }
    }
  }

  void _report(Object error, StackTrace stackTrace, String contextDescription) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        context: ErrorDescription('while $contextDescription'),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_FriendsPageData>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Friends and shared photos could not be loaded.'),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const Text(
                'Friends',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Invites are single-use and expire after 24 hours. Only selected photos are shared.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _createInvite,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Create invite'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _acceptInvite,
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Enter invite code'),
                  ),
                ],
              ),
              const Divider(height: 32),
              Text(
                'Accepted friends (${data.friends.length})',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (data.friends.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('You have no accepted friends yet.'),
                )
              else
                ...data.friends.map(
                  (friend) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      child: Icon(Icons.person_outline),
                    ),
                    title: Text(friend.name),
                    trailing: IconButton(
                      tooltip: 'Remove ${friend.name}',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: () => _removeFriend(friend),
                    ),
                  ),
                ),
              const Divider(height: 32),
              const Text(
                'Photos shared with you',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Shared photos show the saved place and exact map location. Images may also contain identifying details.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (data.photos.isEmpty)
                const Text('No friends have shared photos with you.')
              else
                ...groupSharedMemoryPhotosByOwnerAndLocation(data.photos).map(
                  _buildSharedPhotoAlbum,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSharedPhotoAlbum(List<SharedMemoryPhoto> album) {
    final cover = album.last;
    return ValueListenableBuilder<LocalUiPreferences>(
      valueListenable: LocalUiPreferencesService.current,
      builder: (context, preferences, _) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showSharedPhotoAlbum(album),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (preferences.dataSaver)
                      ColoredBox(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.data_saver_off_outlined, size: 32),
                              SizedBox(height: 8),
                              Text('Open album to load photos'),
                            ],
                          ),
                        ),
                      )
                    else
                      Image.network(
                        cover.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Text(
                            'Photo unavailable. Refresh to request a new private link.',
                          ),
                        ),
                      ),
                    if (album.length > 1)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.photo_library_outlined,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '${album.length} photos',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              ListTile(
                title: Text(cover.placeName),
                subtitle: Text(
                  [
                    if (cover.address?.isNotEmpty == true) cover.address!,
                    'Shared by ${cover.ownerName}',
                    'Last shared ${MaterialLocalizations.of(context).formatMediumDate(cover.createdAt.toLocal())}',
                  ].join(' · '),
                ),
                leading: const Icon(Icons.location_on_outlined),
                trailing: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSharedPhotoAlbum(List<SharedMemoryPhoto> album) async {
    var currentIndex = 0;
    var showMap = false;
    var allowMapInDataSaver =
        !LocalUiPreferencesService.current.value.dataSaver;
    final pageController = PageController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final photo = album[currentIndex];
          return AlertDialog(
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    photo.placeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (album.length > 1)
                  Text(
                    '${currentIndex + 1} / ${album.length}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
              ],
            ),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                maxHeight: MediaQuery.sizeOf(context).height * 0.7,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  AspectRatio(
                    aspectRatio: 16 / 10,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PageView.builder(
                          controller: pageController,
                          itemCount: album.length,
                          onPageChanged: (index) =>
                              setDialogState(() => currentIndex = index),
                          itemBuilder: (context, index) => Image.network(
                            album[index].imageUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (_, _, _) => const Center(
                              child: Text(
                                'Photo unavailable. Refresh to request a new private link.',
                              ),
                            ),
                          ),
                        ),
                        if (album.length > 1) ...[
                          if (currentIndex > 0)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton.filled(
                                tooltip: 'Previous photo',
                                onPressed: () => pageController.previousPage(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                ),
                                icon: const Icon(Icons.chevron_left),
                              ),
                            ),
                          if (currentIndex < album.length - 1)
                            Align(
                              alignment: Alignment.centerRight,
                              child: IconButton.filled(
                                tooltip: 'Next photo',
                                onPressed: () => pageController.nextPage(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                ),
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  if (photo.address?.isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    Text(photo.address!),
                  ],
                  const SizedBox(height: 8),
                  Text('Shared by ${photo.ownerName}'),
                  Text(
                    'Shared on ${MaterialLocalizations.of(context).formatMediumDate(photo.createdAt.toLocal())} at ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(photo.createdAt.toLocal()))}',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => setDialogState(() {
                      showMap = !showMap;
                    }),
                    icon: Icon(
                      showMap ? Icons.map_outlined : Icons.location_on_outlined,
                    ),
                    label: Text(showMap ? 'Hide album map' : 'Show album map'),
                  ),
                  if (showMap && !allowMapInDataSaver) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Data-saver mode is on. Loading this map uses mobile data.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    TextButton(
                      onPressed: () =>
                          setDialogState(() => allowMapInDataSaver = true),
                      child: const Text('Load map anyway'),
                    ),
                  ],
                  if (showMap && allowMapInDataSaver) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 160,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: photo.coordinates,
                            initialZoom: 15,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.all &
                                  ~InteractiveFlag.rotate,
                            ),
                          ),
                          children: [
                            const MapparaanTileLayer(),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: photo.coordinates,
                                  width: 40,
                                  height: 40,
                                  child: Icon(
                                    Icons.location_on,
                                    color: Theme.of(context).colorScheme.error,
                                    size: 36,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
    pageController.dispose();
  }

}

class _FriendsPageData {
  final List<CommuterFriend> friends;
  final List<SharedMemoryPhoto> photos;

  const _FriendsPageData({required this.friends, required this.photos});
}
