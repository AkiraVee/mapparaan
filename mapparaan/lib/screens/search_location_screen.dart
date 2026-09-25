import 'package:flutter/material.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/ask_mapparaan_bar.dart';

class SearchLocationScreen extends StatefulWidget {
  const SearchLocationScreen({super.key});

  @override
  State<SearchLocationScreen> createState() => _SearchLocationScreenState();
}

class _SearchLocationScreenState extends State<SearchLocationScreen> {
  final TextEditingController _topSearchController = TextEditingController();
  final TextEditingController _bottomAskController = TextEditingController();

  @override
  void dispose() {
    _topSearchController.dispose();
    _bottomAskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
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

          // Top bar: "Search here" input + location button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: AskMapparaanBar(
                      controller: _topSearchController,
                      hintText: 'Search here',
                      autofocus: true,
                      leadingIcon: Icons.search,
                      onSubmitted: (query) {
                        // TODO: run place search / autocomplete
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
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

          // TODO: search results / autocomplete suggestions list goes here,
          // between the top search bar and the bottom bar.

          // Bottom "Ask MapParaan" bar (kept consistent with Frame 1).
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: AskMapparaanBar(controller: _bottomAskController),
              ),
            ),
          ),
        ],
      ),
    );
  }
}