import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/friend_sharing_service.dart';

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
                ...data.photos.map(
                  (photo) => Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 10,
                          child: Image.network(
                            photo.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Center(
                              child: Text(
                                'Photo unavailable. Refresh to request a new private link.',
                              ),
                            ),
                          ),
                        ),
                        ListTile(
                          title: Text(photo.placeName),
                          subtitle: Text(
                            [
                              if (photo.address?.isNotEmpty == true)
                                photo.address!,
                              'Shared by ${photo.ownerName}',
                            ].join(' · '),
                          ),
                          leading: const Icon(Icons.location_on_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FriendsPageData {
  final List<CommuterFriend> friends;
  final List<SharedMemoryPhoto> photos;

  const _FriendsPageData({required this.friends, required this.photos});
}
