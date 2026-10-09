import 'package:flutter/material.dart';

/// Reusable pill-shaped search input bar across Mapparaan screens.
class AskMapparaanBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool autofocus;
  final bool readOnly; // Read-only flag when used as a button to trigger navigation
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap; // Callback when the search bar field is tapped
  final VoidCallback? onMicTap;
  final IconData leadingIcon;
  final VoidCallback? onLeadingTap;
  final FocusNode? focusNode;

  const AskMapparaanBar({
    super.key,
    required this.controller,
    this.hintText = 'Ask MapParaan',
    this.autofocus = false,
    this.readOnly = false, // Defaults to editable text field
    this.onSubmitted,
    this.onChanged,
    this.onTap,
    this.onMicTap,
    this.leadingIcon = Icons.search,
    this.onLeadingTap,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    // Material wrapper provides background color and rounded elevation
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const SizedBox(width: 4),
            // Leading Icon (Magnifying glass search icon)
            InkWell(
              onTap: onLeadingTap ?? onTap,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(leadingIcon, color: Colors.black45),
              ),
            ),
            const SizedBox(width: 4),
            // Search Text Input Field
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: autofocus,
                readOnly: readOnly, // Prevents soft keyboard when readOnly is true
                onTap: onTap, // Triggers navigation when tapped
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: hintText,
                  border: InputBorder.none,
                ),
                onSubmitted: onSubmitted,
                onChanged: onChanged,
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
              ),
            ),
            // Trailing Action Button (Send Arrow or Microphone)
            IconButton(
              tooltip: onSubmitted == null ? 'Voice search' : 'Search',
              icon: Icon(
                onSubmitted == null ? Icons.mic : Icons.send,
                color: Colors.black87,
              ),
              onPressed: () {
                final value = controller.text.trim();
                if (onSubmitted != null) {
                  if (value.isNotEmpty) {
                    onSubmitted!(value);
                  }
                  FocusScope.of(context).unfocus();
                  return;
                }
                onMicTap?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}