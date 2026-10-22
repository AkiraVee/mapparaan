import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapparaan/services/ai_assistant_service.dart';
import 'package:mapparaan/services/commuter_preference_service.dart';
import 'package:mapparaan/services/route_planner_service.dart';
import 'package:mapparaan/services/transit_planner_service.dart';

void main() {
  group('PassengerTypeExt', () {
    test('apiValue matches backend expected identifiers', () {
      expect(PassengerType.general.apiValue, 'general');
      expect(PassengerType.student.apiValue, 'student');
      expect(PassengerType.senior.apiValue, 'senior');
      expect(PassengerType.pwd.apiValue, 'pwd');
    });

    test('isDiscounted is true only for student, senior, and pwd', () {
      expect(PassengerType.general.isDiscounted, isFalse);
      expect(PassengerType.student.isDiscounted, isTrue);
      expect(PassengerType.senior.isDiscounted, isTrue);
      expect(PassengerType.pwd.isDiscounted, isTrue);
    });
  });

  group('TransitPlanOption JSON deserialization', () {
    test('parses full API response with legs and coordinates', () {
      final json = {
        'preference': 'fastest',
        'title': 'Fastest route',
        'summary': 'Walk 5 min → LRT-1 LRT 1 (20 min)',
        'eta_minutes': 25,
        'fare': 35,
        'fare_discounted': 28,
        'transfers': 0,
        'modes': ['lrt1'],
        'legs': [
          {
            'type': 'walk',
            'from': 'Your location',
            'to': 'Central Terminal LRT',
            'minutes': 5,
            'meters': 350,
            'path': [
              [14.5918, 120.9786],
              [14.5928, 120.9820],
            ],
          },
          {
            'type': 'ride',
            'mode': 'lrt1',
            'mode_label': 'LRT-1',
            'route_id': 'ROUTE_880747',
            'route_code': 'LRT 1',
            'route_name': 'Baclaran - Roosevelt',
            'from': 'Central Terminal LRT',
            'to': 'Monumento LRT',
            'stops': 9,
            'wait_minutes': 3,
            'minutes': 18,
            'km': 9.2,
            'fare': 35,
            'path': [
              [14.5928, 120.9820],
              [14.6542, 120.9839],
            ],
          },
        ],
      };

      final option = TransitPlanOption.fromJson(json);

      expect(option.preference, 'fastest');
      expect(option.title, 'Fastest route');
      expect(option.etaMinutes, 25);
      expect(option.fare, 35);
      expect(option.fareDiscounted, 28);
      expect(option.transfers, 0);
      expect(option.modes, contains('lrt1'));
      expect(option.legs.length, 2);

      // Verify legs
      final walkLeg = option.legs[0];
      expect(walkLeg.isWalk, isTrue);
      expect(walkLeg.meters, 350);
      expect(walkLeg.path.length, 2);

      final rideLeg = option.legs[1];
      expect(rideLeg.isRide, isTrue);
      expect(rideLeg.mode, 'lrt1');
      expect(rideLeg.modeLabel, 'LRT-1');
      expect(rideLeg.stops, 9);
      expect(rideLeg.path.length, 2);

      // Verify allPoints extraction
      expect(option.allPoints.length, 4);

      // Verify effective fares
      expect(option.effectiveFare(PassengerType.general), 35);
      expect(option.effectiveFare(PassengerType.student), 28);
      expect(option.effectiveFare(PassengerType.senior), 28);
      expect(option.effectiveFare(PassengerType.pwd), 28);
    });
  });

  test('unknown transit modes use the selected app accent color', () {
    final previous = CommuterPreferencesService.current.value;
    addTearDown(() => CommuterPreferencesService.current.value = previous);
    CommuterPreferencesService.current.value = previous.copyWith(
      colorPalette: ColorPalette.pasigDusk,
    );

    const leg = TransitLeg(
      type: 'ride',
      from: 'A',
      to: 'B',
      minutes: 10,
      mode: 'other',
    );

    expect(leg.color, ColorPalette.pasigDusk.primary);
  });

  group('TransitPlannerService Fallback', () {
    test('generates fallback options when API is offline', () {
      const origin = LatLng(14.5943, 120.9721);
      const destination = LatLng(14.6567, 121.0287);

      final fallback = TransitPlannerService.getFallbackOptions(
        destination: destination,
        userLocation: origin,
        preference: RoutePreference.fastest,
        passengerType: PassengerType.student,
      );

      expect(fallback, isNotEmpty);
      expect(fallback.first.isMock, isTrue);
      expect(fallback.first.fare, greaterThan(0));
      expect(fallback.first.fareDiscounted, lessThan(fallback.first.fare));
      expect(
        fallback.first.effectiveFare(PassengerType.student),
        fallback.first.fareDiscounted,
      );
    });

    test('keeps each fallback route preference selectable', () {
      const origin = LatLng(14.5943, 120.9721);
      const destination = LatLng(14.6567, 121.0287);

      final fallback = TransitPlannerService.getFallbackOptions(
        destination: destination,
        userLocation: origin,
      );

      expect(
        fallback.map((option) => option.routePreference),
        containsAll(<RoutePreference>[
          RoutePreference.fastest,
          RoutePreference.cheapest,
          RoutePreference.fewestTransfers,
        ]),
      );
    });
  });

  group('AiQueryResolution passenger parsing', () {
    test('detects student discount from Taglish queries', () {
      final res = AiQueryResolution.fromQuery('student route to UST');
      expect(res.passengerType, PassengerType.student);
    });

    test('detects senior discount from query', () {
      final res = AiQueryResolution.fromQuery(
        'cheapest senior fare to SM North',
      );
      expect(res.passengerType, PassengerType.senior);
      expect(res.preference, RoutePreference.cheapest);
    });

    test('detects PWD discount from query', () {
      final res = AiQueryResolution.fromQuery('pwd route to Ayala');
      expect(res.passengerType, PassengerType.pwd);
    });

    test('defaults to general when no discount specified', () {
      final res = AiQueryResolution.fromQuery('to Monumento');
      expect(res.passengerType, PassengerType.general);
    });
  });
}
