import 'package:flutter/material.dart';

class AskMapparaanBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool autofocus;
  final bool readOnly;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final VoidCallback? onMicTap;
  final IconData leadingIcon;
  final VoidCallback? onLeadingTap;
  final FocusNode? focusNode;

  const AskMapparaanBar({
    super.key,
    required this.controller,
    this.hintText = 'Ask MapParaan',
    this.autofocus = false,
    this.readOnly = false,
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
    return Material(
      color: Theme.of(context).cardColor, // Dynamic Background
      borderRadius: BorderRadius.circular(28),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const SizedBox(width: 4),
            InkWell(
              onTap: onLeadingTap ?? onTap,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(leadingIcon, color: Theme.of(context).iconTheme.color?.withOpacity(0.6)),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: autofocus,
                readOnly: readOnly,
                onTap: onTap,
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
            IconButton(
              tooltip: onSubmitted == null ? 'Voice search' : 'Search',
              icon: Icon(
                onSubmitted == null ? Icons.mic : Icons.send,
                color: Theme.of(context).iconTheme.color,
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