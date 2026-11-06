import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mapparaan/screens/ai_chat_screen.dart';
import 'package:mapparaan/services/ai_chat_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AiChatService serviceFor(MockClient client) => AiChatService(
    client: client,
    accessTokenProvider: () => 'verified-token',
    userIdProvider: () => 'verified-user',
  );

  testWidgets('offers retry after a transient error and resends the prompt', (
    tester,
  ) async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      if (requestCount == 1) {
        return http.Response(
          jsonEncode({
            'status': 'provider_error',
            'message': 'Try again shortly.',
          }),
          503,
        );
      }
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['message'], 'How do I get to Manila City Hall?');
      expect(payload['metadata']['history'], isEmpty);
      return http.Response(
        jsonEncode({'status': 'ok', 'message': 'Take the LRT.'}),
        200,
      );
    });

    await tester.pumpWidget(
      MaterialApp(home: AiChatScreen(service: serviceFor(client))),
    );
    await tester.enterText(
      find.byType(TextField),
      'How do I get to Manila City Hall?',
    );
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.text('Try again shortly.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(requestCount, 2);
    expect(find.text('Take the LRT.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('ignores a response from a conversation cleared while sending', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final client = MockClient((_) => response.future);
    await tester.pumpWidget(
      MaterialApp(home: AiChatScreen(service: serviceFor(client))),
    );
    await tester.enterText(
      find.byType(TextField),
      'A prompt that will be cleared',
    );
    await tester.tap(find.text('Send'));
    await tester.pump();

    await tester.tap(find.byTooltip('New conversation'));
    await tester.pump();
    response.complete(
      http.Response(
        jsonEncode({'status': 'ok', 'message': 'Stale response'}),
        200,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stale response'), findsNothing);
    expect(find.text('A prompt that will be cleared'), findsNothing);
    expect(find.text('Quick prompts'), findsOneWidget);
  });

  testWidgets('displays partial results as usable conversation answers', (
    tester,
  ) async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'status': 'partial',
          'message': 'A route was found, but schedule data is unavailable.',
        }),
        200,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: AiChatScreen(service: serviceFor(client))),
    );
    await tester.enterText(find.byType(TextField), 'Find a route and schedule');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Partial result:'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('renders planner route cards with genuine comparison labels', (
    tester,
  ) async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'status': 'ok',
          'message': 'These are planner results.',
          'route_recommendations': [_routeRecommendation()],
        }),
        200,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: AiChatScreen(service: serviceFor(client))),
    );
    await tester.enterText(find.byType(TextField), 'Plan a commute');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.text('Fastest route'), findsOneWidget);
    expect(find.text('Cheapest route'), findsOneWidget);
    expect(find.text('Cheapest returned'), findsOneWidget);
    expect(find.text('Fastest returned'), findsOneWidget);
    expect(find.text('View on map'), findsNWidgets(2));
    await tester.tap(find.text('View details').first);
    await tester.pumpAndSettle();
    expect(find.text('Board at Stop A; alight at Stop B'), findsOneWidget);
  });

  testWidgets('selected route opens the existing map and returns to chat', (
    tester,
  ) async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      if (requestCount == 1) {
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'message': 'Planner route found.',
            'route_recommendations': [_routeRecommendation()],
          }),
          200,
        );
      }
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(
        payload['metadata']['selected_route_title'],
        'Abad Santos to Manila City Hall: Cheapest route',
      );
      return http.Response(
        jsonEncode({'status': 'ok', 'message': 'It has one transfer.'}),
        200,
      );
    });

    await tester.pumpWidget(
      MaterialApp(home: AiChatScreen(service: serviceFor(client))),
    );
    await tester.enterText(find.byType(TextField), 'Plan a commute');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select route').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View on map').first);
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(PolylineLayer), findsOneWidget);
    expect(find.byType(MarkerLayer), findsWidgets);
    expect(
      tester
          .widget<PolylineLayer>(find.byType(PolylineLayer))
          .polylines
          .single
          .color,
      const Color(0xFFF57F17),
    );

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select route').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View on map').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PolylineLayer>(find.byType(PolylineLayer))
          .polylines
          .single
          .points,
      hasLength(3),
    );
    expect(
      tester
          .widget<PolylineLayer>(find.byType(PolylineLayer))
          .polylines
          .single
          .color,
      const Color(0xFFE65100),
    );

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Where do I transfer?');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('It has one transfer.'), findsOneWidget);
    expect(requestCount, 2);
  });

  testWidgets('route without geometry cannot be drawn on the map', (
    tester,
  ) async {
    final route = _routeRecommendation();
    ((route['options'] as List).first as Map)['legs'] = [
      {
        'type': 'ride',
        'from': 'Stop A',
        'to': 'Stop B',
        'minutes': 30,
        'mode': 'jeepney',
        'path': [],
      },
    ];
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'status': 'ok',
          'message': 'Route found.',
          'route_recommendations': [route],
        }),
        200,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: AiChatScreen(service: serviceFor(client))),
    );
    await tester.enterText(find.byType(TextField), 'Plan a commute');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Map geometry unavailable'), findsOneWidget);
    final mapButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Map geometry unavailable'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(mapButton.onPressed, isNull);
  });
}

Map<String, dynamic> _routeRecommendation() => {
  'origin': {'display_name': 'Abad Santos'},
  'destination': {'display_name': 'Manila City Hall'},
  'origin_coordinates': [14.6, 120.98],
  'destination_coordinates': [14.59, 120.98],
  'passenger_type': 'general',
  'data_notice': 'Static GTFS estimates; not live service information.',
  'options': [
    {
      'title': 'Fastest route',
      'preference': 'fastest',
      'summary': 'Ride jeepney to City Hall.',
      'eta_minutes': 30,
      'fare': 30,
      'fare_max': 30,
      'fare_discounted': 24,
      'fare_discounted_max': 24,
      'fare_estimated': true,
      'transfers': 1,
      'modes': ['jeepney'],
      'legs': [
        {
          'type': 'ride',
          'from': 'Stop A',
          'to': 'Stop B',
          'minutes': 30,
          'mode': 'jeepney',
          'mode_label': 'Jeepney',
          'route_code': 'J-1',
          'fare': 30,
          'fare_max': 30,
          'fare_discounted': 24,
          'fare_discounted_max': 24,
          'path': [
            [14.6, 120.98],
            [14.59, 120.98],
          ],
        },
      ],
    },
    {
      'title': 'Cheapest route',
      'preference': 'cheapest',
      'summary': 'Ride a local bus.',
      'eta_minutes': 40,
      'fare': 20,
      'fare_max': 20,
      'fare_discounted': 16,
      'fare_discounted_max': 16,
      'fare_estimated': true,
      'transfers': 0,
      'modes': ['bus'],
      'legs': [
        {
          'type': 'ride',
          'from': 'Stop C',
          'to': 'Stop D',
          'minutes': 40,
          'mode': 'bus',
          'path': [
            [14.6, 120.98],
            [14.595, 120.99],
            [14.59, 120.98],
          ],
        },
      ],
    },
  ],
};
