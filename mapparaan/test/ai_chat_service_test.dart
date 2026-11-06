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
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['user_id'], isNotEmpty);
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

    final result = await AiChatService(client: client).sendMessage(
      message: 'How do I get to SM City Manila?',
      sessionId: 'session-123',
      history: const [
        AiChatMessage(role: 'user', text: 'Hi'),
        AiChatMessage(role: 'assistant', text: 'Hello'),
      ],
      client: client,
      userId: 'user-123',
    );

    expect(result.status, 'ok');
    expect(result.message, 'Take the LRT or jeepney.');
    expect(result.responseType, 'route');
  });

  test('surfaces quota and backend errors as user-friendly messages', () async {
    final client = MockClient((_) async => http.Response(
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
    ));

    final result = await AiChatService(client: client).sendMessage(
      message: 'Test quota',
      sessionId: 'session-456',
      history: const [],
      client: client,
      userId: 'user-456',
    );

    expect(result.status, 'quota_exceeded');
    expect(result.userFacingMessage, contains('AI usage limit'));
  });
}
