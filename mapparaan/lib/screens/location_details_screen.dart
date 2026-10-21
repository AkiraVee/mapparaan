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
import '../services/transit_planner_service.dart';
import '../services/trip_history_service.dart';
import 'auth_screen.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/mapparaan_drawer.dart';
import '../widgets/mapparaan_tile_layer.dart';
import '../services/auth_service.dart';

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
      place?.coordinates ??
      destinationCoordinates ??
      const LatLng(14.5995, 120.9842);

  @override
  State<LocationDetailsScreen> createState() => _LocationDetailsScreenState();
}

class _LocationDetailsScreenState extends State<LocationDetailsScreen> {
  final MapController _mapController = MapController();

  bool _isSaved = false;
  bool _isLoadingRoute = false;
  bool _tripLogged = false;
  bool _isOfflineFallback = false;

  late RoutePreference _selectedPreference;
  late PassengerType _passengerType;

  List<TransitPlanOption> _routeOptions = const [];
  TransitPlanOption? _selectedOption;
  List<LatLng> _routePoints = [];

  @override
  void initState() {
    super.initState();
    _selectedPreference = widget.initialPreference;
    _passengerType = widget.passengerType;
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
    } catch (_) {}
  }

  Future<void> _refreshRoute() async {
    final destination = widget.resolvedDestination;
    LatLng? origin = widget.userLocation;

    if (origin == null) {
      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          );
          origin = LatLng(position.latitude, position.longitude);
        }
      } catch (_) {}
    }

    if (origin == null) {
      setState(() => _isLoadingRoute = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location is disabled. Enable location services to calculate your route.',
            ),
          ),
        );
      }
      return;
    }

    setState(() => _isLoadingRoute = true);

    final realPlans = await TransitPlannerService.planTransit(
      origin: origin,
      destination: destination,
      passengerType: _passengerType,
    );

    if (!mounted) return;

    if (realPlans != null && realPlans.isNotEmpty) {
      final matching = realPlans.where(
        (o) => o.routePreference == _selectedPreference,
      );
      final selected = matching.isNotEmpty ? matching.first : realPlans.first;
      final points = selected.allPoints;

      setState(() {
        _isOfflineFallback = false;
        _routeOptions = realPlans;
        _selectedOption = selected;
        _routePoints = points;
        _isLoadingRoute = false;
      });

      _fitCameraToBounds(points);
    } else {
      final geometry = await RoutePlannerService.fetchRoute(
        origin: origin,
        destination: destination,
        profile: 'foot',
      );

      if (!mounted) return;

      final fallbackPoints = (geometry != null && geometry.points.isNotEmpty)
          ? geometry.points
          : [origin, destination];

      final fallbackOptions = TransitPlannerService.getFallbackOptions(
        destination: destination,
        userLocation: origin,
        preference: _selectedPreference,
        passengerType: _passengerType,
        fallbackPath: fallbackPoints,
      );

      final selected = fallbackOptions.isNotEmpty
          ? fallbackOptions.first
          : null;

      setState(() {
        _isOfflineFallback = true;
        _routeOptions = fallbackOptions;
        _selectedOption = selected;
        _routePoints = fallbackPoints;
        _isLoadingRoute = false;
      });

      _fitCameraToBounds(fallbackPoints);
    }

    if (!_tripLogged && _routeOptions.isNotEmpty) {
      _tripLogged = true;
      final topOption = _selectedOption ?? _routeOptions.first;
      await TripHistoryService.addEntry(
        TripHistoryEntry(
          origin: widget.userLocation != null
              ? 'Your location'
              : 'Default location',
          destination: widget.resolvedPlaceName,
          preference: _selectedPreference.name,
          durationMinutes: topOption.etaMinutes,
          fareEstimate: topOption.effectiveFare(_passengerType).toDouble(),
          routeSummary: topOption.summary.isNotEmpty
              ? topOption.summary
              : '${topOption.title} (₱${topOption.effectiveFare(_passengerType)})',
        ),
      );
    }
  }

  void _fitCameraToBounds(List<LatLng> points) {
    if (points.length < 2) return;
    try {
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(40, 100, 40, 360),
        ),
      );
    } catch (_) {}
  }

  void _selectPreference(RoutePreference preference) {
    if (preference == _selectedPreference) return;
    setState(() => _selectedPreference = preference);

    final matching = _routeOptions.where(
      (o) => o.routePreference == preference,
    );
    if (matching.isNotEmpty) {
      _selectOption(matching.first);
    } else {
      _refreshRoute();
    }
  }

  void _selectPassengerType(PassengerType type) {
    if (type == _passengerType) return;
    setState(() => _passengerType = type);
    _refreshRoute();
  }

  void _selectOption(TransitPlanOption option) {
    setState(() {
      _selectedOption = option;
      _selectedPreference = option.routePreference;
      _routePoints = option.allPoints;
    });

    if (_routePoints.length >= 2) {
      _fitCameraToBounds(_routePoints);
    }
  }

  Future<void> _handleSaveToggle() async {
    if (!AuthService.isLoggedIn.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Sign in to save places to your account.'),
          action: SnackBarAction(
            label: 'Sign In',
            onPressed: () {
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const AuthScreen()));
            },
          ),
        ),
      );
      return;
    }

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
        SnackBar(
          content: Text(added ? 'Saved place' : 'Removed from saved places'),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save place: $error')));
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
          content: Text(
            "Location isn't available. Enable location from settings.",
          ),
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
                passengerType: _passengerType,
              ),
            ),
          );
        },
      ),
      body: Builder(
        builder: (context) {
          return Stack(
            children: [
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
                  if (_selectedOption != null &&
                      _selectedOption!.legs.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        for (final leg in _selectedOption!.legs)
                          if (leg.path.length >= 2)
                            Polyline(
                              points: leg.path,
                              color: leg.color,
                              strokeWidth: leg.isWalk ? 4.5 : 6.0,
                              borderStrokeWidth: leg.isWalk ? 0.0 : 2.0,
                              borderColor: Colors.white,
                            ),
                      ],
                    )
                  else if (_routePoints.length >= 2)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _routePoints,
                          color: Theme.of(context).colorScheme.primary,
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
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2.5,
                                  ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
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
                  top: 90,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Card(
                      elevation: 4,
                      shape: StadiumBorder(),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Finding best transit routes...',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              _PlaceDetailsSheet(
                placeName: widget.resolvedPlaceName,
                address: widget.resolvedSubtitle,
                coordinates: widget.resolvedDestination,
                isSaved: _isSaved,
                isOfflineFallback: _isOfflineFallback,
                selectedPreference: _selectedPreference,
                passengerType: _passengerType,
                routeOptions: _routeOptions,
                selectedOption: _selectedOption,
                onSaveToggle: _handleSaveToggle,
                onShare: _handleShare,
                onClose: () => Navigator.of(context).pop(),
                onPreferenceSelected: _selectPreference,
                onPassengerTypeSelected: _selectPassengerType,
                onOptionSelected: _selectOption,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Custom sliding panel (whole tab moves) ───────────────────────────────────

class _PlaceDetailsSheet extends StatefulWidget {
  final String placeName;
  final String address;
  final LatLng coordinates;
  final bool isSaved;
  final bool isOfflineFallback;
  final RoutePreference selectedPreference;
  final PassengerType passengerType;
  final List<TransitPlanOption> routeOptions;
  final TransitPlanOption? selectedOption;
  final VoidCallback onSaveToggle;
  final VoidCallback onShare;
  final VoidCallback onClose;
  final ValueChanged<RoutePreference> onPreferenceSelected;
  final ValueChanged<PassengerType> onPassengerTypeSelected;
  final ValueChanged<TransitPlanOption> onOptionSelected;

  const _PlaceDetailsSheet({
    required this.placeName,
    required this.address,
    required this.coordinates,
    required this.isSaved,
    required this.isOfflineFallback,
    required this.selectedPreference,
    required this.passengerType,
    required this.routeOptions,
    required this.selectedOption,
    required this.onSaveToggle,
    required this.onShare,
    required this.onClose,
    required this.onPreferenceSelected,
    required this.onPassengerTypeSelected,
    required this.onOptionSelected,
  });

  @override
  State<_PlaceDetailsSheet> createState() => _PlaceDetailsSheetState();
}

class _PlaceDetailsSheetState extends State<_PlaceDetailsSheet> {
  double _heightFactor = 0.42;

  static const double _minFactor = 0.30;
  static const double _maxFactor = 0.90;

  void _onDragUpdate(DragUpdateDetails details) {
    final screenHeight = MediaQuery.of(context).size.height;
    setState(() {
      _heightFactor -= details.primaryDelta! / screenHeight;
      _heightFactor = _heightFactor.clamp(_minFactor, _maxFactor);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    const targets = [0.30, 0.42, 0.65, 0.90];
    var closest = targets.first;
    var minDist = (_heightFactor - closest).abs();
    for (final t in targets) {
      final d = (_heightFactor - t).abs();
      if (d < minDist) {
        minDist = d;
        closest = t;
      }
    }
    setState(() => _heightFactor = closest);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    final screenHeight = MediaQuery.of(context).size.height;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: screenHeight * _heightFactor,
      child: Material(
        color: colorScheme.surface,
        elevation: 12,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Drag handle + title → moves WHOLE sheet
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: _onDragUpdate,
              onVerticalDragEnd: _onDragEnd,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.placeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            widget.isSaved
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            color: widget.isSaved
                                ? primary
                                : colorScheme.onSurface,
                          ),
                          onPressed: widget.onSaveToggle,
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.share, color: colorScheme.onSurface),
                          onPressed: widget.onShare,
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.close, color: colorScheme.onSurface),
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content scrolls independently
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: AuthService.isLoggedIn,
                    builder: (context, isLoggedIn, _) {
                      if (!isLoggedIn) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.camera_alt, size: 18),
                          label: const Text('Add Memory Photo'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primary,
                            side: BorderSide(color: primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Memory photo upload is not available yet.',
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),

                  _PassengerTypeSelector(
                    selectedType: widget.passengerType,
                    onSelected: widget.onPassengerTypeSelected,
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      _PreferenceButton(
                        label: 'Fastest',
                        active:
                            widget.selectedPreference ==
                            RoutePreference.fastest,
                        accent: primary,
                        onPressed: () => widget.onPreferenceSelected(
                          RoutePreference.fastest,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _PreferenceButton(
                        label: 'Cheapest',
                        active:
                            widget.selectedPreference ==
                            RoutePreference.cheapest,
                        accent: primary,
                        onPressed: () => widget.onPreferenceSelected(
                          RoutePreference.cheapest,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _PreferenceButton(
                        label: 'Fewest\nTransfers',
                        active:
                            widget.selectedPreference ==
                            RoutePreference.fewestTransfers,
                        accent: primary,
                        onPressed: () => widget.onPreferenceSelected(
                          RoutePreference.fewestTransfers,
                        ),
                      ),
                    ],
                  ),

                  if (widget.isOfflineFallback)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFE0B2)),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: Color(0xFFE65100),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'API offline: showing mock estimates. Start backend/planner/api.py for real routes.',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFFBF360C),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 12),

                  ...widget.routeOptions.map((route) {
                    final isSelected =
                        widget.selectedOption == route ||
                        (widget.selectedOption == null &&
                            route == widget.routeOptions.first);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _RouteResultCard(
                        route: route,
                        isSelected: isSelected,
                        passengerType: widget.passengerType,
                        onTap: () => widget.onOptionSelected(route),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Passenger type ───────────────────────────────────────────────────────────

class _PassengerTypeSelector extends StatelessWidget {
  final PassengerType selectedType;
  final ValueChanged<PassengerType> onSelected;

  const _PassengerTypeSelector({
    required this.selectedType,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: PassengerType.values.map((type) {
          final isSelected = type == selectedType;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? colorScheme.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isSelected
                      ? const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      type.label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected ? primary : colorScheme.onSurface,
                      ),
                    ),
                    if (type.isDiscounted)
                      Text(
                        '20% off',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? primary
                              : primary.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Preference buttons ───────────────────────────────────────────────────────

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
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = active ? colorScheme.onPrimary : colorScheme.onSurface;
    final background = active ? accent : colorScheme.surfaceContainerHighest;

    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: active ? 2 : 0,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ─── Route card ───────────────────────────────────────────────────────────────

class _RouteResultCard extends StatelessWidget {
  final TransitPlanOption route;
  final bool isSelected;
  final PassengerType passengerType;
  final VoidCallback onTap;

  const _RouteResultCard({
    required this.route,
    required this.isSelected,
    required this.passengerType,
    required this.onTap,
  });

  IconData _getLeadingIcon() {
    if (route.transfers == 0) {
      if (route.modes.contains('jeepney')) return Icons.airport_shuttle;
      if (route.modes.contains('bus')) return Icons.directions_bus;
      if (route.modes.any(
        (m) => m.startsWith('lrt') || m.startsWith('mrt') || m == 'pnr',
      )) {
        return Icons.train;
      }
      return Icons.directions_walk;
    }
    return Icons.alt_route;
  }

  @override
  Widget build(BuildContext context) {
    final isDiscounted = passengerType.isDiscounted;
    final effectiveFare = route.effectiveFare(passengerType);
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    final container = colorScheme.primaryContainer;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? container.withValues(alpha: 0.35)
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? primary : colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? container
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_getLeadingIcon(), size: 22, color: primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        route.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Active map route',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${route.etaMinutes} min • ${route.transfers} transfer${route.transfers == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (route.legs.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: route.legs.map((leg) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: leg.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: leg.color.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                leg.isWalk
                                    ? Icons.directions_walk
                                    : Icons.directions_bus,
                                size: 11,
                                color: leg.color,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                leg.isWalk
                                    ? '${leg.minutes}m'
                                    : '${leg.modeLabel ?? 'Ride'} ${leg.routeCode ?? ''} (${leg.minutes}m)',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: leg.color,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  if (route.summary.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      route.summary,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '₱$effectiveFare',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: primary,
                    ),
                  ),
                  if (isDiscounted) ...[
                    Text(
                      '₱${route.fare}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: container,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '-20%',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
