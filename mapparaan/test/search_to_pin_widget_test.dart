import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapparaan/screens/home_screen.dart';
import 'package:mapparaan/services/place_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('searching and selecting a place opens its map actions', (
    tester,
  ) async {
    final searchedQueries = <String>[];
    final result = PlaceResult(
      name: 'Santa Ana',
      subtitle: 'Taytay, Rizal, Philippines',
      coordinates: const LatLng(14.57, 121.13),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          showMap: false,
          searchPlaces: (query) async {
            searchedQueries.add(query);
            return [result];
          },
        ),
      ),
    );

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Santa Ana');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(searchedQueries, ['Santa Ana']);
    expect(find.text('Taytay, Rizal, Philippines'), findsOneWidget);

    await tester.tap(find.text('Santa Ana').last);
    await tester.pumpAndSettle();

    expect(find.text('Santa Ana'), findsNWidgets(2));
    expect(find.text('Directions'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });
}
