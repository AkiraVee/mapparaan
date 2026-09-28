import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../constants.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/ask_mapparaan_bar.dart';
import '../widgets/mapparaan_drawer.dart';
import 'search_location_screen.dart';

// [ADDED IMPORTS]
// Needed so this file understands what a PlaceResult object is.
import '../services/place_search_service.dart';
// Needed to render the custom widget we just created.
import '../widgets/location_details_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  MapLibreMapController? mapController;

  // [ADDED STATE VARIABLE]
  // Holds the data of the currently selected location. 
  // It is nullable (PlaceResult?) because when the app first opens, or if 
  // the user closes the bottom sheet, no location is actively selected (so it equals null).
  PlaceResult? _selectedPlace;



  // We added 'async' so we can pause execution and wait for the search screen to close.
  Future<void> _goToSearchScreen() async {
    // Await pauses here until search_location_screen calls Navigator.pop(context, place).
    // 'result' will contain whatever was passed back.
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const SearchLocationScreen()),
    );

    // Verify that a result was actually returned and it is of type PlaceResult.
    // (If the user presses the Android back button instead of selecting a place, result will be null).
    if (result != null && result is PlaceResult) {
      // setState tells Flutter to rebuild the HomeScreen UI. 
      // Because _selectedPlace is no longer null, the LocationDetailsSheet will now render.
      setState(() {
        _selectedPlace = result;
      });
      
      // Pan and zoom the map camera to the selected location's coordinates.
      if (mapController != null) {
        await mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(result.coordinates, 15.5),
        );
      }
    }
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
          const SnackBar(content: Text('Location permission permanently denied')),
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

      if (mapController != null) {
        await mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(userLatLng, 15.0),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
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
              MapLibreMap(
                initialCameraPosition: const CameraPosition(
                  target: LatLng(AppConstants.defaultLat, AppConstants.defaultLng),
                  zoom: AppConstants.defaultZoom,
                ),
                styleString: AppConstants.mapStyleUrl,
                onMapCreated: (controller) {
                  mapController = controller;
                },
                myLocationEnabled: true,
                compassEnabled: false,
                trackCameraPosition: true,
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
              // [MODIFIED LOGIC BEGINS HERE]
              // If NO place is selected (null), show the default AskMapparaan search bar at the bottom.
              if (_selectedPlace == null)
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

              // If a place IS selected (!= null), hide the bottom search bar and 
              // render our new LocationDetailsSheet at the bottom of the screen instead.
              if (_selectedPlace != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0, // Docks the sheet strictly to the bottom of the screen
                  child: LocationDetailsSheet(
                    // Extract data from the state variable to populate the sheet UI
                    title: _selectedPlace!.name,
                    address: _selectedPlace!.subtitle, 
                    
                    // The onClose callback fired when the 'X' button in the sheet is pressed.
                    onClose: () {
                      // Setting _selectedPlace back to null tells Flutter to rebuild.
                      // The UI will remove the sheet and bring back the AskMapparaan bar.
                      setState(() {
                        _selectedPlace = null;
                      });
                    },
                    onDirections: () {
                      // TODO: Add route calculation logic here later
                    },
                    onShare: () {
                      // TODO: Add share intents logic here later
                    },
                  ),
                ),
              // [MODIFIED LOGIC ENDS HERE]
            ],
          );
        },
      ),
    );
  }
}
