import 'package:flutter/material.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/mapparaan_drawer.dart';

class LocationDisabledScreen extends StatelessWidget {
  const LocationDisabledScreen({super.key});

  void _enableLocation(BuildContext context) {
    // TODO: request location permission (e.g. via the `geolocator` or
    // `permission_handler` package) and, once granted, recenter the
    // map on the user's actual position.
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
                        onTap: () => _enableLocation(context),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom sheet: location disabled prompt
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  top: false,
                  child: _LocationDisabledSheet(
                    onEnableLocation: () => _enableLocation(context),
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

class _LocationDisabledSheet extends StatelessWidget {
  final VoidCallback onEnableLocation;

  const _LocationDisabledSheet({required this.onEnableLocation});

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

          const Text(
            'Location is turned off',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),

          const SizedBox(height: 8),

          const Text(
            'Enable location to see where you are and find nearby '
            'places faster.',
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00695C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onPressed: onEnableLocation,
              child: const Text('Enable location'),
            ),
          ),
        ],
      ),
    );
  }
}