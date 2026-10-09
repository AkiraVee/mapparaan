import 'package:flutter_test/flutter_test.dart';
import 'package:mapparaan/services/route_planner_service.dart';
import 'package:mapparaan/services/saved_places_service.dart';
import 'package:mapparaan/services/trip_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saved places persist values containing legacy delimiters', () async {
    const place = SavedPlace(
      id: 'place-1',
      name: 'Mall::North',
      subtitle: 'District::Metro Manila',
      latitude: 14.6,
      longitude: 121.0,
    );

    await SavedPlacesService.save(place);
    final loaded = await SavedPlacesService.load();

    expect(loaded, hasLength(1));
    expect(loaded.single.name, place.name);
    expect(loaded.single.subtitle, place.subtitle);
    expect(loaded.single.latitude, place.latitude);
    expect(loaded.single.longitude, place.longitude);
  });

  test('saved places can be toggled off after reload', () async {
    const place = SavedPlace(
      id: 'place-2',
      name: 'Makati',
      subtitle: 'Metro Manila',
      latitude: 14.55,
      longitude: 121.02,
    );

    expect(await SavedPlacesService.toggle(place), isTrue);
    expect(await SavedPlacesService.toggle(place), isFalse);
    expect(await SavedPlacesService.load(), isEmpty);
  });

  test('trip history round-trips route fields containing delimiters', () async {
    final trip = TripHistoryEntry(
      id: 'trip-1',
      origin: 'Taft',
      destination: 'Makati::CBD',
      preference: RoutePreference.cheapest,
      durationMinutes: 42,
      fareEstimate: 12.5,
      createdAt: DateTime.utc(2026, 10, 9),
    );

    await TripHistoryService.addEntry(trip);
    final loaded = await TripHistoryService.load();

    expect(loaded, hasLength(1));
    expect(loaded.single.id, trip.id);
    expect(loaded.single.origin, trip.origin);
    expect(loaded.single.destination, trip.destination);
    expect(loaded.single.preference, trip.preference);
    expect(loaded.single.durationMinutes, trip.durationMinutes);
    expect(loaded.single.fareEstimate, trip.fareEstimate);
    expect(loaded.single.createdAt, trip.createdAt);
  });

  test('legacy saved-place and trip-history records remain readable', () async {
    SharedPreferences.setMockInitialValues({
      'saved_places': ['old-id::Old Place::Old address::14.6::121.0'],
      'trip_history': [
        'old-trip::Taft::Old destination::cheapest::30::15::2026-10-09T00:00:00.000Z',
      ],
    });

    final places = await SavedPlacesService.load();
    final trips = await TripHistoryService.load();

    expect(places.single.name, 'Old Place');
    expect(places.single.subtitle, 'Old address');
    expect(trips.single.destination, 'Old destination');
    expect(trips.single.preference, RoutePreference.cheapest);
  });
}
