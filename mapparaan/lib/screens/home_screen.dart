import 'package:flutter/material.dart';
// TODO: re-enable once the Google Maps API key is set up.
// import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/ask_mapparaan_bar.dart';
import '../widgets/mapparaan_drawer.dart';
import 'search_location_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();

  void _goToSearchScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const SearchLocationScreen()),
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

              // Bottom search / chat bar.
              // Tapping it opens Frame 2 (Search Location).
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: GestureDetector(
                      onTap: _goToSearchScreen,
                      child: AbsorbPointer(
                        // Absorb taps on the text field itself so the
                        // whole bar just navigates to the search screen,
                        // where real typing happens.
                        child: AskMapparaanBar(controller: _searchController),
                      ),
                    ),
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