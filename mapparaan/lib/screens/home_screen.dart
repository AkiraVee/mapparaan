import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../services/place_search_service.dart';
import '../widgets/ask_mapparaan_bar.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/location_details_sheet.dart';
import '../widgets/mapparaan_drawer.dart';
import '../widgets/mapparaan_tile_layer.dart';
import 'search_location_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();

  LatLng? _userLocation;
  PlaceResult? _selectedPlace;

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Opens the search screen and, if the user picks a place, drops a pin on
  /// this screen's map and shows the details sheet.
  Future<void> _goToSearchScreen() async {
    final place = await Navigator.of(context).push<PlaceResult>(
      MaterialPageRoute(builder: (context) => const SearchLocationScreen()),
    );
    if (!mounted || place == null) return;

    setState(() => _selectedPlace = place);
    _mapController.move(place.coordinates, 16.0);
  }

  Future<void> _goToMyLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return;
      if (!serviceEnabled) {
        _showMessage('Please enable location services');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (!mounted) return;
        if (permission == LocationPermission.denied) {
          _showMessage('Location permission denied');
          return;
        }
      }

      if (!mounted) return;
      if (permission == LocationPermission.deniedForever) {
        _showMessage('Location permission permanently denied');
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
                options: MapOptions(
                  initialCenter: const LatLng(
                    AppConstants.defaultLat,
                    AppConstants.defaultLng,
                  ),
                  initialZoom: AppConstants.defaultZoom,
                  minZoom: AppConstants.minZoom,
                  maxZoom: AppConstants.maxZoom,
                  // Manila only: can't pan outside the bounds.
                  cameraConstraint: CameraConstraint.contain(
                    bounds: AppConstants.manilaBounds,
                  ),
                ),
                children: [
                  const MapparaanTileLayer(),
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
                      if (_selectedPlace != null)
                        Marker(
                          point: _selectedPlace!.coordinates,
                          width: 40,
                          height: 40,
                          // Anchor the pin's tip on the coordinate.
                          alignment: Alignment.topCenter,
                          child: const Icon(
                            Icons.location_on,
                            size: 40,
                            color: Color(0xFFD32F2F),
                          ),
                        ),
                    ],
                  ),
                ],
              ),

              // ===== TOP BAR =====
              SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

              // ===== BOTTOM: details sheet or Ask bar =====
              Align(
                alignment: Alignment.bottomCenter,
                child: _selectedPlace != null
                    ? LocationDetailsSheet(
                        title: _selectedPlace!.name,
                        address: _selectedPlace!.subtitle,
                        onClose: () => setState(() => _selectedPlace = null),
                        // TODO: hook up routing, saved places, and sharing.
                      )
                    : SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: GestureDetector(
                            onTap: _goToSearchScreen,
                            child: AbsorbPointer(
                              child: AskMapparaanBar(
                                controller: _searchController,
                              ),
                            ),
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