// added a new file for location details bottom sheet UI

import 'package:flutter/material.dart';

/// A reusable Bottom Sheet UI widget that displays location details.
/// We use a StatefulWidget here because the "Bookmark" icon needs to toggle
/// its own state (filled vs outlined) when tapped.
class LocationDetailsSheet extends StatefulWidget {
  // Required data to display the location
  final String title;
  
  // Optional address (subtitle from PlaceResult)
  final String? address;
  
  // Callbacks for the action buttons so the parent screen (HomeScreen) 
  // can handle the actual business logic (navigation, API calls, etc.)
  final VoidCallback onClose;
  final VoidCallback? onDirections;
  final VoidCallback? onSave;
  final VoidCallback? onShare;

  const LocationDetailsSheet({
    super.key,
    required this.title,
    this.address,
    required this.onClose,
    this.onDirections,
    this.onSave,
    this.onShare,
  });

  @override
  State<LocationDetailsSheet> createState() => _LocationDetailsSheetState();
}

class _LocationDetailsSheetState extends State<LocationDetailsSheet> {
  // Tracks whether this location is bookmarked locally in the UI
  bool _isBookmarked = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Styling the container to look like a bottom sheet floating over the map
      decoration: const BoxDecoration(
        color: Colors.white,
        // Rounds only the top-left and top-right corners
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        // Adds a soft shadow pointing upwards to separate it from the map
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -4),
          ),
        ],
      ),
      // Padding inside the sheet. Bottom padding is extra large (32) to account 
      // for device safe areas (like the iOS home indicator)
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        // mainAxisSize: MainAxisSize.min ensures the sheet only takes up 
        // as much vertical space as its children need, rather than the whole screen.
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---------------------------------------------------------
          // 1. TOP DRAG HANDLE (Purely visual indicator)
          // ---------------------------------------------------------
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // ---------------------------------------------------------
          // 2. HEADER ROW (Title, Subtitle, and Top Right Icons)
          // ---------------------------------------------------------
          Row(
            // Align to start so the title is at the top left of this row
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Expanded forces the text column to take up remaining horizontal space,
              // pushing the icon buttons to the far right and preventing text overflow.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Location Title
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      maxLines: 2, // Limits title to 2 lines
                      overflow: TextOverflow.ellipsis, // Adds "..." if it's too long
                    ),
                    // Only render the address Text widget if an address was provided
                    if (widget.address != null && widget.address!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.address!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8), // Spacing between text and icons
              
              // ---------------------------------------------------------
              // 3. TOP RIGHT ICON BUTTONS (Bookmark, Share, Close)
              // ---------------------------------------------------------
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Bookmark Icon Button
                  IconButton(
                    // Dynamically swap icon and color based on state
                    icon: Icon(
                      _isBookmarked ? Icons.bookmark : Icons.bookmark_add_outlined,
                      color: _isBookmarked ? const Color(0xFF00695C) : Colors.black87,
                    ),
                    onPressed: () {
                      // Trigger a UI rebuild to update the icon
                      setState(() {
                        _isBookmarked = !_isBookmarked;
                      });
                      // If a parent provided an onSave callback, execute it
                      if (widget.onSave != null) widget.onSave!();
                    },
                  ),
                  // Share Icon Button
                  IconButton(
                    icon: const Icon(Icons.ios_share, color: Colors.black87),
                    onPressed: widget.onShare,
                  ),
                  // Close Icon Button
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.black87),
                    // Triggers the onClose callback passed from HomeScreen
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20), // Spacing before the pills
          
          // ---------------------------------------------------------
          // 4. ACTION PILLS ROW (Directions, Save, Share)
          // ---------------------------------------------------------
          // Wrapping in SingleChildScrollView allows users on small screens 
          // to swipe left/right if the buttons take up too much horizontal space.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPillButton(
                  label: "Directions",
                  color: const Color(0xFF00695C), // MapParaan primary dark green
                  textColor: Colors.white,
                  onTap: widget.onDirections,
                ),
                const SizedBox(width: 8),
                _buildPillButton(
                  label: "Save",
                  color: const Color(0xFFB3E5FC), // Light blue from reference image
                  textColor: Colors.black87,
                  onTap: () {
                    // Syncs with the top-right bookmark icon logic
                    setState(() {
                      _isBookmarked = !_isBookmarked;
                    });
                    if (widget.onSave != null) widget.onSave!();
                  },
                ),
                const SizedBox(width: 8),
                _buildPillButton(
                  label: "Share",
                  color: const Color(0xFFB3E5FC),
                  textColor: Colors.black87,
                  onTap: widget.onShare,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A private helper widget to generate consistent, rounded pill-shaped buttons.
  Widget _buildPillButton({
    required String label,
    required Color color,
    required Color textColor,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        decoration: BoxDecoration(
          color: color, // The background color of the pill
          borderRadius: BorderRadius.circular(24), // Gives the pill shape
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}