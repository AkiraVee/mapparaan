import 'package:flutter/material.dart';
// TODO: re-enable once the Google Maps API key is set up.
// import 'package:google_maps_flutter/google_maps_flutter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();

  void openMenu() {
    Scaffold.of(context).openDrawer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Frame 4 (side menu) will hook into this drawer later.
      drawer: const Drawer(
        child: SafeArea(
          child: Center(child: Text('Menu placeholder')),
        ),
      ),
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

              // Top bar: hamburger menu + location button
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _CircleIconButton(
                        icon: Icons.menu,
                        onTap: () => Scaffold.of(context).openDrawer(),
                      ),
                      _CircleIconButton(
                        icon: Icons.my_location,
                        onTap: () {
                          // TODO: recenter map on user location
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom search / chat bar
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: _AskMapparaanBar(controller: _searchController),
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

/// Small circular button used for the top-left menu and top-right
/// location icons.
class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.black87),
        ),
      ),
    );
  }
}

/// The pill-shaped "Ask MapParaan" search/voice bar pinned to the
/// bottom of the screen.
class _AskMapparaanBar extends StatelessWidget {
  final TextEditingController controller;

  const _AskMapparaanBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const SizedBox(width: 8),
            const Icon(Icons.search, color: Colors.black45),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Ask MapParaan',
                  border: InputBorder.none,
                ),
                onSubmitted: (query) {
                  // TODO: hand query off to chatbot/NLU layer
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.mic, color: Colors.black87),
              onPressed: () {
                // TODO: hook up voice input
              },
            ),
          ],
        ),
      ),
    );
  }
}