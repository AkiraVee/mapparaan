import 'package:flutter/material.dart';

/// The side menu (drawer) shown across Mapparaan's screens.
/// Matches Frame 4 of the wireframe: a back arrow, a set of
/// navigation items, and a larger card at the bottom.
class MapparaanDrawer extends StatelessWidget {
  const MapparaanDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back arrow to close the menu
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),

              const SizedBox(height: 8),

              _MenuItem(
                icon: Icons.person_outline,
                label: 'My Profile',
                onTap: () {
                  // TODO: navigate to profile screen
                },
              ),
              _MenuItem(
                icon: Icons.bookmark_border,
                label: 'Saved Places',
                onTap: () {
                  // TODO: navigate to saved places screen
                },
              ),
              _MenuItem(
                icon: Icons.history,
                label: 'Trip History',
                onTap: () {
                  // TODO: navigate to trip history screen
                },
              ),
              _MenuItem(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () {
                  // TODO: navigate to settings screen
                },
              ),

              const Spacer(),

              // Larger card at the bottom (help & support)
              _HelpCard(
                onTap: () {
                  // TODO: navigate to help & support screen
                },
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
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
    return Material(
      color: const Color(0xFFF0F0F0),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          width: double.infinity,
          child: Row(
            children: [
              Icon(icon, color: Colors.black87),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(fontSize: 15, color: Colors.black87),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpCard extends StatelessWidget {
  final VoidCallback onTap;

  const _HelpCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF0F0F0),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          child: const Row(
            children: [
              Icon(Icons.help_outline, color: Colors.black87),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Help & Support',
                  style: TextStyle(fontSize: 15, color: Colors.black87),
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.black45),
            ],
          ),
        ),
      ),
    );
  }
}