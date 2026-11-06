import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants.dart';
import 'auth_service.dart';

class AiChatMessage {
  final String role;
  final String text;
  final bool isError;

  const AiChatMessage({
    required this.role,
    required this.text,
    this.isError = false,
  });

  factory AiChatMessage.user(String text) =>
      AiChatMessage(role: 'user', text: text.trim());

  factory AiChatMessage.assistant(String text, {bool isError = false}) =>
      AiChatMessage(role: 'assistant', text: text.trim(), isError: isError);

  Map<String, dynamic> toHistoryEntry() => {'role': role, 'text': text};
}

class AiChatUsage {
  final int userDayUsed;
  final int userMinuteUsed;
  final int globalDayUsed;
  final int userDayLimit;
  final int userMinuteLimit;
  final int globalDayLimit;
  final String? resetAt;
  final String? minuteResetAt;

  const AiChatUsage({
    required this.userDayUsed,
    required this.userMinuteUsed,
    required this.globalDayUsed,
    required this.userDayLimit,
    required this.userMinuteLimit,
    required this.globalDayLimit,
    this.resetAt,
    this.minuteResetAt,
  });

  factory AiChatUsage.fromJson(Map<String, dynamic> json) {
    final usage = json['usage'];
    if (usage is! Map<String, dynamic>) {
      return const AiChatUsage(
        userDayUsed: 0,
        userMinuteUsed: 0,
        globalDayUsed: 0,
        userDayLimit: 10,
        userMinuteLimit: 5,
        globalDayLimit: 100,
      );
    }

    return AiChatUsage(
      userDayUsed: int.tryParse('${usage['user_day_used'] ?? usage['userDayUsed'] ?? 0}') ?? 0,
      userMinuteUsed: int.tryParse('${usage['user_minute_used'] ?? usage['userMinuteUsed'] ?? 0}') ?? 0,
      globalDayUsed: int.tryParse('${usage['global_day_used'] ?? usage['globalDayUsed'] ?? 0}') ?? 0,
      userDayLimit: int.tryParse('${usage['user_day_limit'] ?? usage['userDayLimit'] ?? 10}') ?? 10,
      userMinuteLimit: int.tryParse('${usage['user_minute_limit'] ?? usage['userMinuteLimit'] ?? 5}') ?? 5,
      globalDayLimit: int.tryParse('${usage['global_day_limit'] ?? usage['globalDayLimit'] ?? 100}') ?? 100,
      resetAt: usage['reset_at']?.toString() ?? usage['resetAt']?.toString(),
      minuteResetAt: usage['minute_reset_at']?.toString() ?? usage['minuteResetAt']?.toString(),
    );
  }
}

class AiChatResponse {
  final String status;
  final String provider;
  final String model;
  final String message;
  final String responseType;
  final List<Map<String, dynamic>> toolResults;
  final AiChatUsage? usage;
  final String? error;

  const AiChatResponse({
    required this.status,
    this.provider = 'unknown',
    this.model = 'unknown',
    this.message = '',
    this.responseType = 'chat',
    this.toolResults = const [],
    this.usage,
    this.error,
  });

  factory AiChatResponse.fromJson(Map<String, dynamic> json) {
    final toolResultsRaw = json['tool_results'] ?? json['toolResults'] ?? const <dynamic>[];
    final parsedTools = <Map<String, dynamic>>[];
    if (toolResultsRaw is List) {
      for (final item in toolResultsRaw) {
        if (item is Map) {
          parsedTools.add(Map<String, dynamic>.from(item));
        }
      }
    }

    final messageText = (json['message'] ?? '').toString().trim();
    return AiChatResponse(
      status: (json['status'] ?? 'error').toString(),
      provider: (json['provider'] ?? 'unknown').toString(),
      model: (json['model'] ?? 'unknown').toString(),
      message: messageText,
      responseType: (json['response_type'] ?? json['responseType'] ?? 'chat').toString(),
      toolResults: parsedTools,
      usage: json['usage'] is Map ? AiChatUsage.fromJson(json) : null,
      error: (json['error'] ?? '').toString().trim().isEmpty ? null : (json['error'] ?? '').toString().trim(),
    );
  }

  bool get isOk => status == 'ok';

  String get userFacingMessage {
    if (message.trim().isNotEmpty) return message.trim();
    if (error != null && error!.trim().isNotEmpty) return error!.trim();
    if (status == 'quota_exceeded') {
      return 'You have reached the AI usage limit for now. Please try again later.';
    }
    if (status == 'not_configured') {
      return 'MapParaan AI is not configured on the backend right now.';
    }
    if (status == 'provider_error') {
      return 'MapParaan AI is temporarily unavailable. Please try again in a moment.';
    }
    return 'MapParaan AI could not answer that request right now.';
  }
}

class AiChatService {
  AiChatService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _requestTimeout = Duration(seconds: 30);

  Future<AiChatResponse> sendMessage({
    required String message,
    required String sessionId,
    List<AiChatMessage> history = const [],
    http.Client? client,
    String? userId,
  }) async {
    final resolvedUserId = (userId ?? AuthService.currentUser?.id)?.trim();
    if (resolvedUserId == null || resolvedUserId.isEmpty) {
      throw StateError('Please sign in to use MapParaan AI.');
    }

    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      throw StateError('Please enter a message before sending.');
    }

    final body = <String, dynamic>{
      'user_id': resolvedUserId,
      'message': trimmedMessage,
      'session_id': sessionId,
      'metadata': {
        'history': _recentHistory(history),
      },
    };

    final uri = Uri.parse('${AppConstants.transitApiBaseUrl.trim()}/ai/chat');
    final request = await (client ?? _client)
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout);

    if (request.body.isEmpty) {
      return const AiChatResponse(
        status: 'error',
        message: 'The AI backend returned an empty response.',
      );
    }

    final decoded = jsonDecode(request.body);
    if (decoded is! Map<String, dynamic>) {
      return const AiChatResponse(
        status: 'error',
        message: 'The AI backend returned an invalid response.',
      );
    }

    final response = AiChatResponse.fromJson(decoded);
    if (request.statusCode >= 400 && response.message.isEmpty) {
      return AiChatResponse(
        status: response.status.isNotEmpty ? response.status : 'error',
        message: 'MapParaan AI request failed with HTTP ${request.statusCode}.',
        error: response.error,
      );
    }

    return response;
  }

  List<Map<String, dynamic>> _recentHistory(List<AiChatMessage> history) {
    final recent = history
        .where((entry) => entry.text.trim().isNotEmpty)
        .take(10)
        .map((entry) => entry.toHistoryEntry())
        .toList();
    return recent;
  }
}
