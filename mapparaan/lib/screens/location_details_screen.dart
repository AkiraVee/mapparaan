import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../services/ai_assistant_service.dart';
import '../services/place_search_service.dart';
import '../services/route_planner_service.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/mapparaan_drawer.dart';

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
  LatLng get resolvedDestination =>
      place?.coordinates ?? destinationCoordinates ?? const LatLng(14.5995, 120.9842);

  @override
  State<LocationDetailsScreen> createState() => _LocationDetailsScreenState();
}

class _LocationDetailsScreenState extends State<LocationDetailsScreen> {
  bool _isSaved = false;
  RoutePreference _selectedPreference = RoutePreference.fastest;
  List<RouteOption> _routeOptions = const [];

  @override
  void initState() {
    super.initState();
    _selectedPreference = widget.initialPreference;
    _refreshRouteOptions();
  }

  void _refreshRouteOptions() {
    final destination = widget.resolvedDestination;
    final userLocation = widget.userLocation ?? const LatLng(14.5943, 120.9721);

    setState(() {
      _routeOptions = RoutePlannerService.generateRouteOptions(
        destination: destination,
        userLocation: userLocation,
        preference: _selectedPreference,
      );
    });
  }

  void _selectPreference(RoutePreference preference) {
    setState(() {
      _selectedPreference = preference;
    });
    _refreshRouteOptions();
  }

  Future<void> _handleShare() async {
    final text = 'Mapparaan route to ${widget.resolvedPlaceName}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Route summary copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const MapparaanDrawer(),
      body: Builder(
        builder: (context) {
          return Stack(
            children: [
              Container(
                color: const Color(0xFFE0E0E0),
                width: double.infinity,
                height: double.infinity,
                child: const Center(
                  child: Text(
                    'Map goes here',
                    style: TextStyle(color: Colors.black45, fontSize: 16),
                  ),
                ),
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
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Centering on your location')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
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
                    onSaveToggle: () => setState(() => _isSaved = !_isSaved),
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