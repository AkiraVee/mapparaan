import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mapparaan/services/ai_chat_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sends authenticated user and session info to the backend', () async {
    final client = MockClient((request) async {
      expect(request.method, equals('POST'));
      expect(request.url.path, equals('/ai/chat'));
      expect(request.headers['authorization'], equals('Bearer verified-token'));
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['user_id'], equals('user-123'));
      expect(payload['session_id'], equals('session-123'));
      expect(payload['message'], equals('How do I get to SM City Manila?'));
      expect(payload['metadata']['history'], isA<List>());
      return http.Response(
        jsonEncode({
          'status': 'ok',
          'provider': 'gemini',
          'model': 'gemini-flash-lite-latest',
          'message': 'Take the LRT or jeepney.',
          'response_type': 'route',
          'tool_results': [],
        }),
        200,
      );
    });

    final service = AiChatService(
      client: client,
      accessTokenProvider: () => 'verified-token',
      userIdProvider: () => 'user-123',
    );
    final result = await service.sendMessage(
      message: 'How do I get to SM City Manila?',
      sessionId: 'session-123',
      history: const [
        AiChatMessage(role: 'user', text: 'Hi'),
        AiChatMessage(role: 'assistant', text: 'Hello'),
      ],
    );

    expect(result.status, 'ok');
    expect(result.message, 'Take the LRT or jeepney.');
    expect(result.responseType, 'route');
  });

  test('parses planner route cards and validates backend geometry', () async {
    final response = AiChatResponse.fromJson({
      'status': 'ok',
      'message': 'Here are the planner routes.',
      'route_recommendations': [
        {
          'origin': {'display_name': 'Abad Santos'},
          'destination': {'display_name': 'Manila City Hall'},
          'origin_coordinates': [14.6, 120.98],
          'destination_coordinates': [14.59, 120.98],
          'passenger_type': 'student',
          'options': [
            {
              'title': 'Fastest route',
              'preference': 'fastest',
              'eta_minutes': 30,
              'fare': 25,
              'fare_discounted': 20,
              'fare_discounted_max': 22,
              'transfers': 1,
              'modes': ['jeepney', 'lrt1'],
              'legs': [
                {
                  'type': 'ride',
                  'from': 'Stop A',
                  'to': 'Stop B',
                  'minutes': 20,
                  'mode': 'jeepney',
                  'path': [
                    [14.6, 120.98],
                    [14.59, 120.98],
                  ],
                },
              ],
            },
            {
              'title': 'Malformed route',
              'preference': 'cheapest',
              'eta_minutes': 20,
              'fare': 10,
              'transfers': 0,
              'legs': [
                {
                  'type': 'ride',
                  'from': 'Stop A',
                  'to': 'Stop B',
                  'minutes': 10,
                  'path': [
                    [999, 120.98],
                    [14.59, 120.98],
                  ],
                },
              ],
            },
            {
              'title': 'Non-finite route',
              'preference': 'fastest',
              'eta_minutes': 10,
              'fare': double.infinity,
              'transfers': 0,
              'legs': [],
            },
          ],
        },
      ],
    });

    expect(response.routeRecommendations, hasLength(1));
    final recommendation = response.routeRecommendations.single;
    expect(recommendation.origin.name, 'Abad Santos');
    expect(recommendation.passengerCategory.name, 'student');
    expect(recommendation.options, hasLength(1));
    expect(recommendation.options.single.legs.single.path, hasLength(2));
    expect(recommendation.options.single.legs.single.path.first.latitude, 14.6);
  });

  test('includes selected route title as limited chat context', () async {
    final client = MockClient((request) async {
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(
        payload['metadata']['selected_route_title'],
        'Abad Santos to Manila City Hall: Cheapest route',
      );
      return http.Response(
        jsonEncode({'status': 'ok', 'message': 'Checked.'}),
        200,
      );
    });
    await AiChatService(
      client: client,
      accessTokenProvider: () => 'verified-token',
      userIdProvider: () => 'user-context',
    ).sendMessage(
      message: 'Where do I transfer?',
      sessionId: 'session-context',
      selectedRouteTitle: 'Abad Santos to Manila City Hall: Cheapest route',
    );
  });

  test('surfaces quota and backend errors as user-friendly messages', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'status': 'quota_exceeded',
          'message': 'You have reached the AI usage limit for now.',
          'usage': {
            'user_day_used': 10,
            'user_day_limit': 10,
            'user_minute_used': 5,
            'user_minute_limit': 5,
            'global_day_used': 100,
            'global_day_limit': 100,
          },
        }),
        429,
      ),
    );

    final result =
        await AiChatService(
          client: client,
          accessTokenProvider: () => 'verified-token',
          userIdProvider: () => 'user-456',
        ).sendMessage(
          message: 'Test quota',
          sessionId: 'session-456',
          history: const [],
        );

    expect(result.status, 'quota_exceeded');
    expect(result.userFacingMessage, contains('AI usage limit'));
  });

  test(
    'labels partial backend results without discarding the answer',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'status': 'partial',
            'message':
                'The route was found, but the schedule could not be verified.',
            'tool_results': [
              {'name': 'plan_route', 'status': 'ok'},
              {
                'name': 'get_transport_schedule',
                'status': 'planner_unavailable',
              },
            ],
          }),
          200,
        ),
      );

      final result =
          await AiChatService(
            client: client,
            accessTokenProvider: () => 'verified-token',
            userIdProvider: () => 'user-partial',
          ).sendMessage(
            message: 'Route and schedule?',
            sessionId: 'session-partial',
          );

      expect(result.isPartial, isTrue);
      expect(result.hasUsableAnswer, isTrue);
      expect(
        result.userFacingMessage,
        startsWith('Partial result: The route was found'),
      );
    },
  );

  test('requires an access token even when a user ID is available', () async {
    final service = AiChatService(
      accessTokenProvider: () => null,
      userIdProvider: () => 'user-123',
    );

    await expectLater(
      service.sendMessage(message: 'Hello', sessionId: 'session-789'),
      throwsA(isA<StateError>()),
    );
    service.dispose();
  });

  test('keeps only the most recent ten non-error history entries', () async {
    final client = MockClient((request) async {
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      final history = payload['metadata']['history'] as List<dynamic>;
      expect(history, hasLength(10));
      expect(history.first['text'], 'message 2');
      expect(history.last['text'], 'message 11');
      return http.Response(
        jsonEncode({'status': 'ok', 'message': 'done'}),
        200,
      );
    });
    final service = AiChatService(
      client: client,
      accessTokenProvider: () => 'verified-token',
      userIdProvider: () => 'user-123',
    );
    final history = List<AiChatMessage>.generate(
      12,
      (index) => AiChatMessage(role: 'user', text: 'message $index'),
    );
    history.insert(
      5,
      AiChatMessage.assistant('A failed answer', isError: true),
    );

    await service.sendMessage(
      message: 'current message',
      sessionId: 'session-history',
      history: history,
    );
  });
}
