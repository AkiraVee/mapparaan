import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapparaan/services/ai_assistant_service.dart';
import 'package:mapparaan/services/commuter_preference_service.dart';
import 'package:mapparaan/services/route_planner_service.dart';
import 'package:mapparaan/services/transit_planner_service.dart';

void main() {
  void useMockClient(http.Client client) {
    TransitPlannerService.clientOverride?.close();
    TransitPlannerService.clientOverride = client;
    addTearDown(() {
      if (identical(TransitPlannerService.clientOverride, client)) {
        TransitPlannerService.clientOverride = null;
        client.close();
      }
    });
  }

  Future<TransitPlanResult> requestPlan({
    Duration timeout = const Duration(seconds: 1),
  }) {
    return TransitPlannerService.planTransitResult(
      origin: const LatLng(14.6042, 120.9822),
      destination: const LatLng(14.5636, 120.9950),
      departureTime: DateTime(2026, 10, 30, 23),
      timeout: timeout,
    );
  }

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

    test('preserves partial-route metadata from the planner', () {
      final option = TransitPlanOption.fromJson({
        'preference': 'fastest',
        'title': 'Fastest route (partial)',
        'summary': 'Jeepney PUJ2137 (20 min)',
        'eta_minutes': 24,
        'fare': 15,
        'fare_discounted': 12,
        'transfers': 0,
        'modes': ['jeepney'],
        'is_partial': true,
        'remaining_distance_m': 2400,
        'is_next_service': true,
        'next_service_message': 'No transit is scheduled at the selected time. This route uses the next GTFS service window within 12 hours.',
        'partial_message': 'This verified transit segment ends at Stop A. The destination is about 2.4 km away in a straight line.',
        'legs': [
          {
            'type': 'ride',
            'mode': 'jeepney',
            'route_id': 'PUJ2137',
            'from': 'Stop B',
            'to': 'Stop A',
            'minutes': 20,
            'fare': 15,
            'path': [
              [14.60, 120.98],
              [14.62, 120.98],
            ],
          },
        ],
      });

      expect(option.isPartial, isTrue);
      expect(option.remainingDistanceM, 2400);
      expect(option.isNextService, isTrue);
      expect(option.nextServiceMessage, contains('within 12 hours'));
      expect(option.partialMessage, contains('straight line'));
      expect(option.legs.single.routeId, 'PUJ2137');
    });
  });

  test('walking-only alternatives preserve verified path and zero fare', () {
    final path = [const LatLng(14.60, 120.98), const LatLng(14.61, 120.99)];
    final option = TransitPlanOption.walking(
      from: 'Origin',
      to: 'Destination',
      path: path,
      distanceMeters: 1200,
    );

    expect(option.isWalkOption, isTrue);
    expect(option.etaMinutes, 17);
    expect(option.fare, 0);
    expect(option.fareEstimated, isFalse);
    expect(option.legs.single.path, path);
    expect(option.legs.single.meters, 1200);
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

  group('TransitPlannerService base URL', () {
    test('uses the host loopback alias on Android emulators', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(TransitPlannerService.effectiveBaseUrl, 'http://10.0.2.2:8080');
    });
  });

  group('TransitPlannerService response outcomes', () {
    test('distinguishes an empty successful result from offline', () async {
      useMockClient(
        MockClient(
          (_) async =>
              http.Response(json.encode({'status': 'ok', 'options': []}), 200),
        ),
      );

      final result = await requestPlan();

      expect(result.outcome, TransitPlanOutcome.noRoute);
      expect(result.isConnectivityFailure, isFalse);
    });

    test('classifies a successful outside-area response separately', () async {
      useMockClient(
        MockClient(
          (_) async => http.Response(
            json.encode({
              'status': 'ok',
              'reason': outsideServiceAreaReason,
              'options': [],
            }),
            200,
          ),
        ),
      );

      final result = await requestPlan();

      expect(result.outcome, TransitPlanOutcome.outsideServiceArea);
    });

    test(
      'classifies HTTP errors as server errors, not connectivity failures',
      () async {
        useMockClient(
          MockClient((_) async => http.Response('unavailable', 503)),
        );

        final result = await requestPlan();

        expect(result.outcome, TransitPlanOutcome.error);
        expect(result.isServerError, isTrue);
        expect(result.isConnectivityFailure, isFalse);
      },
    );

    test('classifies a network exception as offline', () async {
      useMockClient(
        MockClient((_) => throw http.ClientException('connection refused')),
      );

      final result = await requestPlan();

      expect(result.outcome, TransitPlanOutcome.offline);
    });

    test('classifies an unexpected response body as an API error', () async {
      useMockClient(MockClient((_) async => http.Response('{not-json', 200)));

      final result = await requestPlan();

      expect(result.outcome, TransitPlanOutcome.error);
      expect(result.isConnectivityFailure, isFalse);
    });

    test(
      'does not treat a 200 error envelope as an empty route result',
      () async {
        useMockClient(
          MockClient(
            (_) async => http.Response(
              json.encode({'status': 'error', 'options': []}),
              200,
            ),
          ),
        );

        final result = await requestPlan();

        expect(result.outcome, TransitPlanOutcome.error);
      },
    );
  });

  group('TransitPlannerService base URL', () {
    test('keeps localhost on non-Android platforms', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(TransitPlannerService.effectiveBaseUrl, 'http://127.0.0.1:8080');
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
