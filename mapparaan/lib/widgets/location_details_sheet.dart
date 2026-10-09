import 'package:flutter/material.dart';

enum TransportMode { walking, jeep, bus, uv, lrtMrt }

class LocationDetailsSheet extends StatefulWidget {
  final String title;
  final String? address;
  final bool isSaved;
  final VoidCallback onClose;
  final VoidCallback? onDirections;
  final VoidCallback? onSave;
  final VoidCallback? onShare;
  final ValueChanged<TransportMode>? onModeSelected;

  const LocationDetailsSheet({
    super.key,
    required this.title,
    this.address,
    this.isSaved = false,
    required this.onClose,
    this.onDirections,
    this.onSave,
    this.onShare,
    this.onModeSelected,
  });

  @override
  State<LocationDetailsSheet> createState() => _LocationDetailsSheetState();
}

class _LocationDetailsSheetState extends State<LocationDetailsSheet> {
  TransportMode? _selectedMode;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.30,
      minChildSize: 0.22,
      maxChildSize: 0.75,
      snap: true,
      snapSizes: const [0.30, 0.55, 0.75],
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 16,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag handle
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (details) {
                  final newSize = _sheetController.size -
                      details.delta.dy / MediaQuery.of(context).size.height;
                  _sheetController.jumpTo(newSize.clamp(0.22, 0.75));
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  children: [
                    // Header (only title + close)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.address != null &&
                                  widget.address!.isNotEmpty) ...[
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
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Action pills
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _pill('Directions', const Color(0xFF00695C), Colors.white,
                              widget.onDirections),
                          const SizedBox(width: 8),
                          _pill('Save', const Color(0xFFB3E5FC), Colors.black87,
                              widget.onSave),
                          const SizedBox(width: 8),
                          _pill('Share', const Color(0xFFB3E5FC), Colors.black87,
                              widget.onShare),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    const Text(
                      'Choose transport mode',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ===== Transport mode cards (styled like Figma) =====
                    _modeCard(
                      mode: TransportMode.walking,
                      icon: Icons.directions_walk,
                      title: 'Walking',
                      subtitle: 'Best for short distances',
                    ),
                    const SizedBox(height: 10),
                    _modeCard(
                      mode: TransportMode.jeep,
                      icon: Icons.airport_shuttle,
                      title: 'Jeepney',
                      subtitle: 'Most common & affordable',
                    ),
                    const SizedBox(height: 10),
                    _modeCard(
                      mode: TransportMode.bus,
                      icon: Icons.directions_bus,
                      title: 'Bus',
                      subtitle: 'Good for longer routes',
                    ),
                    const SizedBox(height: 10),
                    _modeCard(
                      mode: TransportMode.uv,
                      icon: Icons.directions_car,
                      title: 'UV Express',
                      subtitle: 'Faster point-to-point',
                    ),
                    const SizedBox(height: 10),
                    _modeCard(
                      mode: TransportMode.lrtMrt,
                      icon: Icons.train,
                      title: 'LRT / MRT',
                      subtitle: 'Avoid road traffic',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pill(String label, Color bg, Color fg, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _modeCard({
    required TransportMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _selectedMode == mode;

    return GestureDetector(
      onTap: () {
        setState(() => _selectedMode = mode);
        widget.onModeSelected?.call(mode);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE0F2F1) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFF00695C) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Left icon box
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF00695C) : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: selected ? Colors.white : Colors.black54,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: selected ? const Color(0xFF00695C) : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black54,
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
}