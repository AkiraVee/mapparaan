import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../constants.dart';
import '../services/ai_assistant_service.dart';
import '../services/memory_photo_compression_service.dart';
import '../services/memory_pin_service.dart';
import '../services/place_search_service.dart';
import '../services/route_planner_service.dart';
import '../services/saved_places_service.dart';
import '../services/transit_planner_service.dart';
import '../services/trip_history_service.dart';
import '../services/last_route_service.dart';
import '../services/commuter_preference_service.dart';
import '../services/saved_commute_service.dart';
import '../services/local_ui_preferences_service.dart';
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
  final LocalUiPreferences localPreferences;

  const LocationDetailsScreen({
    super.key,
    this.place,
    this.placeName = 'Universidad De Manila',
    this.userLocation,
    this.destinationCoordinates,
    this.origin = 'Current location',
    this.initialPreference = RoutePreference.fastest,
    this.passengerType = PassengerType.general,
    this.localPreferences = const LocalUiPreferences(),
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

  /// Set when the server says the trip is outside the City of Manila.
  String? _serviceAreaMessage;

  /// Set when the server answered but found no transit route.
  bool _noRouteFound = false;

  /// Set when the server answered with an error (it is up, but could not plan).
  String? _serverErrorMessage;

  late RoutePreference _selectedPreference;
  late PassengerType _passengerType;
  DateTime? _departureTime;
  Set<String> _avoidModes = {};

  List<TransitPlanOption> _routeOptions = const [];
  TransitPlanOption? _selectedOption;
  List<LatLng> _routePoints = [];
  LatLng? _routeOrigin;
  int _routeRequestId = 0;

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
        _isSaved = savedPlaces.any(
          (s) =>
              s.name == widget.resolvedPlaceName &&
              (s.coordinates.latitude - widget.resolvedDestination.latitude)
                      .abs() <
                  0.00001 &&
              (s.coordinates.longitude - widget.resolvedDestination.longitude)
                      .abs() <
                  0.00001,
        );
      });
    } catch (_) {}
  }

  Future<void> _refreshRoute() async {
    final requestId = ++_routeRequestId;
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

    if (!mounted || requestId != _routeRequestId) return;

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

    setState(() {
      _isLoadingRoute = true;
      _serviceAreaMessage = null;
      _serverErrorMessage = null;
      _noRouteFound = false;
    });
    _routeOrigin = origin;

    final result = await TransitPlannerService.planTransitResult(
      origin: origin,
      destination: destination,
      passengerType: _passengerType,
      departureTime: _departureTime,
      avoidModes: _avoidModes,
    );

    if (!mounted || requestId != _routeRequestId) return;

    // The server answered, but with no routes: say why instead of showing
    // sample routes. (Sample routes are only for when the server is offline.)
    // A planner/server error should not blank the screen. Continue through the
    // existing cached/foot-route fallback so users still get directions while
    // the backend is unavailable. Only genuine no-route/service-area answers
    // should stop here with an empty result list.
    if (result?.isServerError == true) {
      _serverErrorMessage = result?.message ?? 'The route planner is temporarily unavailable. Showing an estimated route.';
    }

    // Some API versions return an empty options list without a reason. Treat
    // that as an unavailable/insufficient planner response and use the same
    // fallback route as an API error. Only an explicit service-area response
    // should intentionally leave the result list empty.
    if (result != null &&
        result.options.isEmpty &&
        !result.isServerError &&
        result.isOutsideServiceArea) {
      setState(() {
        _isOfflineFallback = false;
        if (result.isOutsideServiceArea) {
          _serviceAreaMessage =
              result.message ??
              'Mapparaan currently covers the City of Manila only.';
        } else {
          _noRouteFound = true;
        }
        _routeOptions = const [];
        _selectedOption = null;
        _routePoints = [];
        _isLoadingRoute = false;
      });
      return;
    }

    if (result != null &&
        result.options.isEmpty &&
        !result.isServerError &&
        !result.isOutsideServiceArea) {
      _serverErrorMessage = 'The transit planner returned no route data. Showing an estimated route.';
    }

    final realPlans = result?.options;
    if (realPlans != null && realPlans.isNotEmpty) {
      final filteredPlans = _applyLocalRoutePreferences(realPlans);
      // Never pick the walk-only option as "Fastest" (or any tab). Walk-only
      // trips have no transit option, so fall back to the first option.
      final selected =
          TransitPlanOption.pickForPreference(
            filteredPlans,
            _selectedPreference,
          ) ??
          filteredPlans.first;
      final points = selected.allPoints.isNotEmpty
          ? selected.allPoints
          : [origin, destination];

      setState(() {
        _isOfflineFallback = false;
        _routeOptions = filteredPlans;
        _selectedOption = selected;
        _routePoints = points;
        _isLoadingRoute = false;
      });

      await LastRouteService.save(
        origin: origin,
        destination: destination,
        option: selected,
      );

      if (!mounted || requestId != _routeRequestId) return;

      _fitCameraToBounds(points);
    } else {
      final cached = await LastRouteService.load();
      if (!mounted || requestId != _routeRequestId) return;
      final cacheMatches =
          cached != null &&
          const Distance().as(
                LengthUnit.Meter,
                cached.destination,
                destination,
              ) <
              100;

      if (cacheMatches) {
        final cachedOption = cached.option;
        final cachedPoints = cachedOption.allPoints.isNotEmpty
            ? cachedOption.allPoints
            : [cached.origin, cached.destination];
        final cachedFallbackOptions = TransitPlannerService.getFallbackOptions(
          destination: destination,
          userLocation: cached.origin,
          preference: _selectedPreference,
          passengerType: _passengerType,
          avoidModes: _avoidModes,
          fallbackPath: cachedPoints,
        );
        final offlineOptions = cachedFallbackOptions.isNotEmpty
            ? cachedFallbackOptions
            : [cachedOption];
        final filteredOptions = _applyLocalRoutePreferences(offlineOptions);
        final selected =
            TransitPlanOption.pickForPreference(
              filteredOptions,
              _selectedPreference,
            ) ??
            filteredOptions.first;
        final selectedPoints = selected.allPoints.isNotEmpty
            ? selected.allPoints
            : cachedPoints;
        setState(() {
          _isOfflineFallback = true;
          _routeOptions = filteredOptions;
          _selectedOption = selected;
          _routePoints = selectedPoints;
          _isLoadingRoute = false;
        });
        _fitCameraToBounds(selectedPoints);
      } else {
        final geometry = await RoutePlannerService.fetchRoute(
          origin: origin,
          destination: destination,
          profile: 'foot',
        );

        if (!mounted || requestId != _routeRequestId) return;

        final fallbackPoints = (geometry != null && geometry.points.isNotEmpty)
            ? geometry.points
            : [origin, destination];

        final fallbackOptions = TransitPlannerService.getFallbackOptions(
          destination: destination,
          userLocation: origin,
          preference: _selectedPreference,
          passengerType: _passengerType,
          avoidModes: _avoidModes,
          fallbackPath: fallbackPoints,
        );

        final filteredOptions = _applyLocalRoutePreferences(fallbackOptions);
        final selected = filteredOptions.isNotEmpty
            ? TransitPlanOption.pickForPreference(
                    filteredOptions,
                    _selectedPreference,
                  ) ??
                  filteredOptions.first
            : null;

        setState(() {
          _isOfflineFallback = true;
          _routeOptions = filteredOptions;
          _selectedOption = selected;
          _routePoints = fallbackPoints;
          _isLoadingRoute = false;
        });

        if (selected != null) {
          await LastRouteService.save(
            origin: origin,
            destination: destination,
            option: selected,
          );
          if (!mounted || requestId != _routeRequestId) return;
        }

        _fitCameraToBounds(fallbackPoints);
      }
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
          fareEstimate: topOption.effectiveFare(_passengerType),
          routeSummary: topOption.summary.isNotEmpty
              ? topOption.summary
              : '${topOption.title} (${formatPeso(topOption.effectiveFare(_passengerType))})',
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
    // The walk-only card is not one of the three tabs, so tapping the tab that
    // already looks active must still switch away from a selected walk card.
    final walkSelected = _selectedOption?.isWalkOption ?? false;
    if (preference == _selectedPreference && !walkSelected) return;
    setState(() => _selectedPreference = preference);

    final matching = _routeOptions.where(
      (o) => !o.isWalkOption && o.routePreference == preference,
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

  Future<void> _pickDepartureTime() async {
    final now = DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departureTime ?? now),
      helpText: 'Choose departure time',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _departureTime = DateTime(
        now.year,
        now.month,
        now.day,
        picked.hour,
        picked.minute,
      );
    });
    _refreshRoute();
  }

  void _toggleAvoidMode(String mode, bool selected) {
    setState(() {
      final updated = {..._avoidModes};
      if (selected) {
        updated.add(mode);
      } else {
        updated.remove(mode);
      }
      _avoidModes = updated;
    });
    _refreshRoute();
  }

  void _selectOption(TransitPlanOption option) {
    setState(() {
      _selectedOption = option;
      if (!option.isWalkOption) {
        _selectedPreference = option.routePreference;
      }
      _routePoints = option.allPoints;
    });

    if (_routePoints.length >= 2) {
      _fitCameraToBounds(_routePoints);
    }
  }

  List<TransitPlanOption> _applyLocalRoutePreferences(
    List<TransitPlanOption> options,
  ) {
    final limit = widget.localPreferences.walkingLimitKm;
    if (limit == null) return options;

    final filtered = options.where((option) {
      final walkingKm = option.legs.where((leg) => leg.isWalk).fold<double>(0, (
        total,
        leg,
      ) {
        final legKm = leg.km ?? (leg.meters == null ? 0 : leg.meters! / 1000.0);
        return total + legKm;
      });
      // Keep routes without walking metadata so an incomplete server response
      // does not make the result screen empty.
      final hasWalkingMetadata = option.legs.any(
        (leg) => leg.isWalk && (leg.km != null || leg.meters != null),
      );
      return !hasWalkingMetadata || walkingKm <= limit;
    }).toList();

    // Never hide every result just because a server omitted some leg data.
    return filtered.isEmpty ? options : filtered;
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

  Future<void> _handleInviteCommuter() async {
    final option = _selectedOption;
    if (option == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a route before inviting someone.'),
        ),
      );
      return;
    }

    final inviteeController = TextEditingController();
    final invitee = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Invite a commuter'),
        content: TextField(
          controller: inviteeController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Who would you like to invite?',
            hintText: 'Optional name',
            prefixIcon: Icon(Icons.person_add_alt_1_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pop(dialogContext, inviteeController.text),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share invite'),
          ),
        ],
      ),
    );
    inviteeController.dispose();
    if (!mounted || invitee == null) return;

    final recipient = invitee.trim().isEmpty ? 'A friend' : invitee.trim();
    final fare = option.effectiveFare(_passengerType);
    final preference =
        _selectedPreference.name[0].toUpperCase() +
        _selectedPreference.name.substring(1);
    final message = StringBuffer()
      ..writeln('Mapparaan commute invite')
      ..writeln()
      ..writeln('Hi $recipient, want to travel together?')
      ..writeln('Destination: ${widget.resolvedPlaceName}')
      ..writeln('Starting point: ${widget.origin}')
      ..writeln('Route: ${option.title}')
      ..writeln('Estimated travel time: ${option.etaMinutes} min')
      ..writeln('Estimated fare: ${formatPeso(fare)}')
      ..writeln('Preference: $preference')
      ..writeln()
      ..writeln(
        'Open Mapparaan and search for this destination to choose your route.',
      );

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: message.toString(),
          subject: 'Mapparaan commute invite',
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share invite: $error')),
        );
      }
    }
  }

  Future<void> _handleSaveCommute() async {
    final origin = _routeOrigin ?? widget.userLocation;
    if (origin == null || _selectedOption == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a route before saving it.')),
      );
      return;
    }

    final labelController = TextEditingController(
      text: '${widget.origin} → ${widget.resolvedPlaceName}',
    );
    final label = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save commute'),
        content: TextField(
          controller: labelController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Shortcut name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, labelController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    labelController.dispose();
    if (!mounted || label == null || label.trim().isEmpty) return;

    await SavedCommuteService.save(
      SavedCommute(
        id: '${origin.latitude},${origin.longitude}|${widget.resolvedDestination.latitude},${widget.resolvedDestination.longitude}',
        label: label.trim(),
        originName: widget.origin,
        origin: origin,
        destinationName: widget.resolvedPlaceName,
        destination: widget.resolvedDestination,
        preference: _selectedPreference,
        passengerType: _passengerType,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Commute shortcut saved on this device.')),
      );
    }
  }

  Future<void> _reportProblem() async {
    const categories = [
      'Wrong fare',
      'Route or stop is incorrect',
      'Route does not exist',
      'Safety concern',
    ];
    final category = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Report a problem'),
        children: categories
            .map(
              (item) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, item),
                child: Text(item),
              ),
            )
            .toList(),
      ),
    );
    if (category == null || !mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        text:
            'Mapparaan route report\n'
            'Category: $category\n'
            'Place: ${widget.resolvedPlaceName}\n'
            'Coordinates: ${widget.resolvedDestination.latitude}, '
            '${widget.resolvedDestination.longitude}',
        subject: 'Mapparaan route report',
      ),
    );
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
    final hasRouteGeometry =
        _selectedOption?.legs.any((leg) => leg.path.length >= 2) ?? false;

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
                  if (hasRouteGeometry)
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
                serviceAreaMessage: _serviceAreaMessage,
                serverErrorMessage: _serverErrorMessage,
                noRouteFound: _noRouteFound,
                selectedPreference: _selectedPreference,
                passengerType: _passengerType,
                departureTime: _departureTime,
                avoidModes: _avoidModes,
                routeOptions: _routeOptions,
                selectedOption: _selectedOption,
                onSaveToggle: _handleSaveToggle,
                onSaveCommute: _handleSaveCommute,
                onShare: _handleShare,
                onInviteCommuter: _handleInviteCommuter,
                onClose: () => Navigator.of(context).pop(),
                onPreferenceSelected: _selectPreference,
                onPassengerTypeSelected: _selectPassengerType,
                onOptionSelected: _selectOption,
                onReportProblem: _reportProblem,
                onDepartureTimeSelected: _pickDepartureTime,
                onAvoidModeChanged: _toggleAvoidMode,
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
  final String? serviceAreaMessage;
  final String? serverErrorMessage;
  final bool noRouteFound;
  final RoutePreference selectedPreference;
  final PassengerType passengerType;
  final DateTime? departureTime;
  final Set<String> avoidModes;
  final List<TransitPlanOption> routeOptions;
  final TransitPlanOption? selectedOption;
  final VoidCallback onSaveToggle;
  final VoidCallback onSaveCommute;
  final VoidCallback onShare;
  final VoidCallback onInviteCommuter;
  final VoidCallback onClose;
  final ValueChanged<RoutePreference> onPreferenceSelected;
  final ValueChanged<PassengerType> onPassengerTypeSelected;
  final ValueChanged<TransitPlanOption> onOptionSelected;
  final VoidCallback onReportProblem;
  final VoidCallback onDepartureTimeSelected;
  final void Function(String mode, bool selected) onAvoidModeChanged;

  const _PlaceDetailsSheet({
    required this.placeName,
    required this.address,
    required this.coordinates,
    required this.isSaved,
    required this.isOfflineFallback,
    required this.serviceAreaMessage,
    required this.serverErrorMessage,
    required this.noRouteFound,
    required this.selectedPreference,
    required this.passengerType,
    required this.departureTime,
    required this.avoidModes,
    required this.routeOptions,
    required this.selectedOption,
    required this.onSaveToggle,
    required this.onSaveCommute,
    required this.onShare,
    required this.onInviteCommuter,
    required this.onClose,
    required this.onPreferenceSelected,
    required this.onPassengerTypeSelected,
    required this.onOptionSelected,
    required this.onReportProblem,
    required this.onDepartureTimeSelected,
    required this.onAvoidModeChanged,
  });

  @override
  State<_PlaceDetailsSheet> createState() => _PlaceDetailsSheetState();
}

class _PlaceDetailsSheetState extends State<_PlaceDetailsSheet> {
  double _heightFactor = 0.42;
  bool _isUploadingMemory = false;

  static const double _minFactor = 0.30;
  static const double _maxFactor = 0.90;
  Future<void> _addMemoryPhoto() async {
    if (_isUploadingMemory) return;
    setState(() => _isUploadingMemory = true);

    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        ),
      );
      if (source == null || !mounted) return;

      final pickedFile = await ImagePicker().pickImage(
        source: source,
        maxWidth: MemoryPhotoCompressionService.maxDimension.toDouble(),
        maxHeight: MemoryPhotoCompressionService.maxDimension.toDouble(),
        imageQuality: 100,
      );
      if (pickedFile == null || !mounted) return;

      final originalBytes = await pickedFile.readAsBytes();
      final imageBytes = await MemoryPhotoCompressionService.compress(
        originalBytes,
      );

      await MemoryPinService.addPin(
        placeName: widget.placeName,
        address: widget.address,
        coordinates: widget.coordinates,
        fileName: 'memory-${const Uuid().v4()}.jpg',
        contentType: 'image/jpeg',
        imageBytes: imageBytes,
      );

      if (mounted) {
        _showMemoryPhotoMessage('Memory photo compressed and uploaded.');
      }
    } on FormatException catch (error) {
      if (mounted) _showMemoryPhotoMessage(error.message);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('while uploading a memory photo'),
        ),
      );
      if (mounted) {
        _showMemoryPhotoMessage(
          'Could not upload the photo. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingMemory = false);
    }
  }

  void _showMemoryPhotoMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showBudgetCalculator() async {
    final route = widget.selectedOption;
    if (route == null) {
      _showMemoryPhotoMessage('Choose a route first to calculate its budget.');
      return;
    }
    final fareController = TextEditingController(
      text: formatPesoPlain(route.effectiveFare(widget.passengerType)),
    );
    final tripsController = TextEditingController(text: '2');
    final daysController = TextEditingController(text: '22');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final fare = double.tryParse(fareController.text) ?? 0;
          final trips = double.tryParse(tripsController.text) ?? 0;
          final days = double.tryParse(daysController.text) ?? 0;
          final daily = fare * trips;
          final monthly = daily * days;
          return AlertDialog(
            title: const Text('Commute budget'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: fareController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'One-way fare (₱)',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  TextField(
                    controller: tripsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Trips per day',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  TextField(
                    controller: daysController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Commute days per month',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Daily: ₱${daily.toStringAsFixed(2)}\nMonthly: ₱${monthly.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
    fareController.dispose();
    tripsController.dispose();
    daysController.dispose();
  }

  Future<void> _showFareChecker() async {
    final route = widget.selectedOption;
    if (route == null) {
      _showMemoryPhotoMessage('Choose a route first to check the fare.');
      return;
    }
    final chargedController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Fare checker'),
        content: TextField(
          controller: chargedController,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'What were you charged? (₱)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final charged = double.tryParse(chargedController.text);
              if (charged == null) return;
              final expected = route.effectiveFare(widget.passengerType);
              Navigator.pop(dialogContext);
              final upTo = route.effectiveFareUpTo(widget.passengerType);
              final estimate = route.hasFareRange(widget.passengerType)
                  ? '${formatPeso(expected)} to ${formatPeso(upTo)}'
                  : formatPeso(expected);
              final result =
                  charged >= expected - 0.01 && charged <= upTo + 0.01
                  ? 'This is within the current estimate of $estimate.'
                  : charged > upTo
                  ? 'This is ${formatPeso(charged - upTo)} above the estimate of $estimate.'
                  : 'This is ${formatPeso(expected - charged)} below the estimate of $estimate.';
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(result)));
            },
            child: const Text('Check'),
          ),
        ],
      ),
    );
    chargedController.dispose();
  }

  Future<void> _showEmergencyInfo() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Emergency information'),
        content: const Text(
          'National emergency hotline: 911\n\n'
          'Police, fire, and medical assistance: 911\n\n'
          'If you are in immediate danger, move to a staffed public area and contact local authorities.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

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
    final compactUi = CommuterPreferencesService.current.value.compactUi;
    const modeLabels = {
      'jeepney': 'Jeepney',
      'bus': 'Bus',
      'lrt1': 'LRT-1',
      'lrt2': 'LRT-2',
    };

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height:
          screenHeight *
          (compactUi ? _heightFactor.clamp(0.25, 0.55) : _heightFactor),
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
                          tooltip: widget.isSaved
                              ? 'Remove saved place'
                              : 'Save place',
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
                          tooltip: 'Save commute shortcut',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.route_outlined),
                          onPressed: widget.onSaveCommute,
                        ),
                        IconButton(
                          tooltip: 'Share place',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.share, color: colorScheme.onSurface),
                          onPressed: widget.onShare,
                        ),
                        IconButton(
                          tooltip: 'Invite a commuter',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.group_add_outlined,
                            color: colorScheme.onSurface,
                          ),
                          onPressed: widget.onInviteCommuter,
                        ),
                        IconButton(
                          tooltip: 'Close route details',
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
                          icon: _isUploadingMemory
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.camera_alt, size: 18),
                          label: Text(
                            _isUploadingMemory
                                ? 'Uploading photo...'
                                : 'Add Memory Photo',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primary,
                            side: BorderSide(color: primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          onPressed: _isUploadingMemory
                              ? null
                              : _addMemoryPhoto,
                        ),
                      );
                    },
                  ),

                  _PassengerTypeSelector(
                    selectedType: widget.passengerType,
                    onSelected: widget.onPassengerTypeSelected,
                  ),
                  const SizedBox(height: 10),

                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _showBudgetCalculator,
                        icon: const Icon(Icons.calculate_outlined, size: 17),
                        label: const Text('Budget'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _showFareChecker,
                        icon: const Icon(Icons.receipt_long_outlined, size: 17),
                        label: const Text('Check fare'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _showEmergencyInfo,
                        icon: const Icon(Icons.emergency_outlined, size: 17),
                        label: const Text('Emergency'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

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
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: widget.onDepartureTimeSelected,
                    icon: const Icon(Icons.schedule, size: 17),
                    label: Text(
                      widget.departureTime == null
                          ? 'Leave now'
                          : 'Depart at ${widget.departureTime!.hour.toString().padLeft(2, '0')}:${widget.departureTime!.minute.toString().padLeft(2, '0')}',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Avoid modes (optional)',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    children: modeLabels.entries
                        .map(
                          (entry) => FilterChip(
                            label: Text(entry.value),
                            selected: widget.avoidModes.contains(entry.key),
                            onSelected: (selected) =>
                                widget.onAvoidModeChanged(entry.key, selected),
                          ),
                        )
                        .toList(),
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
                              'Server offline: these are rough distance-based samples, not real routes. Start backend/planner/api.py for real routes.',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFFBF360C),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (widget.serviceAreaMessage != null)
                    _NoticeBanner(
                      icon: Icons.location_off_outlined,
                      text:
                          '${widget.serviceAreaMessage} Choose a start and destination inside the City of Manila.',
                    ),
                  if (widget.serverErrorMessage != null)
                    _NoticeBanner(
                      icon: Icons.error_outline,
                      text: widget.serverErrorMessage!,
                    ),
                  if (widget.noRouteFound)
                    const _NoticeBanner(
                      icon: Icons.alt_route,
                      text: 'No transit route found for this trip. Try another departure time, or allow more modes.',
                    ),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: widget.onReportProblem,
                      icon: const Icon(Icons.flag_outlined, size: 16),
                      label: const Text('Report a problem'),
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

// ─── Notice banner ────────────────────────────────────────────────────────────

class _NoticeBanner extends StatelessWidget {
  final IconData icon;
  final String text;

  const _NoticeBanner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFE0B2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFE65100)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Color(0xFFBF360C)),
            ),
          ),
        ],
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
                        'Discounted',
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
      if (route.modes.any((m) => m.startsWith('lrt') || m.startsWith('mrt'))) {
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
    final fareUpTo = route.effectiveFareUpTo(passengerType);
    final hasFareRange = route.hasFareRange(passengerType);
    // Walking-only routes have no fare, so there is no discount to show.
    final showDiscount =
        isDiscounted && route.fare > route.fareDiscounted + 0.001;
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    final container = colorScheme.primaryContainer;

    return Semantics(
      button: true,
      label:
          '${route.title}, estimated ${route.etaMinutes} minutes, '
          '${route.fareEstimated ? 'estimated ' : ''}fare ${formatPesoPlain(effectiveFare)} pesos'
          '${hasFareRange ? ', up to ${formatPesoPlain(fareUpTo)} pesos on a modern or air-conditioned vehicle' : ''}',
      child: InkWell(
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
                    if (route.legs.isNotEmpty)
                      Material(
                        type: MaterialType.transparency,
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text(
                            'View step-by-step directions',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          children: route.legs.asMap().entries.map((entry) {
                            final index = entry.key + 1;
                            final leg = entry.value;
                            final distance = leg.meters == null
                                ? ''
                                : ' • ${(leg.meters! / 1000).toStringAsFixed(1)} km';
                            final detail = leg.isWalk
                                ? 'Walk from ${leg.from} to ${leg.to}'
                                : 'Take ${leg.modeLabel ?? 'transit'}'
                                      '${leg.routeCode == null ? '' : ' ${leg.routeCode}'} '
                                      'from ${leg.from} to ${leg.to}';
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                radius: 13,
                                backgroundColor: leg.color.withValues(
                                  alpha: 0.15,
                                ),
                                child: Text(
                                  '$index',
                                  style: TextStyle(color: leg.color),
                                ),
                              ),
                              title: Text(
                                detail,
                                style: const TextStyle(fontSize: 11),
                              ),
                              subtitle: Text(
                                '${leg.minutes} min$distance${leg.stops == null ? '' : ' • ${leg.stops} stops'}',
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
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
                      formatPeso(effectiveFare),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: primary,
                      ),
                    ),
                    if (hasFareRange)
                      Text(
                        'up to ${formatPeso(fareUpTo)} if modern/aircon',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      route.fareEstimated ? 'Estimated' : 'Per fare table',
                      style: TextStyle(
                        fontSize: 9,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Round trip ${formatPeso(effectiveFare * 2)}',
                      style: TextStyle(
                        fontSize: 9,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (showDiscount) ...[
                      Text(
                        formatPeso(route.fare),
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
                          '-${route.discountPercent}%',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: primary,
                          ),
                        ),
                      ),
                    ],
                    if (showDiscount)
                      Text(
                        'Bring a valid ID',
                        style: TextStyle(
                          fontSize: 9,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      route.fareSource,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
