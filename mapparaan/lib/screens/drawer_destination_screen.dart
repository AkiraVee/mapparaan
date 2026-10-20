import 'package:flutter/material.dart';

import '../services/commuter_preference_service.dart';

import '../services/ai_assistant_service.dart';
import '../services/place_search_service.dart';
import '../services/saved_places_service.dart';
import '../services/trip_history_service.dart';
import 'search_location_screen.dart';
import 'auth_screen.dart';
import '../services/auth_service.dart';
import '../services/memory_pin_service.dart';

enum DrawerDestination {
  profile,
  savedPlaces,
  tripHistory,
  settings,
  helpSupport,
}

class DrawerDestinationScreen extends StatelessWidget {
  final DrawerDestination destination;

  const DrawerDestinationScreen({super.key, required this.destination});

  @override
  Widget build(BuildContext context) {
    final (title, icon) = switch (destination) {
      DrawerDestination.profile => ('My Profile', Icons.person_outline),
      DrawerDestination.savedPlaces => ('Saved Places', Icons.bookmark_border),
      DrawerDestination.tripHistory => ('Trip History', Icons.history),
      DrawerDestination.settings => ('Settings', Icons.settings_outlined),
      DrawerDestination.helpSupport => ('Help & Support', Icons.help_outline),
    };

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(title),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: switch (destination) {
            DrawerDestination.profile => _ProfilePage(icon: icon),
            DrawerDestination.savedPlaces => const _SavedPlacesPage(),
            DrawerDestination.tripHistory => const _TripHistoryPage(),
            DrawerDestination.settings => const _SettingsPage(),
            DrawerDestination.helpSupport => const _HelpSupportPage(),
          },
        ),
      ),
    );
  }
}

class _ProfilePage extends StatelessWidget {
  final IconData icon;

  const _ProfilePage({required this.icon});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AuthService.isLoggedIn,
      builder: (context, isLoggedIn, _) {
        final user = AuthService.currentUser;

        if (!isLoggedIn) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  child: Icon(
                    Icons.person_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Guest Commuter',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Sign in to upload memory pictures, save favorite locations, and customize your commute experience.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  icon: const Icon(Icons.login),
                  label: const Text('Sign In or Register'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AuthScreen()),
                    );
                  },
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 12),

              // 1. CENTERED AVATAR WITH EDIT BADGE
              Center(
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 3,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 48,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        child: Icon(
                          Icons.person,
                          size: 54,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.edit,
                          size: 14,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 2. CENTERED NAME AND EMAIL
              Text(
                user['name'] ?? 'Commuter User',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                user['email'] ?? 'commuter@example.com',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 24),

              // 3. ACTIVITY STATS ROW
              ValueListenableBuilder<List<MemoryPin>>(
                valueListenable: MemoryPinService.pins,
                builder: (context, pins, _) {
                  return FutureBuilder(
                    future: Future.wait([
                      SavedPlacesService.load(),
                      TripHistoryService.load(),
                    ]),
                    builder: (context, snapshot) {
                      final savedCount =
                          (snapshot.data?[0] as List?)?.length ?? 0;
                      final tripCount =
                          (snapshot.data?[1] as List?)?.length ?? 0;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _StatItem(
                              icon: Icons.photo_library_outlined,
                              value: '${pins.length}',
                              label: 'Memories',
                            ),
                            Container(
                              height: 30,
                              width: 1,
                              color: Colors.grey.withValues(alpha: 0.3),
                            ),
                            _StatItem(
                              icon: Icons.bookmark_border,
                              value: '$savedCount',
                              label: 'Saved Places',
                            ),
                            Container(
                              height: 30,
                              width: 1,
                              color: Colors.grey.withValues(alpha: 0.3),
                            ),
                            _StatItem(
                              icon: Icons.directions_transit_outlined,
                              value: '$tripCount',
                              label: 'Trips Taken',
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 28),

              // 4. UPLOADED PICTURES GALLERY SECTION
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Uploaded Location Memories',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  ValueListenableBuilder<List<MemoryPin>>(
                    valueListenable: MemoryPinService.pins,
                    builder: (context, pins, _) => Text(
                      '${pins.length} photos',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              ValueListenableBuilder<List<MemoryPin>>(
                valueListenable: MemoryPinService.pins,
                builder: (context, pins, _) {
                  if (pins.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.grey.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.add_a_photo_outlined,
                            size: 36,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'No pictures uploaded yet',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Visit a place and tap "Add Memory Photo" on the location details screen to save pictures here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.85,
                        ),
                    itemCount: pins.length,
                    itemBuilder: (context, index) {
                      final pin = pins[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Container(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  child: Center(
                                    child: Icon(
                                      Icons.image,
                                      size: 40,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pin.placeName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      pin.address,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 32),

              // 5. SIGN OUT BUTTON
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red[700],
                    side: BorderSide(color: Colors.red[200]!),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.logout),
                  label: const Text(
                    'Sign Out',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => AuthService.signOut(),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SavedPlacesPage extends StatefulWidget {
  const _SavedPlacesPage();

  @override
  State<_SavedPlacesPage> createState() => _SavedPlacesPageState();
}

class _SavedPlacesPageState extends State<_SavedPlacesPage> {
  late Future<List<SavedPlace>> _future;

  @override
  void initState() {
    super.initState();
    _future = SavedPlacesService.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SavedPlace>>(
      future: _future,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <SavedPlace>[];
        if (items.isEmpty) {
          return _EmptyState(
            icon: Icons.bookmark_border,
            title: 'No saved places yet',
            message: 'Save places you visit often to find them quickly.',
            actionLabel: 'Find a place',
            onAction: () async {
              final selection = await Navigator.of(context)
                  .push<SearchSelection>(
                    MaterialPageRoute<SearchSelection>(
                      builder: (_) => const SearchLocationScreen(),
                    ),
                  );
              if (context.mounted && selection != null) {
                Navigator.of(context).pop(selection.place);
              }
            },
          );
        }

        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final place = items[index];
            return ListTile(
              leading: Icon(
                Icons.place_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(place.name),
              subtitle: Text(
                place.subtitle.isEmpty ? 'Saved place' : place.subtitle,
              ),
              trailing: IconButton(
                icon: Icon(
                  Icons.bookmark_remove_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                tooltip: 'Remove from saved',
                onPressed: () async {
                  await SavedPlacesService.toggle(place);
                  if (!context.mounted) return;
                  setState(() {
                    _future = SavedPlacesService.load();
                  });
                },
              ),
              onTap: () {
                Navigator.of(context).pop(
                  PlaceResult(
                    name: place.name,
                    subtitle: place.subtitle,
                    coordinates: place.coordinates,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _TripHistoryPage extends StatefulWidget {
  const _TripHistoryPage();

  @override
  State<_TripHistoryPage> createState() => _TripHistoryPageState();
}

class _TripHistoryPageState extends State<_TripHistoryPage> {
  late Future<List<TripHistoryEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = TripHistoryService.load();
  }

  void _refresh() {
    setState(() {
      _future = TripHistoryService.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TripHistoryEntry>>(
      future: _future,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <TripHistoryEntry>[];
        if (items.isEmpty) {
          return const _EmptyState(
            icon: Icons.route_outlined,
            title: 'Your trips will show up here',
            message:
                'Once you plan a route, your recent trips will appear here.',
          );
        }

        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${items.length} ${items.length == 1 ? 'trip' : 'trips'} recorded',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('Clear all'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
                  onPressed: () async {
                    await TripHistoryService.clear();
                    if (context.mounted) _refresh();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final trip = items[items.length - 1 - index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer,
                      child: Icon(
                        Icons.directions_transit,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      '${trip.origin} → ${trip.destination}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${trip.routeSummary ?? 'Route'} • ${trip.durationMinutes} min • ₱${trip.fareEstimate.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          trip.etaText,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            size: 18,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                          onPressed: () async {
                            await TripHistoryService.deleteEntry(trip.id);
                            if (context.mounted) _refresh();
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage();

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  CommuterPreferences _prefs = const CommuterPreferences();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final loaded = await CommuterPreferencesService.load();
    if (!mounted) return;
    setState(() {
      _prefs = loaded;
      _isLoading = false;
    });
  }

  Future<void> _updatePreferences(CommuterPreferences newPrefs) async {
    setState(() => _prefs = newPrefs);
    await CommuterPreferencesService.save(newPrefs);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final activeColor = _prefs.colorPalette.primary;

    return ListView(
      children: [
        // ── 1. THEME MODE SELECTOR ──
        const Text(
          'Appearance & Theme Mode',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SegmentedButton<AppThemeMode>(
          segments: const [
            ButtonSegment(
              value: AppThemeMode.system,
              label: Text('System'),
              icon: Icon(Icons.settings_suggest_outlined),
            ),
            ButtonSegment(
              value: AppThemeMode.light,
              label: Text('Light'),
              icon: Icon(Icons.wb_sunny_outlined),
            ),
            ButtonSegment(
              value: AppThemeMode.dark,
              label: Text('Dark'),
              icon: Icon(Icons.dark_mode_outlined),
            ),
          ],
          selected: {_prefs.themeMode},
          onSelectionChanged: (set) {
            _updatePreferences(_prefs.copyWith(themeMode: set.first));
          },
        ),

        const Divider(height: 32),

        // ── 2. MANILA LANDMARK COLOR PALETTES ──
        const Text(
          'Color Palette Accent',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Personalize main branding inspired by famous Manila landmarks.',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: ColorPalette.values.map((palette) {
            final isSelected = _prefs.colorPalette == palette;
            return ChoiceChip(
              avatar: CircleAvatar(
                backgroundColor: palette.primary,
                radius: 10,
              ),
              label: Text(
                palette.label,
                style: TextStyle(
                  // Keep selected chip text legible on its tinted background.
                  color: isSelected
                      ? palette.onContainer
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              selectedColor: palette.container,
              checkmarkColor: palette.onContainer,
              backgroundColor: Theme.of(context).cardColor,
              onSelected: (_) {
                _updatePreferences(_prefs.copyWith(colorPalette: palette));
              },
            );
          }).toList(),
        ),

        const Divider(height: 32),

        // ── 3. DISPLAY CONTROLS ──
        const Text(
          'Display & Map Controls',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('High-Contrast Map Shading'),
          subtitle: const Text(
            'Enhances baseline legibility for visual clarity',
          ),
          value: _prefs.highContrastMap,
          activeTrackColor: activeColor,
          onChanged: (val) =>
              _updatePreferences(_prefs.copyWith(highContrastMap: val)),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Compact Sheet View'),
          subtitle: const Text(
            'Reduces bottom sheet height for maximum map space',
          ),
          value: _prefs.compactUi,
          activeTrackColor: activeColor,
          onChanged: (val) =>
              _updatePreferences(_prefs.copyWith(compactUi: val)),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Metric Units'),
          subtitle: const Text('Display distances in meters and kilometers'),
          value: _prefs.useMetricUnits,
          activeTrackColor: activeColor,
          onChanged: (val) =>
              _updatePreferences(_prefs.copyWith(useMetricUnits: val)),
        ),

        const Divider(height: 32),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.privacy_tip_outlined, color: activeColor),
          title: const Text('Privacy & Location Access'),
          subtitle: const Text(
            'Location permission is used strictly to calculate live routes and center the map on request.',
          ),
        ),
      ],
    );
  }
}

class _HelpSupportPage extends StatelessWidget {
  const _HelpSupportPage();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text(
          'How can we help?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 8),
        Text(
          'Quick answers about using Mapparaan.',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: 16),
        _HelpQuestion(
          question: 'How do I find a place?',
          answer: 'Tap the search bar on the map and enter a place or address.',
        ),
        _HelpQuestion(
          question: 'How does location access work?',
          answer: 'Mapparaan requests your location only when it needs to center the map on you.',
        ),
        _HelpQuestion(
          question: 'Can I plan a transit route?',
          answer: 'Transit route planning is available as a front-end MVP and is still separate from the production backend.',
        ),
      ],
    );
  }
}

class _HelpQuestion extends StatelessWidget {
  final String question;
  final String answer;

  const _HelpQuestion({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(question, style: const TextStyle(fontSize: 15)),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              answer,
              style: TextStyle(
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.search),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
