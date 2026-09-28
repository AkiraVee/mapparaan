import 'package:flutter/material.dart';

import '../screens/drawer_destination_screen.dart';

/// The side menu (drawer) shown across Mapparaan's screens.
class MapparaanDrawer extends StatelessWidget {
  const MapparaanDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 20),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 23,
                    backgroundColor: Color(0xFFE0F2F1),
                    child: Icon(Icons.alt_route, color: Color(0xFF00695C)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mapparaan',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Your commute, simplified',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close navigation menu',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Text(
                      'YOUR ACCOUNT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  _MenuItem(
                    icon: Icons.person_outline,
                    label: 'My Profile',
                    onTap: () =>
                        _openDestination(context, DrawerDestination.profile),
                  ),
                  _MenuItem(
                    icon: Icons.bookmark_border,
                    label: 'Saved Places',
                    onTap: () => _openDestination(
                      context,
                      DrawerDestination.savedPlaces,
                    ),
                  ),
                  _MenuItem(
                    icon: Icons.history,
                    label: 'Trip History',
                    onTap: () => _openDestination(
                      context,
                      DrawerDestination.tripHistory,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 20, 12, 8),
                    child: Text(
                      'PREFERENCES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  _MenuItem(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    onTap: () =>
                        _openDestination(context, DrawerDestination.settings),
                  ),
                  const SizedBox(height: 20),
                  _HelpCard(
                    onTap: () => _openDestination(
                      context,
                      DrawerDestination.helpSupport,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDestination(BuildContext context, DrawerDestination destination) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => DrawerDestinationScreen(destination: destination),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Icon(icon, color: const Color(0xFF00695C)),
      title: Text(label, style: const TextStyle(fontSize: 15)),
      trailing: const Icon(Icons.chevron_right, color: Colors.black38),
      onTap: onTap,
    );
  }
}

class _HelpCard extends StatelessWidget {
  final VoidCallback onTap;

  const _HelpCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE0F2F1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: const ListTile(
          leading: Icon(Icons.help_outline, color: Color(0xFF00695C)),
          title: Text(
            'Help & Support',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          trailing: Icon(Icons.chevron_right, color: Color(0xFF00695C)),
        ),
      ),
    );
  }
}
