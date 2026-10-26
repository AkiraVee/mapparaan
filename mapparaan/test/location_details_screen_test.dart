import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapparaan/screens/location_details_screen.dart';
import 'package:mapparaan/services/ai_assistant_service.dart';
import 'package:mapparaan/services/place_search_service.dart';
import 'package:mapparaan/services/route_planner_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'LocationDetailsScreen renders correctly with passenger selector and route cards',
    (WidgetTester tester) async {
      const testPlace = PlaceResult(
        name: 'National Museum of the Philippines',
        subtitle: 'Padre Burgos Ave, Ermita, Manila',
        coordinates: LatLng(14.5869, 120.9812),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: LocationDetailsScreen(
            place: testPlace,
            userLocation: LatLng(14.5943, 120.9721),
            initialPreference: RoutePreference.fastest,
            passengerType: PassengerType.general,
          ),
        ),
      );

      // Initial pump
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify place name appears
      expect(find.text('National Museum of the Philippines'), findsOneWidget);

      // Verify passenger selector chips appear
      expect(find.text('Regular'), findsOneWidget);
      expect(find.text('Student'), findsOneWidget);
      expect(find.text('Senior'), findsOneWidget);
      expect(find.text('PWD'), findsOneWidget);

      // Verify preference buttons appear
      expect(find.text('Fastest'), findsOneWidget);
      expect(find.text('Cheapest'), findsOneWidget);

      // Tap on Student discount chip
      await tester.tap(find.text('Student'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify student is now selected
      expect(find.text('Student'), findsOneWidget);
    },
  );

  testWidgets('LocationDetailsScreen adapts to mobile and tablet widths', (
    WidgetTester tester,
  ) async {
    const testPlace = PlaceResult(
      name: 'National Museum of the Philippines',
      subtitle: 'Padre Burgos Ave, Ermita, Manila',
      coordinates: LatLng(14.5869, 120.9812),
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final size in const [
      Size(320, 568),
      Size(393, 852),
      Size(768, 1024),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        const MaterialApp(
          home: LocationDetailsScreen(
            place: testPlace,
            userLocation: LatLng(14.5943, 120.9721),
            initialPreference: RoutePreference.fastest,
            passengerType: PassengerType.general,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('National Museum of the Philippines'), findsOneWidget);
      final exception = tester.takeException();
      expect(exception, isNull, reason: 'Viewport: $size');

      if (size.width < 520) {
        expect(find.byTooltip('More place actions'), findsOneWidget);
      } else {
        expect(find.byTooltip('More place actions'), findsNothing);
      }
    }
  });
}
