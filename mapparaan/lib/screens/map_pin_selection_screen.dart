import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../services/manila_boundary_service.dart';
import '../services/place_search_service.dart';
import '../widgets/mapparaan_tile_layer.dart';

enum MapPinRole { pickup, destination }

class MapPinSelectionScreen extends StatefulWidget {
  final MapPinRole role;
  final LatLng? initialPoint;
  final bool showMap;
  final PlaceReverseGeocode reverseGeocode;
  final Future<ManilaBoundary> Function() loadBoundary;

  const MapPinSelectionScreen({
    super.key,
    required this.role,
    this.initialPoint,
    this.showMap = true,
    this.reverseGeocode = PlaceSearchService.reverseGeocode,
    this.loadBoundary = ManilaBoundaryService.load,
  });

  @override
  State<MapPinSelectionScreen> createState() => _MapPinSelectionScreenState();
}

class _MapPinSelectionScreenState extends State<MapPinSelectionScreen> {
  final MapController _mapController = MapController();

  late LatLng _point;
  ManilaBoundary? _boundary;
  PlaceResult? _address;
  Timer? _addressDebounce;
  String? _boundaryError;
  String? _addressError;
  bool _isLoadingBoundary = true;
  bool _isResolvingAddress = false;
  int _addressRequestId = 0;

  bool get _isInsideManila => _boundary?.contains(_point) ?? false;

  @override
  void initState() {
    super.initState();
    _point =
        widget.initialPoint ??
        const LatLng(AppConstants.defaultLat, AppConstants.defaultLng);
    _loadBoundary();
  }

  Future<void> _loadBoundary() async {
    try {
      final boundary = await widget.loadBoundary();
      if (!mounted) return;
      setState(() {
        _boundary = boundary;
        _isLoadingBoundary = false;
      });
      _scheduleAddressLookup(_point, immediately: true);
    } on Exception catch (error) {
      debugPrint(
        'Could not load Manila boundary for map pin selection: $error',
      );
      if (!mounted) return;
      setState(() {
        _boundaryError = 'Manila boundary data could not be loaded.';
        _isLoadingBoundary = false;
      });
    }
  }

  void _movePin(LatLng point) {
    if (!mounted) return;
    setState(() {
      _point = point;
      _address = null;
      _addressError = null;
    });
    _scheduleAddressLookup(point);
  }

  void _scheduleAddressLookup(LatLng point, {bool immediately = false}) {
    _addressDebounce?.cancel();
    final requestId = ++_addressRequestId;
    if (!(_boundary?.contains(point) ?? false)) {
      setState(() => _isResolvingAddress = false);
      return;
    }
    setState(() => _isResolvingAddress = true);
    if (immediately) {
      unawaited(_lookupAddress(point, requestId));
      return;
    }
    _addressDebounce = Timer(const Duration(milliseconds: 450), () {
      _lookupAddress(point, requestId);
    });
  }

  Future<void> _lookupAddress(LatLng point, int requestId) async {
    try {
      final result = await widget.reverseGeocode(point);
      if (!mounted || requestId != _addressRequestId) return;
      setState(() {
        _address = result;
        _isResolvingAddress = false;
        _addressError = null;
      });
    } on Exception catch (error) {
      debugPrint('Reverse geocoding failed for selected map pin: $error');
      if (!mounted || requestId != _addressRequestId) return;
      setState(() {
        _address = null;
        _isResolvingAddress = false;
        _addressError =
            'Address lookup is unavailable. Routing can still use this pin.';
      });
    }
  }

  void _confirmSelection() {
    if (!_isInsideManila) return;
    final coordinates =
        '${_point.latitude.toStringAsFixed(6)}, '
        '${_point.longitude.toStringAsFixed(6)}';
    Navigator.of(context).pop(
      _address ??
          PlaceResult(
            name: 'Pinned location',
            subtitle: coordinates,
            coordinates: _point,
          ),
    );
  }

  @override
  void dispose() {
    _addressDebounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final boundary = _boundary;
    final roleLabel = widget.role == MapPinRole.pickup
        ? 'Pickup'
        : 'Destination';

    return Scaffold(
      appBar: AppBar(
        title: Text('Choose $roleLabel'),
      ),
      body: Stack(
        children: [
          FlutterMap(
            key: const ValueKey('map-pin-map'),
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _point,
              initialZoom: 16,
              minZoom: AppConstants.minZoom,
              maxZoom: AppConstants.maxZoom,
              onTap: (_, point) {
                _movePin(point);
                _mapController.move(point, _mapController.camera.zoom);
              },
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) _movePin(camera.center);
              },
            ),
            children: [
              if (widget.showMap)
                const MapparaanTileLayer()
              else
                const ColoredBox(color: Color(0xFFE8ECEF)),
              if (boundary != null)
                PolygonLayer(
                  polygons: [
                    for (final ring in boundary.outerRings)
                      Polygon(
                        points: ring,
                        color: colorScheme.primary.withValues(alpha: 0.08),
                        borderColor: colorScheme.primary,
                        borderStrokeWidth: 2,
                      ),
                  ],
                ),
            ],
          ),
          Center(
            child: IgnorePointer(
              child: Transform.translate(
                offset: const Offset(0, -22),
                child: Icon(
                  Icons.location_pin,
                  key: const ValueKey('map-pin-marker'),
                  size: 48,
                  color: _isInsideManila
                      ? colorScheme.primary
                      : colorScheme.error,
                  semanticLabel: 'Selected map pin',
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: Card(
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Pan the map or tap a point to move the pin.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isLoadingBoundary
                            ? 'Loading Manila boundary…'
                            : _boundaryError ??
                                  (_isInsideManila
                                      ? _address?.name ??
                                            (_isResolvingAddress
                                                ? 'Looking up address…'
                                                : 'Pinned location')
                                      : 'Outside MapParaan’s supported area'),
                        key: const ValueKey('map-pin-status'),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: _isInsideManila ? null : colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _address?.subtitle ??
                            (_addressError ??
                                (_isInsideManila
                                    ? 'No readable address found. Routing will use the pin coordinates.'
                                    : 'Select a point within the Manila City boundary.')),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Coordinates: $_pointCoordinates',
                        key: const ValueKey('map-pin-coordinates'),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      if (_isResolvingAddress) ...[
                        const SizedBox(height: 10),
                        const LinearProgressIndicator(),
                      ],
                      if (_boundaryError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Selection is disabled until the boundary can be verified.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const ValueKey('map-pin-confirm'),
                        onPressed:
                            !_isLoadingBoundary &&
                                _boundaryError == null &&
                                _isInsideManila
                            ? _confirmSelection
                            : null,
                        icon: const Icon(Icons.check),
                        label: Text('Confirm $roleLabel'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _pointCoordinates =>
      '${_point.latitude.toStringAsFixed(6)}, '
      '${_point.longitude.toStringAsFixed(6)}';
}
