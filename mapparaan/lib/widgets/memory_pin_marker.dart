import 'package:flutter/material.dart';
import '../services/commuter_preference_service.dart';

class _PinArrowPainter extends CustomPainter {
  final Color color;
  _PinArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
      
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MemoryPinMarker extends StatelessWidget {
  final String imageUrl;
  final VoidCallback onTap;

  const MemoryPinMarker({
    super.key,
    required this.imageUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CommuterPreferences>(
      valueListenable: CommuterPreferencesService.current,
      builder: (context, prefs, child) {
        final themeColor = prefs.colorPalette.primary;

        return GestureDetector(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(2), // Thinner border
                decoration: BoxDecoration(
                  color: themeColor,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    )
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    imageUrl,
                    width: 44,  // Smaller width
                    height: 38, // Smaller height
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => Container(
                      width: 44, height: 38, color: Colors.grey,
                      child: const Icon(Icons.image_not_supported, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
              CustomPaint(
                size: const Size(16, 10), // Smaller arrow
                painter: _PinArrowPainter(color: themeColor),
              ),
            ],
          ),
        );
      },
    );
  }
}