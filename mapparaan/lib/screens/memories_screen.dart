import 'package:flutter/material.dart';

import '../services/ai_assistant_service.dart';

import '../services/memory_photo_upload_service.dart';
import '../services/memory_pin_service.dart';
import '../services/place_search_service.dart';
import '../services/saved_places_service.dart';
import '../services/trip_history_service.dart';
import 'search_location_screen.dart';

class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({super.key});

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  late Future<_MemorySources> _sources;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _sources = _loadSources();
  }

  Future<_MemorySources> _loadSources() async {
    final results = await Future.wait([
      SavedPlacesService.load(),
      TripHistoryService.load(limit: 5),
    ]);
    return _MemorySources(
      savedPlaces: results[0] as List<SavedPlace>,
      recentTrips: results[1] as List<TripHistoryEntry>,
    );
  }

  Future<void> _refreshSources() async {
    final future = _loadSources();
    setState(() => _sources = future);
    try {
      await Future.wait([future, MemoryPinService.loadMemoryPins()]);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('while refreshing the memories screen'),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Some memories could not be refreshed.'),
          ),
        );
      }
    }
  }

  Future<void> _chooseFromSearch({String? initialQuery}) async {
    final selection = await Navigator.of(context).push<SearchSelection>(
      SearchLocationScreen.route(
        screen: SearchLocationScreen(
          initialQuery: initialQuery,
          selectionActionLabel: 'Use this place',
          showMap: true,
        ),
      ),
    );
    if (!mounted || selection == null) return;
    await _uploadAt(selection.place);
  }

  Future<void> _uploadAt(PlaceResult place) async {
    if (_isUploading) return;
    setState(() => _isUploading = true);
    try {
      final outcome = await MemoryPhotoUploadService.upload(context, place);
      if (!mounted || outcome == null) return;
      final message = switch (outcome) {
        MemoryPhotoUploadOutcome.private =>
          'Memory added privately at ${place.name}.',
        MemoryPhotoUploadOutcome.shared =>
          'Memory shared with your selected friends.',
        MemoryPhotoUploadOutcome.privateSharingFailed => 'Photo saved privately. Sharing failed; manage sharing from your profile.',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('while adding a memory photo'),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not add this memory. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Map<String, List<MemoryPin>> _groupMemories(List<MemoryPin> pins) {
    final groups = <String, List<MemoryPin>>{};
    for (final pin in pins) {
      groups.putIfAbsent(pin.placeName, () => []).add(pin);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _refreshSources,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text(
            'Keep the places you remember.',
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isUploading ? null : () => _chooseFromSearch(),
            icon: _isUploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_a_photo_outlined),
            label: Text(_isUploading ? 'Adding memory…' : 'Add memory'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: 24),
          FutureBuilder<_MemorySources>(
            future: _sources,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _LoadError(onRetry: _refreshSources);
              }
              if (!snapshot.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              final sources = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeading(
                    title: 'From saved places',
                    subtitle: 'Choose a saved location as your photo pin.',
                  ),
                  if (sources.savedPlaces.isEmpty)
                    const _InlineEmptyState(
                      message: 'No saved places yet. Search for a place to add a memory.',
                    )
                  else
                    ...sources.savedPlaces.map(
                      (place) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.bookmark_outline),
                          title: Text(place.name),
                          subtitle: place.subtitle.isEmpty
                              ? null
                              : Text(
                                  place.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: IconButton(
                            tooltip: 'Add a memory at ${place.name}',
                            icon: const Icon(Icons.add_a_photo_outlined),
                            onPressed: _isUploading
                                ? null
                                : () => _uploadAt(
                                    PlaceResult(
                                      name: place.name,
                                      subtitle: place.subtitle,
                                      coordinates: place.coordinates,
                                    ),
                                  ),
                          ),
                          onTap: _isUploading
                              ? null
                              : () => _uploadAt(
                                  PlaceResult(
                                    name: place.name,
                                    subtitle: place.subtitle,
                                    coordinates: place.coordinates,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  _SectionHeading(
                    title: 'From recent trip plans',
                    subtitle: 'Trip history records planned routes, not verified visits. Confirm the destination before attaching a memory.',
                  ),
                  if (sources.recentTrips.isEmpty)
                    const _InlineEmptyState(
                      message:
                          'Your recent trip destinations will appear here.',
                    )
                  else
                    ...sources.recentTrips.map(
                      (trip) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(
                            trip.destination,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text('Planned ${trip.etaText}'),
                          trailing: TextButton(
                            onPressed: _isUploading
                                ? null
                                : () => _chooseFromSearch(
                                    initialQuery: trip.destination,
                                  ),
                            child: const Text('Find place'),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          ValueListenableBuilder<MemoryPinLoadStatus>(
            valueListenable: MemoryPinService.loadStatus,
            builder: (context, loadStatus, _) =>
                ValueListenableBuilder<List<MemoryPin>>(
                  valueListenable: MemoryPinService.pins,
                  builder: (context, pins, _) {
                    final albums = _groupMemories(pins).values.toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionHeading(
                          title: 'My memories',
                          subtitle:
                              '${pins.length} ${pins.length == 1 ? 'photo' : 'photos'}',
                        ),
                        if (loadStatus == MemoryPinLoadStatus.loading &&
                            pins.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (loadStatus == MemoryPinLoadStatus.error &&
                            pins.isEmpty)
                          _LoadError(
                            message: 'Your memories could not be loaded.',
                            onRetry: MemoryPinService.loadMemoryPins,
                          )
                        else if (albums.isEmpty)
                          const _InlineEmptyState(
                            message: 'Your saved photos will appear here. They are private unless you choose friends to share with.',
                          )
                        else
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final columns = constraints.maxWidth >= 640
                                  ? 3
                                  : 2;
                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: 0.9,
                                    ),
                                itemCount: albums.length,
                                itemBuilder: (context, index) {
                                  final album = albums[index];
                                  final newest = album.last;
                                  return Card(
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: () => _showAlbum(album),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: SizedBox.expand(
                                              child: newest.imageUrl.isEmpty
                                                  ? const Center(
                                                      child: Icon(
                                                        Icons.image_outlined,
                                                      ),
                                                    )
                                                  : Image.network(
                                                      newest.imageUrl,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (_, _, _) =>
                                                          const Center(
                                                            child: Icon(
                                                              Icons
                                                                  .broken_image_outlined,
                                                            ),
                                                          ),
                                                    ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(10),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  newest.placeName,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                if (album.length > 1)
                                                  Text(
                                                    '${album.length} photos',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                      ],
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAlbum(List<MemoryPin> album) async {
    var index = 0;
    final controller = PageController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final pin = album[index];
          return AlertDialog(
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    pin.placeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (album.length > 1) Text('${index + 1}/${album.length}'),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 4 / 3,
                    child: PageView.builder(
                      controller: controller,
                      itemCount: album.length,
                      onPageChanged: (value) =>
                          setDialogState(() => index = value),
                      itemBuilder: (context, itemIndex) {
                        final item = album[itemIndex];
                        return item.imageUrl.isEmpty
                            ? const Center(child: Icon(Icons.image_outlined))
                            : Image.network(
                                item.imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              );
                      },
                    ),
                  ),
                  if (pin.address.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(pin.address),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: dialogContext,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete memory photo?'),
                      content: const Text(
                        'This permanently deletes the selected photo.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  try {
                    await MemoryPinService.deletePin(pin.id);
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  } catch (error, stackTrace) {
                    FlutterError.reportError(
                      FlutterErrorDetails(
                        exception: error,
                        stack: stackTrace,
                        context: ErrorDescription(
                          'while deleting a memory photo',
                        ),
                      ),
                    );
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Could not delete the photo.'),
                        ),
                      );
                    }
                  }
                },
                child: const Text('Delete photo'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
  }
}

class _MemorySources {
  final List<SavedPlace> savedPlaces;
  final List<TripHistoryEntry> recentTrips;

  const _MemorySources({required this.savedPlaces, required this.recentTrips});
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionHeading({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  final String message;

  const _InlineEmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _LoadError({
    this.message = 'Places and recent trips could not be loaded.',
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(message),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}
