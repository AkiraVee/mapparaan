import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapparaan/services/nearby_place_search_service.dart';

void main() {
  const origin = LatLng(14.6, 120.98);
  const categories = {
    'Mall': r'shop~"^(mall|shopping_centre|shopping_center)$"',
    'Restaurant': r'amenity~"^(restaurant|fast_food|cafe|food_court)$"',
    'Hospital': 'amenity=hospital',
    'School': r'amenity~"^(school|college|university|kindergarten)$"',
    'LRT/MRT': 'railway=station',
    'Park': r'leisure~"^(park|garden|playground)$"',
    'Market': 'amenity=marketplace',
  };

  for (final entry in categories.entries) {
    test(
      'maps ${entry.key} to a nearby OpenStreetMap category query',
      () async {
        Uri? requestedUri;
        final client = MockClient((request) async {
          requestedUri = request.url;
          return http.Response(jsonEncode({'elements': []}), 200);
        });

        await NearbyPlaceSearchService.search(
          entry.key,
          origin,
          client: client,
        );

        final query = requestedUri!.queryParameters['data']!;
        expect(query, contains(entry.value));
        expect(query, contains('around:3000,14.600000,120.980000'));
        expect(query, contains('out center tags'));
        client.close();
      },
    );
  }

  test('returns named nearby features ordered by distance', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'elements': [
            {
              'type': 'way',
              'id': 2,
              'center': {'lat': 14.61, 'lon': 120.98},
              'tags': {'name': 'Farther school', 'amenity': 'school'},
            },
            {
              'type': 'node',
              'id': 1,
              'lat': 14.6005,
              'lon': 120.98,
              'tags': {
                'name': 'Nearby school',
                'amenity': 'school',
                'addr:street': 'Test Street',
              },
            },
            {
              'type': 'node',
              'id': 3,
              'lat': 14.6001,
              'lon': 120.98,
              'tags': {'amenity': 'school'},
            },
          ],
        }),
        200,
      ),
    );

    final results = await NearbyPlaceSearchService.search(
      'School',
      origin,
      client: client,
    );

    expect(results.map((place) => place.name), [
      'Nearby school',
      'Farther school',
    ]);
    expect(results.first.subtitle, contains('Test Street'));
    expect(results.first.coordinates, const LatLng(14.6005, 120.98));
    client.close();
  });

  test(
    'surfaces Overpass service errors instead of fabricating results',
    () async {
      final client = MockClient(
        (_) async => http.Response('Overpass unavailable', 503),
      );

      await expectLater(
        () =>
            NearbyPlaceSearchService.search('Hospital', origin, client: client),
        throwsA(isA<http.ClientException>()),
      );
      client.close();
    },
  );
}
