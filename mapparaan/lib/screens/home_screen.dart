import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../constants.dart';
import '../services/ai_assistant_service.dart';
import '../services/place_search_service.dart';
import '../services/route_planner_service.dart';
import '../services/saved_places_service.dart';
import '../widgets/ask_mapparaan_bar.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/location_details_sheet.dart';
import '../widgets/mapparaan_drawer.dart';
import '../widgets/mapparaan_tile_layer.dart';
// import 'drawer_destination_screen.dart';
import 'location_details_screen.dart';
import 'location_disabled_screen.dart';
import 'search_location_screen.dart';

/// Main landing home screen displaying interactive basemap and search controls.
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
  PlaceResult? _selectedPlace;
  List<PlaceResult> _searchResults = [];
  AiQueryResolution? _selectedResolution;
  bool _isSelectedPlaceSaved = false;

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

  /// Opens full search screen overlay and updates home screen when place is selected
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

    final place = selection.place;
    _searchController.text = place.name;

    setState(() {
      _selectedPlace = place;
      _selectedResolution = selection.resolution;
      _isSelectedPlaceSaved = false;
    });
    await _loadSelectedPlaceSavedState(place);
    if (!mounted) return;
    if (widget.showMap) _mapController.move(place.coordinates, 16.0);
  }

  /// Checks if selected place is stored in local saved places
  Future<void> _loadSelectedPlaceSavedState(PlaceResult place) async {
    try {
      final savedPlaces = await SavedPlacesService.load();
      if (!mounted || _selectedPlace?.coordinates != place.coordinates) return;
      final id = _savedPlaceId(place);
      setState(() {
        _isSelectedPlaceSaved = savedPlaces.any(
          (savedPlace) => savedPlace.id == id,
        );
      });
    } catch (error) {
      if (mounted) _showMessage('Could not load saved places: $error');
    }
  }

  String _savedPlaceId(PlaceResult place) =>
      '${place.coordinates.latitude}_${place.coordinates.longitude}';

  Future<void> _selectHomeSearchResult(PlaceResult place) async {
    _searchController.text = place.name;
    setState(() {
      _selectedPlace = place;
      _searchResults = const [];
      _selectedResolution = AiQueryResolution.fromQuery(place.name);
      _isSelectedPlaceSaved = false;
    });
    await _loadSelectedPlaceSavedState(place);
  }

  /// Handles AI query input from bottom prompt bar
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

      final place = results.first;
      _bottomAskController.clear();
      _searchController.text = place.name;

      setState(() {
        _selectedPlace = place;
        _searchResults = const [];
        _selectedResolution = AiQueryResolution.fromQuery(query);
        _isSelectedPlaceSaved = false;
      });
      await _loadSelectedPlaceSavedState(place);
      if (!mounted) return;
      if (widget.showMap) _mapController.move(place.coordinates, 16.0);
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

  /// Centers map view on current GPS coordinates
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

  Future<void> _saveSelectedPlace() async {
    final selectedPlace = _selectedPlace;
    if (selectedPlace == null) return;
    try {
      final added = await SavedPlacesService.toggle(
        SavedPlace(
          id: _savedPlaceId(selectedPlace),
          name: selectedPlace.name,
          subtitle: selectedPlace.subtitle,
          latitude: selectedPlace.coordinates.latitude,
          longitude: selectedPlace.coordinates.longitude,
        ),
      );
      if (!mounted || _selectedPlace?.coordinates != selectedPlace.coordinates) {
        return;
      }
      setState(() => _isSelectedPlaceSaved = added);
      _showMessage(added ? 'Saved place' : 'Removed from saved places');
    } catch (error) {
      if (mounted) _showMessage('Could not save place: $error');
    }
  }

  Future<void> _shareSelectedPlace() async {
    final place = _selectedPlace;
    if (place == null) return;
    try {
      await SharePlus.instance.share(
        ShareParams(text: '${place.name} — ${place.subtitle}'),
      );
    } catch (error) {
      if (mounted) _showMessage('Could not share place: $error');
    }
  }

  Future<void> _openSelectedRouteDetails() async {
    final place = _selectedPlace;
    if (place == null) return;
    final resolution = _selectedResolution;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocationDetailsScreen(
          place: place,
          origin: resolution?.origin ?? 'Current location',
          initialPreference: resolution?.preference ?? RoutePreference.fastest,
          passengerType: resolution?.passengerType ?? PassengerType.general,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const MapparaanDrawer(),
      body: Stack(
        children: [
          // FlutterMap rendering layer
          if (widget.showMap)
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(AppConstants.defaultLat, AppConstants.defaultLng),
                initialZoom: AppConstants.defaultZoom,
                minZoom: AppConstants.minZoom,
                maxZoom: AppConstants.maxZoom,
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
            )
          else
            const Positioned.fill(child: ColoredBox(color: Color(0xFFF2F5F4))),

          // Top Header Row (Menu, Search Bar, Location Button)
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

          // Search Auto-complete Overlay
          if (_searchResults.isNotEmpty)
            Positioned(
              top: 90,
              left: 16,
              right: 16,
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                elevation: 4,
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final place = _searchResults[index];
                    return ListTile(
                      title: Text(place.name),
                      subtitle: place.subtitle.isNotEmpty
                          ? Text(place.subtitle)
                          : null,
                      onTap: () => _selectHomeSearchResult(place),
                    );
                  },
                ),
              ),
            ),

          // Bottom Sheet or Bottom "Ask MapParaan" Bar
          Align(
            alignment: Alignment.bottomCenter,
            child: _selectedPlace != null
                ? LocationDetailsSheet(
                    title: _selectedPlace!.name,
                    address: _selectedPlace!.subtitle,
                    isSaved: _isSelectedPlaceSaved,
                    onClose: () => setState(() {
                      _selectedPlace = null;
                      _selectedResolution = null;
                      _isSelectedPlaceSaved = false;
                      _searchController.clear();
                    }),
                    onDirections: _openSelectedRouteDetails,
                    onSave: _saveSelectedPlace,
                    onShare: _shareSelectedPlace,
                  )
                : SafeArea(
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