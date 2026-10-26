import 'package:flutter/material.dart';

/// Small circular button used for map overlay icons
/// (menu, back, location, etc.) across Mapparaan's screens.
class CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = SizedBox.square(
      dimension: 48,
      child: Material(
        color: Theme.of(context).cardColor,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Icon(icon, color: Theme.of(context).iconTheme.color),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
