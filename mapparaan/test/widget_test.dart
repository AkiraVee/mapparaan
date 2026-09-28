// ignore_for_file: must_call_super
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:mapparaan/main.dart';

class _TestMapLibrePlatform extends MapLibreMethodChannel {
  @override
  void dispose() {
    // Platform views do not initialize native method channels during headless widget tests.
    // Avoid accessing uninitialized late _channel.
  }
}

void main() {
  setUp(() {
    MapLibrePlatform.createInstance = () => _TestMapLibrePlatform();
  });

  testWidgets('Home screen loads', (WidgetTester tester) async {
    await tester.pumpWidget(const MapparaanApp());

    // Confirm the app builds without crashing.
    expect(find.byType(MapparaanApp), findsOneWidget);
  });

  testWidgets('Drawer destinations open their pages', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MapparaanApp());
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Guest commuter'), findsOneWidget);
    expect(
      find.text(
        'Your profile and travel preferences will live here. Sign-in is not available yet.',
      ),
      findsOneWidget,
    );
  });
}
