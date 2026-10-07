import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../services/place_search_service.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/ask_mapparaan_bar.dart';
import '../widgets/mapparaan_drawer.dart';

class SearchLocationScreen extends StatefulWidget {
  const SearchLocationScreen({super.key});

  @override
  State<SearchLocationScreen> createState() => _SearchLocationScreenState();
}

class _SearchLocationScreenState extends State<SearchLocationScreen> {
  final TextEditingController _topSearchController = TextEditingController();
  final TextEditingController _bottomAskController = TextEditingController();
  final FocusNode _topSearchFocusNode = FocusNode();
  final MapController _mapController = MapController();

  bool _isSearchFocused = false;
  bool _hasConnectionError = false;
  bool _isSearching = false;

  LatLng? _userLocation;
  List<PlaceResult> _searchResults = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _topSearchFocusNode.addListener(() {
      setState(() => _isSearchFocused = _topSearchFocusNode.hasFocus);
    });
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition();
      final userLatLng = LatLng(position.latitude, position.longitude);
      setState(() {
        _userLocation = userLatLng;
      });

      _mapController.move(userLatLng, 14.0);
    } catch (e) {
      // geolocator_web has a known bug throwing here on some browsers —
      // safe to ignore, the app just won't auto-center on your location.
      debugPrint('Location fetch failed: $e');
    }
  }

  void _goToMyLocation() {
    if (_userLocation != null) {
      _mapController.move(_userLocation!, 15.0);
    } else {
      _getCurrentLocation();
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 700), () async {
      if (query.trim().length < 3) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
        return;
      }

      setState(() => _isSearching = true);

      final results = await PlaceSearchService.search(query);

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
          _hasConnectionError = false;
        });
      }
    });
  }

  void _selectPlace(PlaceResult place) {
    _topSearchFocusNode.unfocus();

    // Hand the selected place straight back to HomeScreen. HomeScreen owns
    // the persistent map instance, so it's the one that should animate the
    // camera and draw the marker/bottom sheet — this screen is about to be
    // popped off the stack entirely.
    Navigator.of(context).pop(place);
  }

  void _retry() {
    setState(() => _hasConnectionError = false);
    _onSearchChanged(_topSearchController.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _topSearchController.dispose();
    _bottomAskController.dispose();
    _topSearchFocusNode.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showDropdownArea = _isSearchFocused;

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
                  initialCenter: _userLocation ??
                      const LatLng(
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
                ],
              ),

              // Top bar + results
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          CircleIconButton(
                            icon: _isSearchFocused
                                ? Icons.arrow_back
                                : Icons.menu,
                            onTap: () {
                              if (_isSearchFocused) {
                                _topSearchFocusNode.unfocus();
                              } else {
                                Scaffold.of(context).openDrawer();
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: AskMapparaanBar(
                              controller: _topSearchController,
                              focusNode: _topSearchFocusNode,
                              hintText: 'Search here',
                              leadingIcon: Icons.search,
                              onChanged: _onSearchChanged,
                              onSubmitted: _onSearchChanged,
                            ),
                          ),
                          if (!_isSearchFocused) ...[
                            const SizedBox(width: 8),
                            CircleIconButton(
                              icon: Icons.my_location,
                              onTap: _goToMyLocation,
                            ),
                          ],
                        ],
                      ),

                      if (showDropdownArea) ...[
                        const SizedBox(height: 8),
                        Expanded(
                          child: _hasConnectionError
                              ? _NoConnectionState(onRetry: _retry)
                              : _isSearching
                              ? const Center(child: CircularProgressIndicator())
                              : _searchResults.isEmpty
                              ? const Center(
                                  child: Text(
                                    "Type at least 3 characters",
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                )
                              : _SearchDropdown(
                                  results: _searchResults,
                                  onSelect: _selectPlace,
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Bottom bar
              if (!showDropdownArea)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: AskMapparaanBar(controller: _bottomAskController),
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

class _SearchDropdown extends StatelessWidget {
  final List<PlaceResult> results;
  final ValueChanged<PlaceResult> onSelect;

  const _SearchDropdown({required this.results, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: results.length,
        separatorBuilder: (context, index) =>
            const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, index) {
          final place = results[index];
          return ListTile(
            leading: const Icon(Icons.place_outlined, color: Colors.black54),
            title: Text(
              place.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15),
            ),
            subtitle: Text(
              place.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            onTap: () => onSelect(place),
          );
        },
      ),
    );
  }
}

class _NoConnectionState extends StatelessWidget {
  final VoidCallback onRetry;
  const _NoConnectionState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 40, color: Colors.black45),
            const SizedBox(height: 16),
            const Text(
              "Couldn't load results",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check your connection. Your search is still here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00695C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
