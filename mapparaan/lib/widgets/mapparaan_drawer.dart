import 'package:flutter/material.dart';

import '../screens/drawer_destination_screen.dart';
import '../services/place_search_service.dart';

class MapparaanDrawer extends StatelessWidget {
  final ValueChanged<PlaceResult>? onPlaceSelected;

  const MapparaanDrawer({super.key, this.onPlaceSelected});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Drawer(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Icon(
                      Icons.alt_route,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mapparaan',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Your commute, simplified',
                          style: TextStyle(
                            fontSize: 12,
                            color: onSurface.withValues(alpha: 0.6),
                          ),
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
            Divider(height: 1, color: Theme.of(context).dividerColor),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Text(
                      'YOUR ACCOUNT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: onSurface.withValues(alpha: 0.5),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
                    child: Text(
                      'PREFERENCES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: onSurface.withValues(alpha: 0.5),
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

  Future<void> _openDestination(
    BuildContext context,
    DrawerDestination destination,
  ) async {
    final navigator = Navigator.of(context);
    navigator.pop();
    final selected = await navigator.push<PlaceResult>(
      MaterialPageRoute<PlaceResult>(
        builder: (_) => DrawerDestinationScreen(destination: destination),
      ),
    );
    if (selected != null) {
      onPlaceSelected?.call(selected);
    }
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
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label, style: const TextStyle(fontSize: 15)),
      trailing: Icon(
        Icons.chevron_right,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
      ),
      onTap: onTap,
    );
  }
}

class _HelpCard extends StatelessWidget {
  final VoidCallback onTap;

  const _HelpCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ListTile(
          leading: Icon(Icons.help_outline, color: scheme.primary),
          title: Text(
            'Help & Support',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
          trailing: Icon(Icons.chevron_right, color: scheme.primary),
        ),
      ),
    );
  }
}
