import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapparaan/screens/search_location_screen.dart';
import 'package:mapparaan/services/ai_assistant_service.dart';
import 'package:mapparaan/services/manila_boundary_service.dart';
import 'package:mapparaan/services/place_search_service.dart';
import 'package:mapparaan/services/route_planner_service.dart';
import 'package:mapparaan/services/saved_places_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const place = PlaceResult(
    name: 'University of Santo Tomas',
    subtitle: 'España, Manila',
    coordinates: LatLng(14.6091, 120.9894),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows saved-place empty state and short-query guidance', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SearchLocationScreen(
          showMap: false,
          loadSavedPlaces: _emptySavedPlaces,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Places you save from their details will appear here.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'us');
    await tester.pump();

    expect(find.text('Type at least 3 characters to search.'), findsOneWidget);
  });

  testWidgets('shows a useful empty state when a search has no matches', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SearchLocationScreen(
          showMap: false,
          searchPlaces: (_) async => [],
          loadSavedPlaces: _emptySavedPlaces,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'no match');
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();

    expect(find.text('No places found'), findsOneWidget);
    expect(find.textContaining('Try a nearby landmark'), findsOneWidget);
  });

  testWidgets('ignores stale search results when a newer query is pending', (
    WidgetTester tester,
  ) async {
    final firstSearch = Completer<List<PlaceResult>>();
    final secondSearch = Completer<List<PlaceResult>>();
    var searchCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SearchLocationScreen(
          showMap: false,
          searchPlaces: (_) {
            searchCount++;
            return searchCount == 1 ? firstSearch.future : secondSearch.future;
          },
          loadSavedPlaces: _emptySavedPlaces,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'first query');
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();
    expect(searchCount, 1);

    await tester.enterText(find.byType(TextField), 'second query');
    await tester.pump();
    firstSearch.complete([place]);
    await tester.pump();
    expect(find.text(place.name), findsNothing);

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();
    expect(searchCount, 2);
    secondSearch.complete([
      const PlaceResult(
        name: 'Second query result',
        subtitle: 'Manila',
        coordinates: LatLng(14.6, 121.0),
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Second query result'), findsOneWidget);
    expect(find.text(place.name), findsNothing);
  });

  testWidgets('returns the selected place and parsed route preferences', (
    WidgetTester tester,
  ) async {
    final selectionResult = Completer<SearchSelection?>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  final selection = await Navigator.of(context)
                      .push<SearchSelection>(
                        MaterialPageRoute(
                          builder: (_) => SearchLocationScreen(
                            showMap: false,
                            initialQuery: 'UST cheapest student',
                            searchPlaces: (_) async => [place],
                            reverseGeocode: _notFound,
                            loadManilaBoundary: _testBoundaryLoader,
                            loadSavedPlaces: _emptySavedPlaces,
                          ),
                        ),
                      );
                  selectionResult.complete(selection);
                },
                child: const Text('Open search'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open search'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();
    await tester.tap(find.byTooltip('Choose a location on the map'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose pickup on map'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('map-pin-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Pickup: Pinned location'), findsOneWidget);

    await tester.tap(find.text(place.name));
    await tester.pumpAndSettle();
    expect(find.text('Selected destination'), findsOneWidget);

    final planRoute = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Plan route'),
    );
    planRoute.onPressed!();
    await tester.pumpAndSettle();

    final selection = await selectionResult.future;
    expect(selection?.place.name, place.name);
    expect(selection?.origin?.name, 'Pinned location');
    expect(selection?.origin?.coordinates, const LatLng(14.59, 120.976));
    expect(selection?.resolution?.preference, RoutePreference.cheapest);
    expect(selection?.resolution?.passengerType, PassengerType.student);
  });
}

Future<List<SavedPlace>> _emptySavedPlaces() async => [];
Future<PlaceResult?> _notFound(LatLng coordinates) async => null;

Future<ManilaBoundary> _testBoundaryLoader() async {
  return ManilaBoundary.fromGeoJson({
    'type': 'Polygon',
    'coordinates': [
      [
        [120.9, 14.5],
        [121.0, 14.5],
        [121.0, 14.7],
        [120.9, 14.7],
        [120.9, 14.5],
      ],
    ],
  });
}
