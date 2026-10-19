import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../constants.dart';
import '../services/ai_assistant_service.dart';
import '../services/place_search_service.dart';
import '../services/route_planner_service.dart';
import '../services/saved_places_service.dart';
import '../services/trip_history_service.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/mapparaan_drawer.dart';
import '../widgets/mapparaan_tile_layer.dart';

/// The single, consistent "I picked a place" screen. Every place selection
/// in the app — plain search, an "Ask MapParaan" query, or tapping a saved
/// place from the drawer — ends up here, showing the same real map, the
/// same Save/Share actions, and the same route-preference cards, instead of
/// switching between this screen and the smaller bottom sheet depending on
/// how the place was picked.
class LocationDetailsScreen extends StatefulWidget {
  final PlaceResult? place;
  final String placeName;
  final LatLng? userLocation;
  final LatLng? destinationCoordinates;
  final String origin;
  final RoutePreference initialPreference;
  final PassengerType passengerType;

  const LocationDetailsScreen({
    super.key,
    this.place,
    this.placeName = 'Universidad De Manila',
    this.userLocation,
    this.destinationCoordinates,
    this.origin = 'Current location',
    this.initialPreference = RoutePreference.fastest,
    this.passengerType = PassengerType.general,
  });

  String get resolvedPlaceName => place?.name ?? placeName;
  String get resolvedSubtitle => place?.subtitle ?? origin;
  LatLng get resolvedDestination =>
      place?.coordinates ?? destinationCoordinates ?? const LatLng(14.5995, 120.9842);

  @override
  State<LocationDetailsScreen> createState() => _LocationDetailsScreenState();
}

class _LocationDetailsScreenState extends State<LocationDetailsScreen> {
  final MapController _mapController = MapController();

  bool _isSaved = false;
  bool _isLoadingRoute = false;
  bool _tripLogged = false;
  RoutePreference _selectedPreference = RoutePreference.fastest;
  List<RouteOption> _routeOptions = const [];
  List<LatLng> _routePoints = [];

  @override
  void initState() {
    super.initState();
    _selectedPreference = widget.initialPreference;
    _loadSavedState();
    _refreshRoute();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  String get _savedPlaceId {
    final destination = widget.resolvedDestination;
    return '${destination.latitude}_${destination.longitude}';
  }

  Future<void> _loadSavedState() async {
    try {
      final savedPlaces = await SavedPlacesService.load();
      if (!mounted) return;
      setState(() {
        _isSaved = savedPlaces.any((s) => s.id == _savedPlaceId);
      });
    } catch (_) {
      // Saved-state check failing shouldn't block showing the screen.
    }
  }

  /// Refreshes both the mocked multimodal route cards and the real
  /// walking-route polyline on the map, then records the lookup in Trip
  /// History — the same way a route lookup used to only get logged when it
  /// happened through the old bottom sheet's "Directions" button.
  Future<void> _refreshRoute() async {
    final destination = widget.resolvedDestination;
    final userLocation = widget.userLocation ?? const LatLng(14.5943, 120.9721);

    setState(() {
      _routeOptions = RoutePlannerService.generateRouteOptions(
        destination: destination,
        userLocation: userLocation,
        preference: _selectedPreference,
      );
      _isLoadingRoute = true;
    });

    final geometry = await RoutePlannerService.fetchRoute(
      origin: userLocation,
      destination: destination,
      profile: 'foot',
    );

    if (!mounted) return;

    if (geometry == null || geometry.points.isEmpty) {
      setState(() => _isLoadingRoute = false);
      return;
    }

    setState(() {
      _routePoints = geometry.points;
      _isLoadingRoute = false;
    });

    final bounds = LatLngBounds.fromPoints(geometry.points);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.fromLTRB(40, 120, 40, 280),
      ),
    );

    final mins = (geometry.durationSeconds / 60).round();
    final km = (geometry.distanceMeters / 1000).toStringAsFixed(1);
    final topOption = _routeOptions.isNotEmpty ? _routeOptions.first : null;

    // Log once per visit to this screen, so tapping through the preference
    // buttons doesn't pile up duplicate entries for the same trip.
    if (_tripLogged) return;
    _tripLogged = true;
    await TripHistoryService.addEntry(
      TripHistoryEntry(
        origin: widget.userLocation != null ? 'Your location' : 'Default location',
        destination: widget.resolvedPlaceName,
        preference: _selectedPreference,
        durationMinutes: mins,
        // Fare stays a placeholder (0) until real fare data from the
        // Sakay.ph GTFS repo is wired in.
        routeSummary: topOption != null
            ? '${topOption.modeLabel} • $km km'
            : 'Walking • $km km',
      ),
    );
  }

  void _selectPreference(RoutePreference preference) {
    if (preference == _selectedPreference) return;
    setState(() => _selectedPreference = preference);
    _refreshRoute();
  }

  Future<void> _handleSaveToggle() async {
    try {
      final destination = widget.resolvedDestination;
      final added = await SavedPlacesService.toggle(
        SavedPlace(
          id: _savedPlaceId,
          name: widget.resolvedPlaceName,
          subtitle: widget.resolvedSubtitle,
          latitude: destination.latitude,
          longitude: destination.longitude,
        ),
      );
      if (!mounted) return;
      setState(() => _isSaved = added);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(added ? 'Saved place' : 'Removed from saved places')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save place: $error')),
        );
      }
    }
  }

  Future<void> _handleShare() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: '${widget.resolvedPlaceName} — ${widget.resolvedSubtitle}',
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share place: $error')),
        );
      }
    }
  }

  void _centerOnMyLocation() {
    final location = widget.userLocation;
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Location isn't available. Enable it from the home screen."),
        ),
      );
      return;
    }
    _mapController.move(location, 15.0);
  }

  @override
  Widget build(BuildContext context) {
    final destination = widget.resolvedDestination;

    return Scaffold(
      drawer: MapparaanDrawer(
        onPlaceSelected: (selected) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => LocationDetailsScreen(
                place: selected,
                userLocation: widget.userLocation,
              ),
            ),
          );
        },
      ),
      body: Builder(
        builder: (context) {
          return Stack(
            children: [
              // ===== REAL MAP (same tiles/markers/route styling as the rest
              // of the app, instead of a static "Map goes here" box) =====
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: widget.userLocation ?? destination,
                  initialZoom: AppConstants.defaultZoom,
                  minZoom: AppConstants.minZoom,
                  maxZoom: AppConstants.maxZoom,
                  cameraConstraint: CameraConstraint.contain(
                    bounds: AppConstants.manilaBounds,
                  ),
                ),
                children: [
                  const MapparaanTileLayer(),
                  if (_routePoints.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _routePoints,
                          color: const Color(0xFF00695C),
                          strokeWidth: 5,
                          borderStrokeWidth: 2,
                          borderColor: Colors.white,
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      if (widget.userLocation != null)
                        Marker(
                          point: widget.userLocation!,
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
                                  border: Border.all(color: Colors.white, width: 2.5),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Marker(
                        point: destination,
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
              ),

              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CircleIconButton(
                        icon: Icons.menu,
                        onTap: () => Scaffold.of(context).openDrawer(),
                      ),
                      CircleIconButton(
                        icon: Icons.my_location,
                        onTap: _centerOnMyLocation,
                      ),
                    ],
                  ),
                ),
              ),

              if (_isLoadingRoute)
                const Positioned(
                  top: 100,
                  left: 0,
                  right: 0,
                  child: Center(child: CircularProgressIndicator()),
                ),

              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  top: false,
                  child: _PlaceDetailsSheet(
                    placeName: widget.resolvedPlaceName,
                    isSaved: _isSaved,
                    selectedPreference: _selectedPreference,
                    routeOptions: _routeOptions,
                    onSaveToggle: _handleSaveToggle,
                    onShare: _handleShare,
                    onClose: () => Navigator.of(context).pop(),
                    onPreferenceSelected: _selectPreference,
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

class _PlaceDetailsSheet extends StatelessWidget {
  final String placeName;
  final bool isSaved;
  final RoutePreference selectedPreference;
  final List<RouteOption> routeOptions;
  final VoidCallback onSaveToggle;
  final VoidCallback onShare;
  final VoidCallback onClose;
  final ValueChanged<RoutePreference> onPreferenceSelected;

  const _PlaceDetailsSheet({
    required this.placeName,
    required this.isSaved,
    required this.selectedPreference,
    required this.routeOptions,
    required this.onSaveToggle,
    required this.onShare,
    required this.onClose,
    required this.onPreferenceSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  placeName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  isSaved ? Icons.bookmark : Icons.bookmark_border,
                  color: Colors.black87,
                ),
                onPressed: onSaveToggle,
              ),
              IconButton(
                icon: const Icon(Icons.share, color: Colors.black87),
                onPressed: onShare,
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.black87),
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _PreferenceButton(
                label: 'Fastest',
                active: selectedPreference == RoutePreference.fastest,
                accent: const Color(0xFF00695C),
                onPressed: () => onPreferenceSelected(RoutePreference.fastest),
              ),
              const SizedBox(width: 8),
              _PreferenceButton(
                label: 'Cheapest',
                active: selectedPreference == RoutePreference.cheapest,
                accent: const Color(0xFFB2EBF2),
                onPressed: () => onPreferenceSelected(RoutePreference.cheapest),
              ),
              const SizedBox(width: 8),
              _PreferenceButton(
                label: 'Fewest\nTransfers',
                active: selectedPreference == RoutePreference.fewestTransfers,
                accent: const Color(0xFFE0F7FA),
                onPressed: () =>
                    onPreferenceSelected(RoutePreference.fewestTransfers),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...routeOptions.map(
            (route) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RouteResultCard(route: route),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferenceButton extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onPressed;

  const _PreferenceButton({
    required this.label,
    required this.active,
    required this.accent,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = active ? Colors.white : Colors.black87;
    final background = active ? accent : const Color(0xFFEAF1F1);

    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}

class _RouteResultCard extends StatelessWidget {
  final RouteOption route;

  const _RouteResultCard({required this.route});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFD7F3F1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              route.transfers == 0 ? Icons.directions_car : Icons.directions_bus,
              color: const Color(0xFF00695C),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  route.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${route.modeLabel} • ${route.etaMinutes} min • ${route.transfers} transfer${route.transfers == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  route.summary,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '₱${route.fare}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF00695C),
              ),
            ),
          ),
        ],
      ),
    );
  }
}