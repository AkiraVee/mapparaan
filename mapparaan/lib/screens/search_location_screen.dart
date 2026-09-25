import 'package:flutter/material.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/ask_mapparaan_bar.dart';
import '../widgets/mapparaan_drawer.dart';
import 'location_details_screen.dart';

/// A single autocomplete suggestion shown in the search dropdown.
/// TODO: replace with real results from a Places/geocoding API once
/// the search is wired to one.
class _SearchSuggestion {
  final String name;
  final String subtitle;

  const _SearchSuggestion(this.name, this.subtitle);
}

const List<_SearchSuggestion> _mockSuggestions = [
  _SearchSuggestion('Universidad De Manila', 'Mehan Garden, Manila'),
  _SearchSuggestion('University of Santo Tomas', 'España Blvd, Manila'),
  _SearchSuggestion('Rizal Memorial Track and Football Stadium',
      'Pablo Ocampo Sr. St, Malate, Manila'),
  _SearchSuggestion('SM Manila', 'Concepcion Aguila St, Manila'),
  _SearchSuggestion('Manila City Hall', 'Padre Burgos Ave, Manila'),
  _SearchSuggestion('Robinsons Place Manila', 'Pedro Gil St, Manila'),
];

class SearchLocationScreen extends StatefulWidget {
  const SearchLocationScreen({super.key});

  @override
  State<SearchLocationScreen> createState() => _SearchLocationScreenState();
}

class _SearchLocationScreenState extends State<SearchLocationScreen> {
  final TextEditingController _topSearchController = TextEditingController();
  final TextEditingController _bottomAskController = TextEditingController();
  final FocusNode _topSearchFocusNode = FocusNode();

  bool _isSearchFocused = false;

  // TODO: replace this manual flag with real connectivity detection
  // (e.g. via the `connectivity_plus` package) once the search is
  // wired to an actual API. For now this lets us preview/test Frame 7
  // (No Internet Connection) by flipping it to true.
  bool _hasConnectionError = false;

  @override
  void initState() {
    super.initState();
    _topSearchFocusNode.addListener(() {
      setState(() => _isSearchFocused = _topSearchFocusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _topSearchController.dispose();
    _bottomAskController.dispose();
    _topSearchFocusNode.dispose();
    super.dispose();
  }

  void _selectSuggestion(_SearchSuggestion suggestion) {
    _topSearchFocusNode.unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            LocationDetailsScreen(placeName: suggestion.name),
      ),
    );
  }

  void _retry() {
    // TODO: re-run the actual search/connectivity check here.
    setState(() => _hasConnectionError = false);
  }

  @override
  Widget build(BuildContext context) {
    // Dropdown area is shown whenever the search field is focused.
    // TODO: once a real API is wired up, only show it when there are
    // actual results (and show an empty/no-results state otherwise).
    final showDropdownArea = _isSearchFocused;

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

              // Top bar + dropdown/error area, grouped in a column so
              // it sits directly beneath the search bar.
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),

                      // Top bar: switches between
                      // [menu] [search bar] [location]  <- not focused
                      // [back] [search bar, full width]  <- focused
                      Row(
                        children: [
                          CircleIconButton(
                            icon: _isSearchFocused
                                ? Icons.arrow_back
                                : Icons.menu,
                            onTap: () {
                              if (_isSearchFocused) {
                                _topSearchFocusNode.unfocus();
                              } else {
                                Scaffold.of(context).openDrawer();
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: AskMapparaanBar(
                              controller: _topSearchController,
                              focusNode: _topSearchFocusNode,
                              hintText: 'Search here',
                              leadingIcon: Icons.search,
                              onSubmitted: (query) {
                                // TODO: run place search / autocomplete
                              },
                            ),
                          ),
                          if (!_isSearchFocused) ...[
                            const SizedBox(width: 8),
                            CircleIconButton(
                              icon: Icons.my_location,
                              onTap: () {
                                // TODO: recenter map on user location
                              },
                            ),
                          ],
                        ],
                      ),

                      // Dropdown area: either results, or the
                      // no-connection state (Frame 7).
                      if (showDropdownArea) ...[
                        const SizedBox(height: 8),
                        Expanded(
                          child: _hasConnectionError
                              ? _NoConnectionState(onRetry: _retry)
                              : _SearchDropdown(
                                  suggestions: _mockSuggestions,
                                  onSelect: _selectSuggestion,
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Bottom "Ask MapParaan" bar (kept consistent with Frame 1).
              // Hidden while the dropdown/error area is open so it
              // doesn't compete with it for the user's attention.
              if (!showDropdownArea)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child:
                          AskMapparaanBar(controller: _bottomAskController),
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

class _SearchDropdown extends StatelessWidget {
  final List<_SearchSuggestion> suggestions;
  final ValueChanged<_SearchSuggestion> onSelect;

  const _SearchDropdown({
    required this.suggestions,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: suggestions.length,
        separatorBuilder: (context, index) => const Divider(
          height: 1,
          indent: 16,
          endIndent: 16,
        ),
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          return ListTile(
            leading: const Icon(Icons.place_outlined, color: Colors.black54),
            title: Text(
              suggestion.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15),
            ),
            subtitle: Text(
              suggestion.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            onTap: () => onSelect(suggestion),
          );
        },
      ),
    );
  }
}

/// Frame 7 — shown in place of the dropdown when results can't load
/// due to a connectivity issue.
class _NoConnectionState extends StatelessWidget {
  final VoidCallback onRetry;

  const _NoConnectionState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 40, color: Colors.black45),
            const SizedBox(height: 16),
            const Text(
              "Couldn't load results",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check your connection. Your search is still here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00695C),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}