import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../services/ai_assistant_service.dart';
import '../services/memory_pin_service.dart';
import '../services/place_search_service.dart';
import '../services/route_planner_service.dart';
import '../services/saved_commute_service.dart';
import '../services/last_route_service.dart';
import '../services/local_ui_preferences_service.dart';
import '../widgets/ask_mapparaan_bar.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/mapparaan_drawer.dart';
import '../widgets/mapparaan_tile_layer.dart';
import '../widgets/memory_pin_marker.dart'; // <-- Added the new marker import here!
import 'location_details_screen.dart';
import 'location_disabled_screen.dart';
import 'search_location_screen.dart';

class HomeScreen extends StatefulWidget {
  final bool showMap;
  final PlaceSearch searchPlaces;

  const HomeScreen({
    super.key,
    this.showMap = true,
    this.searchPlaces = PlaceSearchService.search,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _bottomAskController = TextEditingController();
  final MapController _mapController = MapController();

  LatLng? _userLocation;
  final RoutePreference _homePreference = RoutePreference.fastest;
  List<SavedCommute> _savedCommutes = const [];
  LocalUiPreferences _localPreferences = const LocalUiPreferences();

  @override
  void initState() {
    super.initState();
    _initUserLocation();
    _loadSavedCommutes();
    _loadLocalPreferences();
  }

  Future<void> _loadLocalPreferences() async {
    final preferences = await LocalUiPreferencesService.load();
    if (mounted) setState(() => _localPreferences = preferences);
  }

  Future<void> _saveLocalPreferences(LocalUiPreferences preferences) async {
    await LocalUiPreferencesService.save(preferences);
    if (mounted) setState(() => _localPreferences = preferences);
  }

  Future<void> _loadSavedCommutes() async {
    final saved = await SavedCommuteService.load();
    if (mounted) setState(() => _savedCommutes = saved);
  }

  Future<void> _initUserLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return;
      if (!serviceEnabled) {
        await _openLocationHelp();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (!mounted) return;
        if (permission == LocationPermission.denied) {
          await _openLocationHelp();
          return;
        }
      }

      if (!mounted) return;
      if (permission == LocationPermission.deniedForever) {
        await _openLocationHelp();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;

      final userLatLng = LatLng(position.latitude, position.longitude);
      setState(() => _userLocation = userLatLng);
      _mapController.move(userLatLng, 15.0);
    } catch (_) {
      if (mounted) {
        _showMessage('Could not get your current location.');
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _bottomAskController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _selectPlace(
    PlaceResult place, {
    RoutePreference? preference,
    PassengerType? passengerType,
  }) async {
    _searchController.text = place.name;
    if (widget.showMap) _mapController.move(place.coordinates, 16.0);

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocationDetailsScreen(
          place: place,
          userLocation: _userLocation,
          initialPreference: preference ?? _homePreference,
          passengerType: passengerType ?? PassengerType.general,
          localPreferences: _localPreferences,
        ),
      ),
    );

    if (!mounted) return;
    _searchController.clear();
  }

  Future<void> _openSavedCommute(SavedCommute commute) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocationDetailsScreen(
          place: PlaceResult(
            name: commute.destinationName,
            subtitle: commute.originName,
            coordinates: commute.destination,
          ),
          userLocation: commute.origin,
          origin: commute.originName,
          initialPreference: commute.preference,
          passengerType: commute.passengerType,
          localPreferences: _localPreferences,
        ),
      ),
    );
    if (mounted) _loadSavedCommutes();
  }

  Future<void> _showLocalTools() async {
    var sheetPreferences = _localPreferences;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final preferences = sheetPreferences;

          Future<void> update(LocalUiPreferences next) async {
            sheetPreferences = next;
            setSheetState(() {});
            await _saveLocalPreferences(next);
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Commute tools',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  const Text(
                    'These settings are saved on this device and do not change transit data.',
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    title: const Text('Senior-friendly mode'),
                    subtitle: const Text('Larger controls and simpler choices'),
                    value: preferences.seniorMode,
                    onChanged: (value) =>
                        update(preferences.copyWith(seniorMode: value)),
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('Simple-words mode'),
                    subtitle: const Text('Use shorter labels and explanations'),
                    value: preferences.simpleWords,
                    onChanged: (value) =>
                        update(preferences.copyWith(simpleWords: value)),
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('Data-saver mode'),
                    subtitle: const Text('Reduce map detail and image loading'),
                    value: preferences.dataSaver,
                    onChanged: (value) =>
                        update(preferences.copyWith(dataSaver: value)),
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('Accessible-route preference'),
                    subtitle: const Text('Prefer routes marked as accessible'),
                    value: preferences.accessibleOnly,
                    onChanged: (value) =>
                        update(preferences.copyWith(accessibleOnly: value)),
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('Avoid stairs'),
                    value: preferences.avoidStairs,
                    onChanged: (value) =>
                        update(preferences.copyWith(avoidStairs: value)),
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('Avoid flood-prone areas'),
                    subtitle: const Text(
                      'Requires advisory data when available',
                    ),
                    value: preferences.avoidFloods,
                    onChanged: (value) =>
                        update(preferences.copyWith(avoidFloods: value)),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Language'),
                    subtitle: const Text('UI translation preference'),
                    trailing: DropdownButton<String>(
                      value: preferences.language,
                      items: const [
                        DropdownMenuItem(
                          value: 'English',
                          child: Text('English'),
                        ),
                        DropdownMenuItem(
                          value: 'Filipino',
                          child: Text('Filipino'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          update(preferences.copyWith(language: value));
                        }
                      },
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Walking-distance limit'),
                    subtitle: Text(
                      preferences.walkingLimitKm == null
                          ? 'No limit set'
                          : '${preferences.walkingLimitKm!.toStringAsFixed(1)} km maximum',
                    ),
                    trailing: PopupMenuButton<double?>(
                      tooltip: 'Set walking limit',
                      initialValue: preferences.walkingLimitKm,
                      onSelected: (value) =>
                          update(preferences.copyWith(walkingLimitKm: value)),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: null, child: Text('No limit')),
                        PopupMenuItem(value: 0.5, child: Text('0.5 km')),
                        PopupMenuItem(value: 1.0, child: Text('1.0 km')),
                        PopupMenuItem(value: 2.0, child: Text('2.0 km')),
                      ],
                      child: const Icon(Icons.tune),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calculate_outlined),
                    title: const Text('Offline budget insights'),
                    subtitle: const Text('Use the last saved route estimate'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showBudgetInsights();
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.alt_route),
                    title: const Text('Draft a multi-stop trip'),
                    subtitle: const Text(
                      'Prepare stops before route support is available',
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showMultiStopDraft();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showBudgetInsights() async {
    final cached = await LastRouteService.load();
    if (!mounted) return;
    if (cached == null) {
      _showMessage('Plan and save a route first to see budget insights.');
      return;
    }
    final fare = cached.option.effectiveFare(PassengerType.general);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Offline budget insights'),
        content: Text(
          'Based on the last saved estimate:\n\n'
          'Daily return commute: ₱${(fare * 2).toStringAsFixed(2)}\n'
          'Monthly estimate (22 days): ₱${(fare * 2 * 22).toStringAsFixed(2)}\n\n'
          'This is an estimate. Verify the fare before travelling.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMultiStopDraft() async {
    final stopController = TextEditingController();
    final stops = <String>[];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Multi-stop trip draft'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Add stops in visit order.'),
                ),
                const SizedBox(height: 8),
                ...stops.asMap().entries.map(
                  (entry) => ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 12,
                      child: Text('${entry.key + 1}'),
                    ),
                    title: Text(entry.value),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () =>
                          setDialogState(() => stops.removeAt(entry.key)),
                    ),
                  ),
                ),
                TextField(
                  controller: stopController,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: stops.isEmpty
                        ? 'First stop'
                        : 'Add another stop',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        final value = stopController.text.trim();
                        if (value.isEmpty) return;
                        setDialogState(() {
                          stops.add(value);
                          stopController.clear();
                        });
                      },
                    ),
                  ),
                  onSubmitted: (_) {
                    final value = stopController.text.trim();
                    if (value.isEmpty) return;
                    setDialogState(() {
                      stops.add(value);
                      stopController.clear();
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: stops.length < 2
                  ? null
                  : () {
                      Navigator.pop(dialogContext);
                      _showMessage(
                        'Trip draft saved for ${stops.length} stops. Route calculation will be available when multi-stop planning is connected.',
                      );
                    },
              child: const Text('Save draft'),
            ),
          ],
        ),
      ),
    );
    stopController.dispose();
  }

  Future<void> _goToSearchScreen([String? prefilledQuery]) async {
    final selection = await Navigator.of(context).push<SearchSelection>(
      MaterialPageRoute(
        builder: (context) => SearchLocationScreen(
          initialQuery: prefilledQuery,
          showMap: widget.showMap,
          searchPlaces: widget.searchPlaces,
        ),
      ),
    );
    if (!mounted || selection == null) return;

    await _selectPlace(
      selection.place,
      preference: selection.resolution?.preference,
      passengerType: selection.resolution?.passengerType,
    );
  }

  Future<void> _handleAiQuery(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return;

    try {
      final results = await AiAssistantService.resolveQuery(query);
      if (!mounted) return;
      if (results.isEmpty) {
        _showMessage('No matching place found for that request.');
        return;
      }

      final resolution = AiQueryResolution.fromQuery(query);
      _bottomAskController.clear();
      await _selectPlace(
        results.first,
        preference: resolution.preference,
        passengerType: resolution.passengerType,
      );
    } catch (_) {
      if (mounted) _showMessage('Could not process your request.');
    }
  }

  Future<void> _openLocationHelp() async {
    final location = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute<LatLng>(builder: (_) => const LocationDisabledScreen()),
    );
    if (!mounted || location == null) return;
    setState(() => _userLocation = location);
    _mapController.move(location, 15.0);
  }

  Future<void> _goToMyLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return;
      if (!serviceEnabled) {
        await _openLocationHelp();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (!mounted) return;
        if (permission == LocationPermission.denied) {
          await _openLocationHelp();
          return;
        }
      }

      if (!mounted) return;
      if (permission == LocationPermission.deniedForever) {
        await _openLocationHelp();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;

      final userLatLng = LatLng(position.latitude, position.longitude);
      setState(() => _userLocation = userLatLng);
      _mapController.move(userLatLng, 15.0);
    } catch (e) {
      if (mounted) _showMessage('Error getting location: $e');
    }
  }

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 30,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMemoryAlbumDialog(List<MemoryPin> album) {
    int currentIndex = 0;
    final pageController = PageController();

    showDialog(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;

        return StatefulBuilder(
          builder: (context, setState) {
            final currentPin = album[currentIndex];

            return AlertDialog(
              contentPadding: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      currentPin.placeName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (album.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${currentIndex + 1} / ${album.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 250,
                    width: double.infinity,
                    child: Stack(
                      children: [
                        PageView.builder(
                          controller: pageController,
                          itemCount: album.length,
                          onPageChanged: (index) =>
                              setState(() => currentIndex = index),
                          itemBuilder: (context, index) {
                            final pin = album[index];
                            return GestureDetector(
                              onTap: () {
                                if (pin.imageUrl.isNotEmpty) {
                                  _showFullScreenImage(context, pin.imageUrl);
                                }
                              },
                              child: Container(
                                color: colorScheme.surfaceContainerHighest,
                                child: pin.imageUrl.isEmpty
                                    ? Center(
                                        child: Icon(
                                          Icons.image_not_supported_outlined,
                                          size: 50,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      )
                                    : Image.network(
                                        pin.imageUrl,
                                        fit: BoxFit.cover,
                                        loadingBuilder:
                                            (context, child, progress) {
                                              if (progress == null) {
                                                return child;
                                              }
                                              return const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              );
                                            },
                                        errorBuilder: (_, _, _) => Center(
                                          child: Icon(
                                            Icons.broken_image_outlined,
                                            size: 42,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                              ),
                            );
                          },
                        ),

                        // Navigation Arrows
                        if (album.length > 1) ...[
                          if (currentIndex > 0)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: CircleAvatar(
                                  backgroundColor: Colors.black45,
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.chevron_left,
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      pageController.previousPage(
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        curve: Curves.easeInOut,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          if (currentIndex < album.length - 1)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: CircleAvatar(
                                  backgroundColor: Colors.black45,
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.chevron_right,
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      pageController.nextPage(
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        curve: Curves.easeInOut,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            currentPin.address,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Close',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: const Text('Add Photo'),
                  onPressed: () {
                    Navigator.pop(context);
                    _selectPlace(
                      PlaceResult(
                        name: currentPin.placeName,
                        subtitle: currentPin.address,
                        coordinates: currentPin.coordinates,
                      ),
                    );
                  },
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  icon: const Icon(Icons.directions, size: 18),
                  label: const Text('Go Here'),
                  onPressed: () {
                    Navigator.pop(context);
                    _selectPlace(
                      PlaceResult(
                        name: currentPin.placeName,
                        subtitle: currentPin.address,
                        coordinates: currentPin.coordinates,
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: MapparaanDrawer(onPlaceSelected: _selectPlace),
      body: Stack(
        children: [
          if (widget.showMap)
            ValueListenableBuilder<List<MemoryPin>>(
              valueListenable: MemoryPinService.pins,
              builder: (context, memoryPins, _) {
                final visibleMemoryPins = _localPreferences.dataSaver
                    ? const <MemoryPin>[]
                    : memoryPins;
                final albumsMap = <String, List<MemoryPin>>{};
                for (final pin in visibleMemoryPins) {
                  albumsMap.putIfAbsent(pin.placeName, () => []).add(pin);
                }
                final albums = albumsMap.values.toList();

                return FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(
                      AppConstants.defaultLat,
                      AppConstants.defaultLng,
                    ),
                    initialZoom: AppConstants.defaultZoom,
                    minZoom: AppConstants.minZoom,
                    maxZoom: AppConstants.maxZoom,
                    cameraConstraint: CameraConstraint.contain(
                      bounds: AppConstants.manilaBounds,
                    ),
                  ),
                  children: [
                    const MapparaanTileLayer(),
                    if (_userLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _userLocation!,
                            width: 24,
                            height: 24,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.3),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                    // --- NEW MARKER INTEGRATION START ---
                    if (albums.isNotEmpty)
                      MarkerLayer(
                        markers: albums.map<Marker>((album) {
                          final latestPin = album.last;
                          return Marker(
                            point: latestPin.coordinates,
                            width: 50,
                            height: 54,
                            alignment: Alignment.topCenter,
                            child: MemoryPinMarker(
                              imageUrl: latestPin.imageUrl,
                              onTap: () => _showMemoryAlbumDialog(album),
                            ),
                          );
                        }).toList(),
                      ),
                    // --- NEW MARKER INTEGRATION END ---
                  ],
                );
              },
            )
          else
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
              ),
            ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Builder(
                    builder: (context) {
                      return CircleIconButton(
                        icon: Icons.menu,
                        onTap: () => Scaffold.of(context).openDrawer(),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AskMapparaanBar(
                      controller: _searchController,
                      hintText: 'Search here',
                      readOnly: true,
                      leadingIcon: Icons.search,
                      onTap: () => _goToSearchScreen(_searchController.text),
                      onSubmitted: (value) => _goToSearchScreen(value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleIconButton(icon: Icons.tune, onTap: _showLocalTools),
                  const SizedBox(width: 6),
                  CircleIconButton(
                    icon: Icons.my_location,
                    onTap: _goToMyLocation,
                  ),
                ],
              ),
            ),
          ),

          if (_savedCommutes.isNotEmpty)
            Positioned(
              top: 88,
              left: 16,
              right: 16,
              child: Card(
                elevation: 4,
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.route_outlined, size: 18),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Saved commutes',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Refresh saved commutes',
                            icon: const Icon(Icons.refresh, size: 18),
                            onPressed: _loadSavedCommutes,
                          ),
                        ],
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _savedCommutes.take(3).map((commute) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                avatar: const Icon(Icons.play_arrow, size: 16),
                                label: Text(commute.label),
                                onPressed: () => _openSavedCommute(commute),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: AskMapparaanBar(
                  controller: _bottomAskController,
                  hintText: 'Ask MapParaan',
                  onTap: () => _goToSearchScreen(_bottomAskController.text),
                  onLeadingTap: () =>
                      _goToSearchScreen(_bottomAskController.text),
                  onSubmitted: _handleAiQuery,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}