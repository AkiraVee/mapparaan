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
    final isEditingShare = widget.initialFriendIds.isNotEmpty;
    final actionLabel = switch ((isSharing, isEditingShare)) {
      (true, true) => 'Update sharing',
      (true, false) =>
        'Share with ${_selectedFriendIds.length} ${_selectedFriendIds.length == 1 ? 'friend' : 'friends'}',
      (false, true) => 'Make private',
      (false, false) => 'Keep private',
    };

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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSharing
                      ? Theme.of(context).colorScheme.errorContainer
                      : Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isSharing ? Icons.location_on : Icons.lock_outline,
                      color: isSharing
                          ? Theme.of(context).colorScheme.onErrorContainer
                          : Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isSharing
                            ? 'Sharing reveals this photo, its saved place, and the exact map pin to the selected friends. The location cannot be hidden separately.'
                            : 'No friends are selected. This photo stays private; selecting a friend will also reveal its saved place and exact map pin.',
                        style: TextStyle(
                          color: isSharing
                              ? Theme.of(context).colorScheme.onErrorContainer
                              : Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
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
                  'The image itself may reveal more through faces, signs, logos, or other details. Only share with people you trust.',
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
          child: Text(actionLabel),
        ),
      ],
    );
  }
}
