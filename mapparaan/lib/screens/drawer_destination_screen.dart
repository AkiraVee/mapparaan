import 'package:flutter/material.dart';

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

class _SavedPlacesPage extends StatelessWidget {
  const _SavedPlacesPage();

  @override
  Widget build(BuildContext context) {
    return _EmptyState(
      icon: Icons.bookmark_border,
      title: 'No saved places yet',
      message: 'Save places you visit often to find them quickly. Saved places will appear here.',
      actionLabel: 'Find a place',
      onAction: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SearchLocationScreen()),
      ),
    );
  }
}

class _TripHistoryPage extends StatelessWidget {
  const _TripHistoryPage();

  @override
  Widget build(BuildContext context) {
    return _EmptyState(
      icon: Icons.route_outlined,
      title: 'Your trips will show up here',
      message: 'Once trip planning and history are available, you can review your past commutes here.',
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
          answer: 'Transit route planning is being developed and is not available yet.',
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
