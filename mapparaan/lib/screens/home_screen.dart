import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/ask_mapparaan_bar.dart';
import '../widgets/mapparaan_drawer.dart';
import 'search_location_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  MapLibreMapController? mapController;

  void _goToSearchScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const SearchLocationScreen()),
    );
  }

  Future<void> _goToMyLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable location services')),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied')),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission permanently denied')),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final userLatLng = LatLng(position.latitude, position.longitude);

      if (mapController != null) {
        await mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(userLatLng, 15.0),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting location: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const MapparaanDrawer(),
      body: Stack(
        children: [
          // ===== MAP =====
          MapLibreMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(14.5995, 120.9842),
              zoom: 12.0,
            ),
            styleString: "https://demotiles.maplibre.org/style.json",
            onMapCreated: (controller) {
              mapController = controller;
            },
            myLocationEnabled: true,          // keeps the blue dot only
            compassEnabled: false,
            trackCameraPosition: true,
            // These help hide any remaining default buttons
            myLocationTrackingMode: MyLocationTrackingMode.none,
          ),

          // ===== TOP BAR =====
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    onTap: _goToMyLocation,   // ← only this button has the function
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
      ),
    );
  }
}
