import 'package:flutter/material.dart';

/// The pill-shaped "Ask MapParaan" search/voice bar reused across
/// Mapparaan's screens (bottom bar on the homepage, top bar on the
/// search screen, etc.).
class AskMapparaanBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onMicTap;
  final IconData leadingIcon;
  final VoidCallback? onLeadingTap;
  final FocusNode? focusNode;

  const AskMapparaanBar({
    super.key,
    required this.controller,
    this.hintText = 'Ask MapParaan',
    this.autofocus = false,
    this.onSubmitted,
    this.onMicTap,
    this.leadingIcon = Icons.search,
    this.onLeadingTap,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const SizedBox(width: 4),
            InkWell(
              onTap: onLeadingTap,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(leadingIcon, color: Colors.black45),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: autofocus,
                decoration: InputDecoration(
                  hintText: hintText,
                  border: InputBorder.none,
                ),
                onSubmitted: onSubmitted,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.mic, color: Colors.black87),
              onPressed: onMicTap,
            ),
          ],
        ),
      ),
    );
  }
}