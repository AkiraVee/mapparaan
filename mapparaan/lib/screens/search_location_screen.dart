import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../services/ai_assistant_service.dart';
import '../services/place_search_service.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/mapparaan_tile_layer.dart';

class SearchLocationScreen extends StatefulWidget {
  final String? initialQuery;
  final bool showMap;
  final PlaceSearch searchPlaces;

  const SearchLocationScreen({
    super.key,
    this.initialQuery,
    this.showMap = true,
    this.searchPlaces = PlaceSearchService.search,
  });

  @override
  State<SearchLocationScreen> createState() => _SearchLocationScreenState();
}

class _SearchLocationScreenState extends State<SearchLocationScreen> {
  final TextEditingController _topSearchController = TextEditingController();
  final FocusNode _topSearchFocusNode = FocusNode();
  final MapController _mapController = MapController();

  bool _hasConnectionError = false;
  bool _isSearching = false;
  final bool _isAiResolving = false;

  LatLng? _userLocation;
  List<PlaceResult> _searchResults = [];
  Timer? _debounce;
  String? _selectedCategory;

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
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition();
      final userLatLng = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => _userLocation = userLatLng);
      _mapController.move(userLatLng, 14.0);
    } catch (_) {}
  }

  Future<void> _runSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) {
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _hasConnectionError = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _hasConnectionError = false;
    });

    try {
      final results = await widget.searchPlaces(trimmed);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searchResults = const [];
        _isSearching = false;
        _hasConnectionError = true;
      });
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (_selectedCategory != null) {
      setState(() => _selectedCategory = null);
    }

    _debounce = Timer(const Duration(milliseconds: 700), () {
      _runSearch(query);
    });
  }

  void _onChipTap(String chip) {
    setState(() {
      _selectedCategory = _selectedCategory == chip ? null : chip;
      _searchResults = [];
      _isSearching = false;
      _hasConnectionError = false;
    });
  }

  void _onPopularTap(_PopularPlace popular) {
    final query = popular.name;
    _topSearchController.text = query;
    _topSearchController.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    setState(() => _selectedCategory = null);
    _runSearch(query);
  }

  void _selectPlace(PlaceResult place) {
    Navigator.of(context).pop(
      SearchSelection(
        place: place,
        resolution: AiQueryResolution.fromQuery(
          _topSearchController.text.trim().isEmpty
              ? place.name
              : _topSearchController.text.trim(),
        ),
      ),
    );
  }

  void _retry() {
    setState(() => _hasConnectionError = false);
    _runSearch(_topSearchController.text);
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

    return Scaffold(
      body: Stack(
        children: [
          // MAP (blocked from receiving any taps)
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
            )
          else
            Positioned.fill(child: ColoredBox(color: colorScheme.surface)),

          // FULL UI OVERLAY (always on top, always receives taps)
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  // Top bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        CircleIconButton(
                          icon: Icons.arrow_back,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Material(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(28),
                            elevation: 4,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(width: 4),
                                  InkWell(
                                    customBorder: const CircleBorder(),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Icon(
                                        Icons.search,
                                        color: Theme.of(context).iconTheme.color
                                            ?.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: TextField(
                                      controller: _topSearchController,
                                      focusNode: _topSearchFocusNode,
                                      autofocus: true,
                                      textInputAction: TextInputAction.search,
                                      decoration: const InputDecoration(
                                        hintText: 'Search here',
                                        border: InputBorder.none,
                                      ),
                                      onChanged: _onSearchChanged,
                                      onSubmitted: _onSearchChanged,
                                      onTapOutside: (_) =>
                                          FocusScope.of(context).unfocus(),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Search',
                                    icon: Icon(
                                      Icons.send,
                                      color: Theme.of(context).iconTheme.color,
                                    ),
                                    onPressed: () {
                                      final value = _topSearchController.text
                                          .trim();
                                      if (value.isNotEmpty) {
                                        _onSearchChanged(value);
                                      }
                                      FocusScope.of(context).unfocus();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Panel — always visible
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Material(
                        color: colorScheme.surface,
                        elevation: 8,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: _hasConnectionError
                            ? _NoConnectionState(onRetry: _retry)
                            : (_isAiResolving || _isSearching)
                            ? const _SearchSkeleton()
                            : _searchResults.isNotEmpty
                            ? _SearchDropdown(
                                results: _searchResults,
                                onSelect: _selectPlace,
                              )
                            : _EmptySearchState(
                                popularPlaces: _displayedPlaces,
                                chips: _quickChips,
                                selectedCategory: _selectedCategory,
                                onPopularTap: _onPopularTap,
                                onChipTap: _onChipTap,
                              ),
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
  final ValueChanged<_PopularPlace> onPopularTap;
  final ValueChanged<String> onChipTap;

  const _EmptySearchState({
    required this.popularPlaces,
    required this.chips,
    required this.selectedCategory,
    required this.onPopularTap,
    required this.onChipTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Text(
          'Quick search',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: chips.map((chip) {
            final isSelected = selectedCategory == chip;
            return FilterChip(
              label: Text(chip),
              selected: isSelected,
              onSelected: (_) {
                onChipTap(chip);
              },
              selectedColor: colorScheme.primaryContainer,
              checkmarkColor: colorScheme.onPrimaryContainer,
              backgroundColor: colorScheme.surfaceContainerHighest,
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        Text(
          selectedCategory ?? 'Popular in Metro Manila',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...popularPlaces.map((place) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.place_outlined,
                color: colorScheme.onPrimaryContainer,
                size: 22,
              ),
            ),
            title: Text(
              place.name,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              place.subtitle,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            onTap: () {
              onPopularTap(place);
            },
          );
        }),
      ],
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: results.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, index) {
        final place = results[index];
        return ListTile(
          leading: Icon(
            Icons.place_outlined,
            color: colorScheme.onSurfaceVariant,
          ),
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
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          onTap: () => onSelect(place),
        );
      },
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
