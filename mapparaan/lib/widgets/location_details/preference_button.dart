import 'package:flutter/material.dart';

/// Styled button used for selecting transit route preferences (Fastest, Cheapest, Fewest Transfers).
class PreferenceButton extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onPressed;

  const PreferenceButton({
    super.key,
    required this.label,
    required this.active,
    required this.accent,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = active ? colorScheme.onPrimary : colorScheme.onSurface;
    final background = active ? accent : colorScheme.surfaceContainerHighest;

    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: active ? 2 : 0,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

