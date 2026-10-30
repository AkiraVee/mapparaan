import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../services/ai_assistant_service.dart';
import '../services/manila_boundary_service.dart';
import '../services/place_search_service.dart';
import '../services/saved_places_service.dart';
import '../widgets/mapparaan_tile_layer.dart';
import 'map_pin_selection_screen.dart';

class SearchLocationScreen extends StatefulWidget {
  final String? initialQuery;
  final bool showMap;
  final PlaceSearch searchPlaces;
  final PlaceReverseGeocode reverseGeocode;
  final Future<ManilaBoundary> Function() loadManilaBoundary;
  final Future<List<SavedPlace>> Function() loadSavedPlaces;

  const SearchLocationScreen({
    super.key,
    this.initialQuery,
    this.showMap = true,
    this.searchPlaces = PlaceSearchService.search,
    this.reverseGeocode = PlaceSearchService.reverseGeocode,
    this.loadManilaBoundary = ManilaBoundaryService.load,
    this.loadSavedPlaces = SavedPlacesService.fetchSavedPlaces,
  });

  @override
  State<SearchLocationScreen> createState() => _SearchLocationScreenState();
}

class _SearchLocationScreenState extends State<SearchLocationScreen> {
  final TextEditingController _topSearchController = TextEditingController();
  final FocusNode _topSearchFocusNode = FocusNode();
  final MapController _mapController = MapController();

  static const _recentPlacesKey = 'recent_search_places';
  static const _maxRecentPlaces = 8;

  bool _hasSearchError = false;
  bool _hasSearched = false;
  bool _isSearching = false;
  bool _isDebouncing = false;
  bool _isLocating = false;
  bool _isLoadingSavedPlaces = true;
  bool _hasSavedPlacesError = false;
  bool _hasRecentPlacesError = false;

  LatLng? _userLocation;
  List<PlaceResult> _searchResults = const [];
  List<PlaceResult> _recentPlaces = const [];
  List<SavedPlace> _savedPlaces = const [];
  PlaceResult? _selectedPlace;
  PlaceResult? _selectedOrigin;
  Timer? _debounce;
  String? _selectedCategory;
  int _searchGeneration = 0;

  static const _allPlaces = <String, List<_PopularPlace>>{
    'Mall': [
      _PopularPlace('SM Mall of Asia', 'Pasay City', LatLng(14.5351, 120.9822)),
      _PopularPlace('SM North EDSA', 'Quezon City', LatLng(14.6569, 121.0307)),
      _PopularPlace('Robinsons Manila', 'Manila', LatLng(14.5750, 120.9830)),
      _PopularPlace(
        'Ayala Malls Manila Bay',
        'Pasay',
        LatLng(14.5358, 120.9815),
      ),
      _PopularPlace('Greenbelt', 'Makati', LatLng(14.5520, 121.0240)),
      _PopularPlace('Trinoma', 'Quezon City', LatLng(14.6535, 121.0325)),
    ],
    'Hospital': [
      _PopularPlace(
        'Philippine General Hospital',
        'Manila',
        LatLng(14.5778, 120.9856),
      ),
      _PopularPlace(
        'St. Luke\'s Medical Center',
        'Quezon City',
        LatLng(14.6400, 121.0450),
      ),
      _PopularPlace(
        'Makati Medical Center',
        'Makati',
        LatLng(14.5580, 121.0140),
      ),
      _PopularPlace(
        'Chinese General Hospital',
        'Manila',
        LatLng(14.6250, 120.9850),
      ),
      _PopularPlace('The Medical City', 'Pasig', LatLng(14.5700, 121.0650)),
    ],
    'School': [
      _PopularPlace(
        'University of Santo Tomas',
        'España, Manila',
        LatLng(14.6091, 120.9894),
      ),
      _PopularPlace(
        'University of the Philippines Diliman',
        'Quezon City',
        LatLng(14.6537, 121.0687),
      ),
      _PopularPlace(
        'Ateneo de Manila University',
        'Quezon City',
        LatLng(14.6390, 121.0780),
      ),
      _PopularPlace(
        'De La Salle University',
        'Manila',
        LatLng(14.5647, 120.9932),
      ),
      _PopularPlace(
        'Polytechnic University of the Philippines',
        'Manila',
        LatLng(14.5980, 121.0100),
      ),
    ],
    'LRT/MRT': [
      _PopularPlace('LRT-1 Baclaran', 'Pasay', LatLng(14.5340, 120.9950)),
      _PopularPlace('LRT-1 Doroteo Jose', 'Manila', LatLng(14.6040, 120.9820)),
      _PopularPlace(
        'MRT-3 North Avenue',
        'Quezon City',
        LatLng(14.6520, 121.0330),
      ),
      _PopularPlace('MRT-3 Ayala', 'Makati', LatLng(14.5490, 121.0270)),
      _PopularPlace('LRT-2 Recto', 'Manila', LatLng(14.6030, 120.9830)),
    ],
    'Park': [
      _PopularPlace('Rizal Park (Luneta)', 'Manila', LatLng(14.5832, 120.9794)),
      _PopularPlace(
        'Quezon City Memorial Circle',
        'Quezon City',
        LatLng(14.6510, 121.0490),
      ),
      _PopularPlace(
        'Arroceros Forest Park',
        'Manila',
        LatLng(14.5930, 120.9810),
      ),
      _PopularPlace(
        'La Mesa Eco Park',
        'Quezon City',
        LatLng(14.7120, 121.0920),
      ),
    ],
    'Market': [
      _PopularPlace('Divisoria Market', 'Manila', LatLng(14.6040, 120.9700)),
      _PopularPlace('Baclaran Market', 'Pasay', LatLng(14.5345, 120.9960)),
      _PopularPlace('Quiapo Market', 'Manila', LatLng(14.5980, 120.9835)),
      _PopularPlace('Cartimar Market', 'Pasay', LatLng(14.5450, 120.9950)),
    ],
  };

  static const _defaultPopular = [
    _PopularPlace('SM Mall of Asia', 'Pasay City', LatLng(14.5351, 120.9822)),
    _PopularPlace('Intramuros', 'Manila', LatLng(14.5896, 120.9747)),
    _PopularPlace(
      'Quezon City Circle',
      'Quezon City',
      LatLng(14.6510, 121.0490),
    ),
    _PopularPlace('BGC High Street', 'Taguig', LatLng(14.5515, 121.0510)),
    _PopularPlace(
      'University of Santo Tomas',
      'España, Manila',
      LatLng(14.6091, 120.9894),
    ),
    _PopularPlace('NAIA Terminal 3', 'Pasay', LatLng(14.5086, 121.0197)),
  ];

  static const _quickChips = [
    'Mall',
    'Hospital',
    'School',
    'LRT/MRT',
    'Park',
    'Market',
  ];

  List<_PopularPlace> get _displayedPlaces {
    if (_selectedCategory == null) return _defaultPopular;
    return _allPlaces[_selectedCategory] ?? _defaultPopular;
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _topSearchController.text = widget.initialQuery!;
      _onSearchChanged(widget.initialQuery!);
    }
    _loadRecentPlaces();
    _loadSavedPlaces();
  }

  Future<void> _useCurrentLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationMessage(
          'Turn on location services to use your current location.',
          action: SnackBarAction(
            label: 'Settings',
            onPressed: Geolocator.openLocationSettings,
          ),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showLocationMessage(
            'Location permission is needed for nearby search. You can still search manually.',
          );
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showLocationMessage(
          'Location permission is off. Enable it in Settings or search manually.',
          action: SnackBarAction(
            label: 'Settings',
            onPressed: Geolocator.openAppSettings,
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final userLatLng = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => _userLocation = userLatLng);
      if (widget.showMap) _mapController.move(userLatLng, 14.0);
    } on Exception catch (error) {
      debugPrint('Current location lookup failed: $error');
      _showLocationMessage(
        'Could not get your location. You can still search manually.',
      );
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _showLocationMessage(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), action: action));
  }

  Future<void> _loadRecentPlaces() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString(_recentPlacesKey);
      if (encoded == null) return;

      final decoded = jsonDecode(encoded);
      if (decoded is! List) {
        throw const FormatException('Recent searches are not a list.');
      }
      final places = <PlaceResult>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final name = item['name'];
        final subtitle = item['subtitle'];
        final latitude = double.tryParse(item['latitude']?.toString() ?? '');
        final longitude = double.tryParse(item['longitude']?.toString() ?? '');
        if (name is! String ||
            name.trim().isEmpty ||
            subtitle is! String ||
            latitude == null ||
            longitude == null ||
            latitude < -90 ||
            latitude > 90 ||
            longitude < -180 ||
            longitude > 180) {
          continue;
        }
        places.add(
          PlaceResult(
            name: name,
            subtitle: subtitle,
            coordinates: LatLng(latitude, longitude),
          ),
        );
      }
      if (mounted) {
        setState(() => _recentPlaces = places.take(_maxRecentPlaces).toList());
      }
    } on Exception catch (error) {
      debugPrint('Could not load recent place searches: $error');
      if (mounted) setState(() => _hasRecentPlacesError = true);
    }
  }

  Future<void> _loadSavedPlaces() async {
    try {
      final places = await widget.loadSavedPlaces();
      if (!mounted) return;
      setState(() {
        _savedPlaces = places;
        _isLoadingSavedPlaces = false;
        _hasSavedPlacesError = false;
      });
    } on Exception catch (error) {
      debugPrint('Could not load saved places in search: $error');
      if (!mounted) return;
      setState(() {
        _isLoadingSavedPlaces = false;
        _hasSavedPlacesError = true;
      });
    }
  }

  Future<void> _recordRecentPlace(PlaceResult place) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final recent = [
        place,
        ..._recentPlaces.where(
          (existing) =>
              existing.name != place.name ||
              existing.coordinates != place.coordinates,
        ),
      ].take(_maxRecentPlaces);
      final encoded = jsonEncode(
        recent
            .map(
              (item) => {
                'name': item.name,
                'subtitle': item.subtitle,
                'latitude': item.coordinates.latitude,
                'longitude': item.coordinates.longitude,
              },
            )
            .toList(),
      );
      await preferences.setString(_recentPlacesKey, encoded);
      if (mounted) setState(() => _recentPlaces = recent.toList());
    } on Exception catch (error) {
      debugPrint('Could not save recent place search: $error');
      _showLocationMessage('This place could not be saved to recent searches.');
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final generation = ++_searchGeneration;
    final trimmed = query.trim();
    setState(() {
      _selectedPlace = null;
      _selectedCategory = null;
      _searchResults = const [];
      _hasSearchError = false;
      _hasSearched = false;
      _isSearching = false;
      _isDebouncing = trimmed.length >= AppConstants.searchMinQueryLength;
    });

    if (trimmed.length < AppConstants.searchMinQueryLength) return;
    // Keep requests below Nominatim's public-service rate limit.
    _debounce = Timer(const Duration(milliseconds: 1100), () {
      _runSearch(trimmed, generation);
    });
  }

  Future<void> _runSearch(String query, int generation) async {
    final trimmed = query.trim();
    if (generation != _searchGeneration) return;
    setState(() {
      _isSearching = true;
      _isDebouncing = false;
      _hasSearchError = false;
    });

    try {
      final results = await widget.searchPlaces(trimmed);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
        _hasSearched = true;
      });
    } on Exception catch (error) {
      debugPrint('Place search failed: $error');
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchResults = const [];
        _isSearching = false;
        _hasSearched = true;
        _hasSearchError = true;
      });
    }
  }

  void _clearSearch() {
    _debounce?.cancel();
    ++_searchGeneration;
    _topSearchController.clear();
    setState(() {
      _searchResults = const [];
      _selectedPlace = null;
      _hasSearchError = false;
      _hasSearched = false;
      _isSearching = false;
      _isDebouncing = false;
      _selectedCategory = null;
    });
    _topSearchFocusNode.requestFocus();
  }

  void _onChipTap(String chip) {
    _debounce?.cancel();
    ++_searchGeneration;
    _topSearchController.clear();
    setState(() {
      _selectedCategory = _selectedCategory == chip ? null : chip;
      _searchResults = const [];
      _selectedPlace = null;
      _isSearching = false;
      _isDebouncing = false;
      _hasSearchError = false;
      _hasSearched = false;
    });
  }

  void _onPopularTap(_PopularPlace popular) {
    final query = popular.name;
    _topSearchController.text = query;
    _topSearchController.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    _onSearchChanged(query);
  }

  void _previewPlace(PlaceResult place) {
    FocusScope.of(context).unfocus();
    setState(() => _selectedPlace = place);
    if (widget.showMap) {
      _mapController.move(place.coordinates, 15.0);
    }
  }

  void _previewSavedPlace(SavedPlace place) {
    _previewPlace(
      PlaceResult(
        name: place.name,
        subtitle: place.subtitle,
        coordinates: place.coordinates,
      ),
    );
  }

  Future<void> _selectPlace(PlaceResult place) async {
    await _recordRecentPlace(place);
    if (!mounted) return;
    Navigator.of(context).pop(
      SearchSelection(
        place: place,
        origin: _selectedOrigin,
        resolution: AiQueryResolution.fromQuery(
          _topSearchController.text.trim().isEmpty
              ? place.name
              : _topSearchController.text.trim(),
        ),
      ),
    );
  }

  Future<void> _pickMapPoint(MapPinRole role) async {
    final selected = await Navigator.of(context).push<PlaceResult>(
      MaterialPageRoute(
        builder: (_) => MapPinSelectionScreen(
          role: role,
          showMap: widget.showMap,
          reverseGeocode: widget.reverseGeocode,
          loadBoundary: widget.loadManilaBoundary,
          initialPoint: role == MapPinRole.pickup
              ? _selectedOrigin?.coordinates ?? _userLocation
              : _selectedPlace?.coordinates,
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (role == MapPinRole.pickup) {
      setState(() => _selectedOrigin = selected);
      _showLocationMessage('Pickup point selected on the map.');
      return;
    }
    await _selectPlace(selected);
  }

  void _retry() {
    _onSearchChanged(_topSearchController.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _topSearchController.dispose();
    _topSearchFocusNode.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final query = _topSearchController.text.trim();
    final mapPeek =
        widget.showMap && MediaQuery.viewInsetsOf(context).bottom == 0
        ? 112.0
        : 8.0;

    return Scaffold(
      body: Stack(
        children: [
          // Map remains visual context in this version of search.
          if (widget.showMap)
            IgnorePointer(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter:
                      _userLocation ??
                      const LatLng(
                        AppConstants.defaultLat,
                        AppConstants.defaultLng,
                      ),
                  initialZoom: AppConstants.defaultZoom,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  const MapparaanTileLayer(),
                  if (_userLocation != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _userLocation!,
                          width: 24,
                          height: 24,
                          child: Container(
                            decoration: BoxDecoration(
                              color: colorScheme.secondary.withValues(
                                alpha: 0.3,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: colorScheme.secondary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: colorScheme.surface,
                                    width: 2.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (_selectedPlace != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _selectedPlace!.coordinates,
                          width: 44,
                          height: 52,
                          child: Icon(
                            Icons.location_pin,
                            color: colorScheme.primary,
                            size: 44,
                            semanticLabel: 'Selected place',
                          ),
                        ),
                      ],
                    ),
                  if (_selectedOrigin != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _selectedOrigin!.coordinates,
                          width: 40,
                          height: 48,
                          child: Icon(
                            Icons.trip_origin,
                            color: colorScheme.secondary,
                            size: 36,
                            semanticLabel: 'Pickup location',
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            )
          else
            Positioned.fill(child: ColoredBox(color: colorScheme.surface)),

          // FULL UI OVERLAY (always on top, always receives taps)
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Material(
                            color: colorScheme.surface,
                            elevation: 4,
                            borderRadius: BorderRadius.circular(18),
                            child: TextField(
                              controller: _topSearchController,
                              focusNode: _topSearchFocusNode,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              textCapitalization: TextCapitalization.words,
                              decoration: InputDecoration(
                                hintText: 'Search places in Metro Manila',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: query.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Clear search',
                                        icon: const Icon(Icons.close),
                                        onPressed: _clearSearch,
                                      ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                              ),
                              onChanged: _onSearchChanged,
                              onSubmitted: _onSearchChanged,
                              onTapOutside: (_) =>
                                  FocusScope.of(context).unfocus(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Use my location',
                          onPressed: _isLocating ? null : _useCurrentLocation,
                          icon: _isLocating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.my_location),
                        ),
                        PopupMenuButton<MapPinRole>(
                          tooltip: 'Choose a location on the map',
                          icon: const Icon(Icons.pin_drop_outlined),
                          onSelected: _pickMapPoint,
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: MapPinRole.pickup,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.trip_origin),
                                title: Text('Choose pickup on map'),
                              ),
                            ),
                            PopupMenuItem(
                              value: MapPinRole.destination,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.location_on_outlined),
                                title: Text('Choose destination on map'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: mapPeek),
                  Expanded(
                    child: Material(
                      color: colorScheme.surface,
                      elevation: 10,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: colorScheme.outlineVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedPlace != null
                                            ? 'Selected place'
                                            : _isSearching
                                            ? 'Searching places'
                                            : _hasSearched
                                            ? 'Search results'
                                            : 'Explore places',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      if (_selectedOrigin != null)
                                        Text(
                                          'Pickup: ${_selectedOrigin!.name}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (_hasSearched &&
                                    !_isSearching &&
                                    !_hasSearchError)
                                  Text(
                                    '${_searchResults.length} found',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(child: _buildSearchContent(query)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchContent(String query) {
    if (_selectedPlace != null) {
      final selected = _selectedPlace!;
      return _SelectedPlacePreview(
        place: selected,
        onBack: () => setState(() => _selectedPlace = null),
        onPlanRoute: () => _selectPlace(selected),
      );
    }
    if (_hasSearchError) return _NoConnectionState(onRetry: _retry);
    if (_isSearching) return const _SearchSkeleton();
    if (_isDebouncing) {
      return const _SearchHintState(message: 'Searching as you type…');
    }
    if (query.isNotEmpty && query.length < AppConstants.searchMinQueryLength) {
      return _SearchHintState(
        message:
            'Type at least ${AppConstants.searchMinQueryLength} characters to search.',
      );
    }
    if (_hasSearched && _searchResults.isEmpty) {
      return _NoResultsState(query: query, onClear: _clearSearch);
    }
    if (_searchResults.isNotEmpty) {
      return _SearchDropdown(results: _searchResults, onSelect: _previewPlace);
    }
    return _EmptySearchState(
      popularPlaces: _displayedPlaces,
      chips: _quickChips,
      selectedCategory: _selectedCategory,
      recentPlaces: _recentPlaces,
      savedPlaces: _savedPlaces,
      isLoadingSavedPlaces: _isLoadingSavedPlaces,
      hasSavedPlacesError: _hasSavedPlacesError,
      hasRecentPlacesError: _hasRecentPlacesError,
      onPopularTap: _onPopularTap,
      onChipTap: _onChipTap,
      onSelectPlace: _previewPlace,
      onSelectSavedPlace: _previewSavedPlace,
      onRetrySavedPlaces: _loadSavedPlaces,
      onClearRecents: _clearRecentPlaces,
    );
  }

  Future<void> _clearRecentPlaces() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_recentPlacesKey);
      if (mounted) setState(() => _recentPlaces = const []);
    } on Exception catch (error) {
      debugPrint('Could not clear recent place searches: $error');
      _showLocationMessage('Recent places could not be cleared.');
    }
  }
}

class _PopularPlace {
  final String name;
  final String subtitle;
  final LatLng coordinates;

  const _PopularPlace(this.name, this.subtitle, this.coordinates);
}

class _EmptySearchState extends StatelessWidget {
  final List<_PopularPlace> popularPlaces;
  final List<String> chips;
  final String? selectedCategory;
  final List<PlaceResult> recentPlaces;
  final List<SavedPlace> savedPlaces;
  final bool isLoadingSavedPlaces;
  final bool hasSavedPlacesError;
  final bool hasRecentPlacesError;
  final ValueChanged<_PopularPlace> onPopularTap;
  final ValueChanged<String> onChipTap;
  final ValueChanged<PlaceResult> onSelectPlace;
  final ValueChanged<SavedPlace> onSelectSavedPlace;
  final VoidCallback onRetrySavedPlaces;
  final VoidCallback onClearRecents;

  const _EmptySearchState({
    required this.popularPlaces,
    required this.chips,
    required this.selectedCategory,
    required this.recentPlaces,
    required this.savedPlaces,
    required this.isLoadingSavedPlaces,
    required this.hasSavedPlacesError,
    required this.hasRecentPlacesError,
    required this.onPopularTap,
    required this.onChipTap,
    required this.onSelectPlace,
    required this.onSelectSavedPlace,
    required this.onRetrySavedPlaces,
    required this.onClearRecents,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Text(
          'Quick categories',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: chips.map((chip) {
              final isSelected = selectedCategory == chip;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(chip),
                  selected: isSelected,
                  onSelected: (_) => onChipTap(chip),
                  selectedColor: colorScheme.primaryContainer,
                  checkmarkColor: colorScheme.onPrimaryContainer,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
              );
            }).toList(),
          ),
        ),
        if (recentPlaces.isNotEmpty || hasRecentPlacesError) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recent places',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (recentPlaces.isNotEmpty)
                TextButton(
                  onPressed: onClearRecents,
                  child: const Text('Clear'),
                ),
            ],
          ),
          if (hasRecentPlacesError)
            Text(
              'Recent places could not be loaded from this device.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colorScheme.error),
            ),
          ...recentPlaces.map(
            (place) => _PlaceListTile(
              name: place.name,
              subtitle: place.subtitle,
              icon: Icons.history,
              onTap: () => onSelectPlace(place),
            ),
          ),
        ],
        ...[
          const SizedBox(height: 14),
          Text(
            'Saved places',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (isLoadingSavedPlaces)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            )
          else if (hasSavedPlacesError)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Could not load saved places'),
              trailing: TextButton(
                onPressed: onRetrySavedPlaces,
                child: const Text('Retry'),
              ),
            )
          else if (savedPlaces.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Places you save from their details will appear here.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            )
          else
            ...savedPlaces
                .take(6)
                .map(
                  (place) => _PlaceListTile(
                    name: place.name,
                    subtitle: place.subtitle,
                    icon: Icons.bookmark_outline,
                    onTap: () => onSelectSavedPlace(place),
                  ),
                ),
        ],
        const SizedBox(height: 16),
        Text(
          selectedCategory ?? 'Popular in Metro Manila',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        ...popularPlaces.map(
          (place) => _PlaceListTile(
            name: place.name,
            subtitle: place.subtitle,
            icon: Icons.place_outlined,
            onTap: () => onPopularTap(place),
          ),
        ),
      ],
    );
  }
}

class _PlaceListTile extends StatelessWidget {
  final String name;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _PlaceListTile({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 12,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: colorScheme.onPrimaryContainer, size: 22),
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
      trailing: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
      onTap: onTap,
    );
  }
}

class _SearchSkeleton extends StatelessWidget {
  const _SearchSkeleton();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 12,
                    width: 160,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.6,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SearchDropdown extends StatelessWidget {
  final List<PlaceResult> results;
  final ValueChanged<PlaceResult> onSelect;

  const _SearchDropdown({required this.results, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: results.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: 56, endIndent: 4),
      itemBuilder: (context, index) {
        final place = results[index];
        return ListTile(
          minVerticalPadding: 12,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.place_outlined,
            color: colorScheme.primary,
            size: 25,
          ),
          title: Text(
            place.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            place.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: colorScheme.onSurfaceVariant,
          ),
          onTap: () => onSelect(place),
        );
      },
    );
  }
}

class _SelectedPlacePreview extends StatelessWidget {
  final PlaceResult place;
  final VoidCallback onBack;
  final VoidCallback onPlanRoute;

  const _SelectedPlacePreview({
    required this.place,
    required this.onBack,
    required this.onPlanRoute,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.location_on_outlined,
                  color: colorScheme.onPrimaryContainer,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (place.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        place.subtitle,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'Selected destination',
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to results'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onPlanRoute,
            icon: const Icon(Icons.directions),
            label: const Text('Plan route'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchHintState extends StatelessWidget {
  final String message;

  const _SearchHintState({required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search, size: 36, color: colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  final String query;
  final VoidCallback onClear;

  const _NoResultsState({required this.query, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_searching,
                size: 40,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 14),
              Text(
                'No places found',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Try a nearby landmark or check the spelling of “$query”.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.close),
                label: const Text('Clear search'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoConnectionState extends StatelessWidget {
  final VoidCallback onRetry;
  const _NoConnectionState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, size: 40, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          const Text(
            "Couldn't load results",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Check your connection. Your search is still here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
