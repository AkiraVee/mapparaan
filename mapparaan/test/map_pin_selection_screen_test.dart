import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapparaan/screens/map_pin_selection_screen.dart';
import 'package:mapparaan/services/manila_boundary_service.dart';
import 'package:mapparaan/services/place_search_service.dart';

void main() {
  const initialPoint = LatLng(14.59, 120.976);

  testWidgets('confirms an unnamed pin using exact selected coordinates', (
    WidgetTester tester,
  ) async {
    PlaceResult? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await Navigator.of(context).push<PlaceResult>(
                  MaterialPageRoute(
                    builder: (_) => const MapPinSelectionScreen(
                      role: MapPinRole.destination,
                      initialPoint: initialPoint,
                      showMap: false,
                      reverseGeocode: _notFound,
                      loadBoundary: _testBoundaryLoader,
                    ),
                  ),
                );
              },
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    final mapSize = tester.getSize(find.byKey(const ValueKey('map-pin-map')));
    final mapTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey('map-pin-map')),
    );
    await tester.dragFrom(
      mapTopLeft + Offset(mapSize.width / 2 + 30, mapSize.height / 2 - 50),
      const Offset(-60, 30),
    );
    await tester.pumpAndSettle();
    expect(find.text('Coordinates: 14.590000, 120.976000'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('map-pin-confirm')));
    await tester.pumpAndSettle();

    expect(selected?.name, 'Pinned location');
    final selectedCoordinates = selected!.coordinates;
    expect(
      selected?.subtitle,
      '${selectedCoordinates.latitude.toStringAsFixed(6)}, '
      '${selectedCoordinates.longitude.toStringAsFixed(6)}',
    );
    expect(selected?.coordinates, isNot(initialPoint));
  });

  testWidgets('uses reverse-geocoded address when available', (
    WidgetTester tester,
  ) async {
    PlaceResult? selected;
    var reverseGeocodeCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await Navigator.of(context).push<PlaceResult>(
                  MaterialPageRoute(
                    builder: (_) => MapPinSelectionScreen(
                      role: MapPinRole.pickup,
                      initialPoint: initialPoint,
                      showMap: false,
                      reverseGeocode: (_) async {
                        reverseGeocodeCalled = true;
                        return const PlaceResult(
                          name: 'Pedro Gil Street',
                          subtitle: 'Ermita, Manila',
                          coordinates: LatLng(14.59, 120.976),
                        );
                      },
                      loadBoundary: _testBoundaryLoader,
                    ),
                  ),
                );
              },
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(reverseGeocodeCalled, isTrue);
    expect(find.text('Pedro Gil Street'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('map-pin-confirm')));
    await tester.pumpAndSettle();

    expect(selected?.name, 'Pedro Gil Street');
    expect(selected?.coordinates, initialPoint);
  });

  testWidgets('disables confirmation for a point outside Manila', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MapPinSelectionScreen(
          role: MapPinRole.pickup,
          initialPoint: LatLng(14.6567, 121.0287),
          showMap: false,
          reverseGeocode: _notFound,
          loadBoundary: _testBoundaryLoader,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Outside MapParaan’s supported area'), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('map-pin-confirm')),
    );
    expect(confirm.onPressed, isNull);
  });
}

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
