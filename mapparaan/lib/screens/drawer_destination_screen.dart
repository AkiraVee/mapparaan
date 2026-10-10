import 'package:flutter/material.dart';

import '../services/ai_assistant_service.dart';
import '../services/place_search_service.dart';
import '../services/saved_places_service.dart';
import '../services/trip_history_service.dart';
import 'search_location_screen.dart';

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
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F9F8),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        CircleAvatar(
          radius: 36,
          backgroundColor: const Color(0xFFE0F2F1),
          child: Icon(icon, size: 34, color: const Color(0xFF00695C)),
        ),
        const SizedBox(height: 20),
        const Text(
          'Guest commuter',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your profile and travel preferences will live here. Sign-in is not available yet.',
          style: TextStyle(fontSize: 15, height: 1.45, color: Colors.black54),
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
              final selection = await Navigator.of(context).push<SearchSelection>(
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
              leading: const Icon(
                Icons.place_outlined,
                color: Color(0xFF00695C),
              ),
              title: Text(place.name),
              subtitle: Text(
                place.subtitle.isEmpty ? 'Saved place' : place.subtitle,
              ),
              trailing: IconButton(
                icon: const Icon(
                  Icons.bookmark_remove_outlined,
                  color: Colors.black45,
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
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('Clear all'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red[700],
                  ),
                  onPressed: () async {
                    await TripHistoryService.clear();
                    if (!context.mounted) return;
                    setState(() {
                      _future = TripHistoryService.load();
                    });
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
                    leading: const CircleAvatar(
                      radius: 20,
                      backgroundColor: Color(0xFFE0F2F1),
                      child: Icon(
                        Icons.directions_transit,
                        color: Color(0xFF00695C),
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
                    trailing: Text(
                      trip.etaText,
                      style: const TextStyle(fontSize: 12, color: Colors.black45),
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
  bool _useMetricUnits = true;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const Text(
          'Travel preferences',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Metric units'),
          subtitle: const Text('Show distances in kilometers'),
          value: _useMetricUnits,
          activeTrackColor: const Color(0xFF00695C),
          onChanged: (value) => setState(() => _useMetricUnits = value),
        ),
        const Divider(height: 24),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.privacy_tip_outlined),
          title: Text('Privacy'),
          subtitle: Text('Location is used to center the map when requested.'),
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
      children: const [
        Text(
          'How can we help?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 8),
        Text(
          'Quick answers about using Mapparaan.',
          style: TextStyle(fontSize: 14, color: Colors.black54),
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
              style: const TextStyle(height: 1.4, color: Colors.black54),
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
            Icon(icon, size: 52, color: const Color(0xFF00695C)),
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
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: Colors.black54,
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.search),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00695C),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
