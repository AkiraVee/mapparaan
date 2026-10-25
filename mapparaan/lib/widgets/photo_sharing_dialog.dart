import 'package:flutter/material.dart';

import '../services/friend_sharing_service.dart';

class PhotoShareSelection {
  final List<String> friendIds;

  const PhotoShareSelection({required this.friendIds});
}

class PhotoSharingDialog extends StatefulWidget {
  final List<CommuterFriend> friends;
  final List<String> initialFriendIds;
  final String? informationMessage;

  const PhotoSharingDialog({
    super.key,
    required this.friends,
    this.initialFriendIds = const [],
    this.informationMessage,
  });

  @override
  State<PhotoSharingDialog> createState() => _PhotoSharingDialogState();
}

class _PhotoSharingDialogState extends State<PhotoSharingDialog> {
  late final Set<String> _selectedFriendIds;

  @override
  void initState() {
    super.initState();
    _selectedFriendIds = widget.initialFriendIds.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final isSharing = _selectedFriendIds.isNotEmpty;

    return AlertDialog(
      title: const Text('Photo privacy'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No friends are selected by default, so this photo stays private.',
              ),
              const SizedBox(height: 8),
              Text(
                'Selected friends will see the saved place name and exact map pin, along with the photo.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (widget.informationMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  widget.informationMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              if (widget.friends.isEmpty)
                const Text(
                  'You have no accepted friends yet. You can add friends from the Friends page.',
                )
              else
                ...widget.friends.map(
                  (friend) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _selectedFriendIds.contains(friend.id),
                    title: Text(friend.name),
                    onChanged: (selected) {
                      setState(() {
                        if (selected == true) {
                          _selectedFriendIds.add(friend.id);
                        } else {
                          _selectedFriendIds.remove(friend.id);
                        }
                      });
                    },
                  ),
                ),
              if (isSharing) ...[
                const SizedBox(height: 8),
                Text(
                  'A photo can still reveal a venue through signs, logos, or other details in the image.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context)
              .pop(PhotoShareSelection(friendIds: _selectedFriendIds.toList())),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
