import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapparaan/main.dart';
import 'package:mapparaan/screens/home_screen.dart';
import 'package:mapparaan/services/saved_places_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Home screen loads', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MapparaanApp(enableMap: false));

    expect(find.byType(MapparaanApp), findsOneWidget);
  });

  testWidgets('Tapping saved place from drawer selects it and opens details sheet', (
    WidgetTester tester,
  ) async {
    const testPlace = SavedPlace(
      id: '14.59_120.98',
      name: 'National Museum',
      subtitle: 'Manila, Philippines',
      latitude: 14.59,
      longitude: 120.98,
    );

    SharedPreferences.setMockInitialValues({
      'saved_places': [testPlace.serialize()],
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(showMap: false),
      ),
    );
    await tester.pumpAndSettle();

    // Open drawer
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    // Tap Saved Places in drawer
    await tester.tap(find.text('Saved Places'));
    await tester.pumpAndSettle();

    // Verify saved place appears
    expect(find.text('National Museum'), findsOneWidget);

    // Tap the saved place to select it and return to map
    await tester.tap(find.text('National Museum'));
    await tester.pumpAndSettle();

    // Verify we are back on HomeScreen with LocationDetailsSheet showing
    expect(find.text('Directions'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });
}
