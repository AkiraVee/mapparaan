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

  // Automatically fetches live location on startup or prompts the user if disabled.
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
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;

      final userLatLng = LatLng(position.latitude, position.longitude);
      setState(() => _userLocation = userLatLng);
      _mapController.move(userLatLng, 15.0);
    } catch (e) {
      if (mounted) debugPrint('Auto-location error: $e');
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
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;

      final userLatLng = LatLng(position.latitude, position.longitude);
      setState(() => _userLocation = userLatLng);
      _mapController.move(userLatLng, 15.0);
    } catch (e) {
      if (mounted) _showMessage('Error getting location: $e');
    }
  }

  /// Displays popup dialog when a purple memory pin on the map is tapped
  void _showMemoryPinDialog(MemoryPin pin) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            pin.placeName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.image, size: 50, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                pin.address,
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: Colors.black54)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00695C),
                foregroundColor: Colors.white,
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
                    name: pin.placeName,
                    subtitle: pin.address,
                    coordinates: pin.coordinates,
                  ),
                );
              },
            ),
          ],
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
          // ===== MAP WITH MEMORY PINS =====
          if (widget.showMap)
            ValueListenableBuilder<List<MemoryPin>>(
              valueListenable: MemoryPinService.pins,
              builder: (context, memoryPins, _) {
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
                    if (memoryPins.isNotEmpty)
                      MarkerLayer(
                        markers: memoryPins.map((pin) {
                          return Marker(
                            point: pin.coordinates,
                            width: 50,
                            height: 50,
                            alignment: Alignment.topCenter,
                            child: GestureDetector(
                              onTap: () => _showMemoryPinDialog(pin),
                              child: const Icon(
                                Icons.photo_camera_front,
                                size: 40,
                                color: Colors.purple,
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
            const Positioned.fill(child: ColoredBox(color: Color(0xFFF2F5F4))),

          // ===== TOP BAR =====
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

          // ===== ASK BAR =====
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