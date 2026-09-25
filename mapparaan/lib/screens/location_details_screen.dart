import 'package:flutter/material.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/mapparaan_drawer.dart';

/// Route preference the user can pick from the location details sheet.
/// Mirrors the "cheapest / fastest / fewest transfers" preference the
/// chatbot/NLU layer also parses from natural-language queries.
enum RoutePreference { fastest, cheapest, fewestTransfers }

class LocationDetailsScreen extends StatefulWidget {
  final String placeName;

  const LocationDetailsScreen({
    super.key,
    this.placeName = 'Universidad De Manila',
  });

  @override
  State<LocationDetailsScreen> createState() => _LocationDetailsScreenState();
}

class _LocationDetailsScreenState extends State<LocationDetailsScreen> {
  bool _isSaved = false;

  void _selectPreference(RoutePreference preference) {
    // TODO: hand this off to the routing engine (OTP/OSRM/Google Routes)
    // along with the selected place, to generate the actual route.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const MapparaanDrawer(),
      body: Builder(
        builder: (context) {
          return Stack(
            children: [
              // Full-screen map placeholder (base layer).
              // TODO: replace with GoogleMap widget once the API key is set up.
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

              // Top bar: hamburger menu + location button (same as Frame 1)
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
                          // TODO: recenter map on user location
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom sheet: selected place details + route preference
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  top: false,
                  child: _PlaceDetailsSheet(
                    placeName: widget.placeName,
                    isSaved: _isSaved,
                    onSaveToggle: () => setState(() => _isSaved = !_isSaved),
                    onShare: () {
                      // TODO: hook up native share sheet
                    },
                    onClose: () => Navigator.of(context).maybePop(),
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
  final VoidCallback onSaveToggle;
  final VoidCallback onShare;
  final VoidCallback onClose;
  final ValueChanged<RoutePreference> onPreferenceSelected;

  const _PlaceDetailsSheet({
    required this.placeName,
    required this.isSaved,
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
          // Drag handle
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

          // Place name + save / share / close icons
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

          // Route preference buttons: fastest / cheapest / fewest transfers
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00695C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: () =>
                      onPreferenceSelected(RoutePreference.fastest),
                  child: const Text('Fastest'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFB2EBF2),
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: () =>
                      onPreferenceSelected(RoutePreference.cheapest),
                  child: const Text('Cheapest'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFE0F7FA),
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: () =>
                      onPreferenceSelected(RoutePreference.fewestTransfers),
                  child: const Text(
                    'Fewest\nTransfers',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}