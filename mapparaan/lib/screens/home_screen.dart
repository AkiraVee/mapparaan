import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../services/place_search_service.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/ask_mapparaan_bar.dart';
import '../widgets/location_details_sheet.dart';
import '../widgets/mapparaan_drawer.dart';
import 'search_location_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();
  Marker? _selectedMarker;
  LatLng? _userLocation;

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _goToSearchScreen() async {
    // Push the search screen and wait for it to pop back with the place the
    // user tapped (or null if they backed out without picking anything).
    final selectedPlace = await Navigator.of(context).push<PlaceResult>(
      MaterialPageRoute(builder: (context) => const SearchLocationScreen()),
    );

    if (selectedPlace != null && mounted) {
      await _onLocationSelected(selectedPlace);
    }
  }

  Future<void> _onLocationSelected(PlaceResult place) async {
    _searchController.text = place.name;

    // 1. Move the map camera to the selected coordinates.
    _mapController.move(place.coordinates, 15.5);

    setState(() {
      _selectedMarker = Marker(
        point: place.coordinates,
        width: 140,
        height: 60,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, color: Colors.red, size: 36),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                place.name,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    });

    if (!mounted) return;

    // 2. Show the location details as a modal bottom sheet over the map.
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => LocationDetailsSheet(
        title: place.name,
        address: place.subtitle,
        onClose: () => Navigator.of(sheetContext).pop(),
        onDirections: () {
          // TODO: wire up turn-by-turn directions.
        },
        onSave: () {
          // TODO: persist this place to the user's saved locations.
        },
        onShare: () {
          // TODO: share the place (e.g. via share_plus).
        },
      ),
    ).whenComplete(() {
      // Clean up the marker once the sheet is dismissed.
      if (mounted) {
        setState(() {
          _selectedMarker = null;
        });
      }
    });
  }

  Future<void> _goToMyLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return;
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable location services')),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (!mounted) return;
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied')),
          );
          return;
        }
      }

      if (!mounted) return;
      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission permanently denied'),
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;

      final userLatLng = LatLng(position.latitude, position.longitude);
      setState(() {
        _userLocation = userLatLng;
      });
      _mapController.move(userLatLng, 15.0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error getting location: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const MapparaanDrawer(),
      body: Builder(
        builder: (context) {
          return Stack(
            children: [
              // ===== MAP =====
              FlutterMap(
                mapController: _mapController,
                options: const MapOptions(
                  initialCenter: LatLng(
                    AppConstants.defaultLat,
                    AppConstants.defaultLng,
                  ),
                  initialZoom: AppConstants.defaultZoom,
                ),
                children: [
                  TileLayer(
                    urlTemplate: AppConstants.mapTileUrl,
                    userAgentPackageName: AppConstants.appPackageName,
                  ),
                  MarkerLayer(
                    markers: [
                      if (_userLocation != null)
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
                      ?_selectedMarker,
                    ],
                  ),
                ],
              ),

              // ===== TOP BAR =====
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      CircleIconButton(
                        icon: Icons.menu,
                        onTap: () => Scaffold.of(context).openDrawer(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: _goToSearchScreen,
                          child: AbsorbPointer(
                            child: AskMapparaanBar(
                              controller: _searchController,
                              hintText: 'Search here',
                              leadingIcon: Icons.search,
                            ),
                          ),
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

              // ===== BOTTOM BAR =====
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: SafeArea(
                  child: GestureDetector(
                    onTap: _goToSearchScreen,
                    child: AbsorbPointer(
                      child: AskMapparaanBar(controller: _searchController),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
