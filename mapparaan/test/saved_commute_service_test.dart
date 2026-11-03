import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapparaan/services/ai_assistant_service.dart';
import 'package:mapparaan/services/route_planner_service.dart';
import 'package:mapparaan/services/saved_commute_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saves edited preference and passenger type for a commute', () async {
    const commute = SavedCommute(
      id: 'home|work',
      label: 'Morning trip',
      originName: 'Home',
      origin: LatLng(14.59, 120.97),
      destinationName: 'Work',
      destination: LatLng(14.60, 120.98),
    );
    await SavedCommuteService.save(commute);

    await SavedCommuteService.save(
      const SavedCommute(
        id: 'home|work',
        label: 'Work commute',
        originName: 'Home',
        origin: LatLng(14.59, 120.97),
        destinationName: 'Work',
        destination: LatLng(14.60, 120.98),
        preference: RoutePreference.cheapest,
        passengerType: PassengerType.student,
      ),
    );

    final saved = await SavedCommuteService.load();

    expect(saved, hasLength(1));
    expect(saved.single.label, 'Work commute');
    expect(saved.single.preference, RoutePreference.cheapest);
    expect(saved.single.passengerType, PassengerType.student);
  });

  test('stores a reversed commute as a separate return shortcut', () async {
    await SavedCommuteService.save(
      const SavedCommute(
        id: 'home|work',
        label: 'Home to work',
        originName: 'Home',
        origin: LatLng(14.59, 120.97),
        destinationName: 'Work',
        destination: LatLng(14.60, 120.98),
      ),
    );
    await SavedCommuteService.save(
      const SavedCommute(
        id: 'work|home',
        label: 'Work to home',
        originName: 'Work',
        origin: LatLng(14.60, 120.98),
        destinationName: 'Home',
        destination: LatLng(14.59, 120.97),
      ),
    );

    final saved = await SavedCommuteService.load();

    expect(saved, hasLength(2));
    expect(saved.first.originName, 'Work');
    expect(saved.first.destinationName, 'Home');
    expect(saved.first.origin, const LatLng(14.60, 120.98));
    expect(saved.first.destination, const LatLng(14.59, 120.97));
  });
}
