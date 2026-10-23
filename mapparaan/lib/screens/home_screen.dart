import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../services/ai_assistant_service.dart';
import '../services/memory_pin_service.dart';
import '../services/place_search_service.dart';
import '../services/route_planner_service.dart';
import '../widgets/ask_mapparaan_bar.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/mapparaan_drawer.dart';
import '../widgets/mapparaan_tile_layer.dart';
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

  @override
  void initState() {
    super.initState();
    _initUserLocation();
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
          initialPreference: preference ?? RoutePreference.fastest,
          passengerType: passengerType ?? PassengerType.general,
        ),
      ),
    );

    if (!mounted) return;
    _searchController.clear();
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
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
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
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (album.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                          onPageChanged: (index) => setState(() => currentIndex = index),
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
                                        loadingBuilder: (context, child, progress) {
                                          if (progress == null) return child;
                                          return const Center(child: CircularProgressIndicator());
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
                                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                                    onPressed: () {
                                      pageController.previousPage(
                                        duration: const Duration(milliseconds: 300),
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
                                    icon: const Icon(Icons.chevron_right, color: Colors.white),
                                    onPressed: () {
                                      pageController.nextPage(
                                        duration: const Duration(milliseconds: 300),
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
                        Icon(Icons.location_on_outlined, size: 18, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            currentPin.address,
                            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
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
                  child: Text('Close', style: TextStyle(color: colorScheme.onSurfaceVariant)),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                
                final albumsMap = <String, List<MemoryPin>>{};
                for (final pin in memoryPins) {
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
                    
                    if (albums.isNotEmpty)
                      MarkerLayer(
                        markers: albums.map((album) {
                          final latestPin = album.last; 
                          return Marker(
                            point: latestPin.coordinates,
                            width: 52,
                            height: 60,
                            alignment: Alignment.bottomCenter,
                            child: GestureDetector(
                              onTap: () => _showMemoryAlbumDialog(album),
                              child: Stack(
                                alignment: Alignment.topCenter,
                                children: [
                                  Icon(
                                    Icons.location_on,
                                    size: 52,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  Positioned(
                                    top: 5,
                                    child: Container(
                                      width: 25,
                                      height: 25,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.surface,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Theme.of(context).colorScheme.surface,
                                          width: 2,
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: latestPin.imageUrl.isEmpty
                                          ? Icon(
                                              Icons.photo,
                                              size: 16,
                                              color: Theme.of(context).colorScheme.primary,
                                            )
                                          : Image.network(
                                              latestPin.imageUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) => Icon(
                                                Icons.photo,
                                                size: 16,
                                                color: Theme.of(context).colorScheme.primary,
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                );
              },
            )
          else
            Positioned.fill(
              child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
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
                  CircleIconButton(
                    icon: Icons.my_location,
                    onTap: _goToMyLocation,
                  ),
                ],
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
                  onLeadingTap: () => _goToSearchScreen(_bottomAskController.text),
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