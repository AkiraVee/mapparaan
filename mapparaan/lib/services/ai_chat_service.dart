import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import 'ai_assistant_service.dart';
import 'auth_service.dart';
import 'place_search_service.dart';
import 'transit_planner_service.dart';

LatLng? _routeCoordinate(Object? value) {
  if (value is! List || value.length < 2) return null;
  final latitude = value[0];
  final longitude = value[1];
  if (latitude is! num || longitude is! num) return null;
  final lat = latitude.toDouble();
  final lon = longitude.toDouble();
  if (!lat.isFinite ||
      !lon.isFinite ||
      lat < -90 ||
      lat > 90 ||
      lon < -180 ||
      lon > 180) {
    return null;
  }
  return LatLng(lat, lon);
}

bool _nonNegativeNumber(Object? value) =>
    value is num && value.isFinite && value >= 0;

bool _optionalNonNegativeNumber(Object? value) =>
    value == null || _nonNegativeNumber(value);

bool _nonNegativeInteger(Object? value) =>
    _nonNegativeNumber(value) && value == (value as num).toInt();

bool _optionalNonNegativeInteger(Object? value) =>
    value == null || _nonNegativeInteger(value);

bool _validRouteOption(Map<String, dynamic> json) {
  if (json['title'] is! String ||
      (json['title'] as String).trim().isEmpty ||
      json['preference'] is! String ||
      !{
        'fastest',
        'cheapest',
        'fewest_transfers',
        'walk',
      }.contains(json['preference']) ||
      !_nonNegativeInteger(json['eta_minutes']) ||
      !_nonNegativeNumber(json['fare']) ||
      !_nonNegativeInteger(json['transfers']) ||
      !_optionalNonNegativeNumber(json['fare_max']) ||
      !_optionalNonNegativeNumber(json['fare_discounted']) ||
      !_optionalNonNegativeNumber(json['fare_discounted_max']) ||
      !_optionalNonNegativeInteger(json['remaining_distance_m']) ||
      json['legs'] is! List) {
    return false;
  }
  final rawModes = json['modes'];
  if (rawModes != null &&
      (rawModes is! List || rawModes.any((mode) => mode is! String))) {
    return false;
  }
  final legs = json['legs'] as List;
  for (final item in legs) {
    if (item is! Map) return false;
    final leg = Map<String, dynamic>.from(item);
    if (!{'walk', 'ride'}.contains(leg['type']) ||
        leg['from'] is! String ||
        leg['to'] is! String ||
        !_nonNegativeInteger(leg['minutes']) ||
        !_optionalNonNegativeInteger(leg['meters']) ||
        !_optionalNonNegativeInteger(leg['wait_minutes']) ||
        !_optionalNonNegativeInteger(leg['stops']) ||
        !_optionalNonNegativeNumber(leg['km']) ||
        !_optionalNonNegativeNumber(leg['fare']) ||
        !_optionalNonNegativeNumber(leg['fare_max']) ||
        !_optionalNonNegativeNumber(leg['fare_discounted']) ||
        !_optionalNonNegativeNumber(leg['fare_discounted_max'])) {
      return false;
    }
    final path = leg['path'];
    if (path != null &&
        (path is! List ||
            path.any((point) => _routeCoordinate(point) == null))) {
      return false;
    }
  }
  return true;
}

class AiChatRouteRecommendation {
  final PlaceResult origin;
  final PlaceResult destination;
  final String passengerType;
  final List<TransitPlanOption> options;
  final String? dataNotice;

  const AiChatRouteRecommendation({
    required this.origin,
    required this.destination,
    required this.passengerType,
    required this.options,
    this.dataNotice,
  });

  static AiChatRouteRecommendation? fromJson(Map<String, dynamic> json) {
    final originData = json['origin'];
    final destinationData = json['destination'];
    if (originData is! Map || destinationData is! Map) return null;
    final originCoordinates = _routeCoordinate(json['origin_coordinates']);
    final destinationCoordinates = _routeCoordinate(
      json['destination_coordinates'],
    );
    if (originCoordinates == null || destinationCoordinates == null) {
      return null;
    }
    final originName = originData['display_name'];
    final destinationName = destinationData['display_name'];
    if (originName is! String ||
        originName.trim().isEmpty ||
        destinationName is! String ||
        destinationName.trim().isEmpty) {
      return null;
    }
    final rawOptions = json['options'];
    if (rawOptions is! List) return null;
    final options = <TransitPlanOption>[];
    for (final rawOption in rawOptions) {
      if (rawOption is! Map) continue;
      try {
        final optionJson = Map<String, dynamic>.from(rawOption);
        if (!_validRouteOption(optionJson)) continue;
        options.add(TransitPlanOption.fromJson(optionJson));
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    if (options.isEmpty) return null;
    final passenger = json['passenger_type'];
    return AiChatRouteRecommendation(
      origin: PlaceResult(
        name: originName.trim(),
        subtitle: '',
        coordinates: originCoordinates,
      ),
      destination: PlaceResult(
        name: destinationName.trim(),
        subtitle: '',
        coordinates: destinationCoordinates,
      ),
      passengerType: passenger is String ? passenger : 'general',
      options: options,
      dataNotice: json['data_notice'] is String
          ? json['data_notice'] as String
          : null,
    );
  }

  PassengerType get passengerCategory => PassengerType.values.firstWhere(
    (type) => type.name == passengerType,
    orElse: () => PassengerType.general,
  );
}

class AiChatMessage {
  final String role;
  final String text;
  final bool isError;
  final List<AiChatRouteRecommendation> routeRecommendations;

  const AiChatMessage({
    required this.role,
    required this.text,
    this.isError = false,
    this.routeRecommendations = const [],
  });

  factory AiChatMessage.user(String text) =>
      AiChatMessage(role: 'user', text: text.trim());

  factory AiChatMessage.assistant(
    String text, {
    bool isError = false,
    List<AiChatRouteRecommendation> routeRecommendations = const [],
  }) => AiChatMessage(
    role: 'assistant',
    text: text.trim(),
    isError: isError,
    routeRecommendations: routeRecommendations,
  );

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
      userDayUsed:
          int.tryParse(
            '${usage['user_day_used'] ?? usage['userDayUsed'] ?? 0}',
          ) ??
          0,
      userMinuteUsed:
          int.tryParse(
            '${usage['user_minute_used'] ?? usage['userMinuteUsed'] ?? 0}',
          ) ??
          0,
      globalDayUsed:
          int.tryParse(
            '${usage['global_day_used'] ?? usage['globalDayUsed'] ?? 0}',
          ) ??
          0,
      userDayLimit:
          int.tryParse(
            '${usage['user_day_limit'] ?? usage['userDayLimit'] ?? 10}',
          ) ??
          10,
      userMinuteLimit:
          int.tryParse(
            '${usage['user_minute_limit'] ?? usage['userMinuteLimit'] ?? 5}',
          ) ??
          5,
      globalDayLimit:
          int.tryParse(
            '${usage['global_day_limit'] ?? usage['globalDayLimit'] ?? 100}',
          ) ??
          100,
      resetAt: usage['reset_at']?.toString() ?? usage['resetAt']?.toString(),
      minuteResetAt:
          usage['minute_reset_at']?.toString() ??
          usage['minuteResetAt']?.toString(),
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
  final List<AiChatRouteRecommendation> routeRecommendations;
  final AiChatUsage? usage;
  final String? error;

  const AiChatResponse({
    required this.status,
    this.provider = 'unknown',
    this.model = 'unknown',
    this.message = '',
    this.responseType = 'chat',
    this.toolResults = const [],
    this.routeRecommendations = const [],
    this.usage,
    this.error,
  });

  factory AiChatResponse.fromJson(Map<String, dynamic> json) {
    final toolResultsRaw =
        json['tool_results'] ?? json['toolResults'] ?? const <dynamic>[];
    final parsedTools = <Map<String, dynamic>>[];
    if (toolResultsRaw is List) {
      for (final item in toolResultsRaw) {
        if (item is Map) {
          parsedTools.add(Map<String, dynamic>.from(item));
        }
      }
    }

    final messageText = (json['message'] ?? '').toString().trim();
    final routeRecommendations = <AiChatRouteRecommendation>[];
    final routeData =
        json['route_recommendations'] ?? json['routeRecommendations'];
    if (routeData is List) {
      for (final item in routeData) {
        if (item is! Map) continue;
        try {
          final recommendation = AiChatRouteRecommendation.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (recommendation != null) {
            routeRecommendations.add(recommendation);
          }
        } on FormatException {
          continue;
        } on TypeError {
          continue;
        }
      }
    }
    return AiChatResponse(
      status: (json['status'] ?? 'error').toString(),
      provider: (json['provider'] ?? 'unknown').toString(),
      model: (json['model'] ?? 'unknown').toString(),
      message: messageText,
      responseType: (json['response_type'] ?? json['responseType'] ?? 'chat')
          .toString(),
      toolResults: parsedTools,
      routeRecommendations: routeRecommendations,
      usage: json['usage'] is Map ? AiChatUsage.fromJson(json) : null,
      error: (json['error'] ?? '').toString().trim().isEmpty
          ? null
          : (json['error'] ?? '').toString().trim(),
    );
  }

  bool get isOk => status == 'ok';
  bool get isPartial => status == 'partial' && message.trim().isNotEmpty;
  bool get hasUsableAnswer => isOk || isPartial;

  String get userFacingMessage {
    if (message.trim().isNotEmpty) {
      return isPartial ? 'Partial result: ${message.trim()}' : message.trim();
    }
    if (error != null && error!.trim().isNotEmpty) return error!.trim();
    if (status == 'quota_exceeded') {
      return 'You have reached the AI usage limit for now. Please try again later.';
    }
    if (status == 'not_configured') {
      return 'MapParaan AI is not configured on the backend right now.';
    }
    if (status == 'unauthorized') {
      return 'Your sign-in session has expired. Please sign in again.';
    }
    if (status == 'auth_unavailable') {
      return 'Sign-in verification is temporarily unavailable. Please try again.';
    }
    if (status == 'provider_error') {
      return 'MapParaan AI is temporarily unavailable. Please try again in a moment.';
    }
    if (status == 'provider_quota_exceeded') {
      return 'MapParaan AI is temporarily rate-limited. Please try again later.';
    }
    return 'MapParaan AI could not answer that request right now.';
  }
}

class AiChatService {
  AiChatService({
    http.Client? client,
    String? Function()? accessTokenProvider,
    String? Function()? userIdProvider,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _accessTokenProvider =
           accessTokenProvider ??
           (() => AuthService.currentSession?.accessToken),
       _userIdProvider = userIdProvider ?? (() => AuthService.currentUser?.id);

  final http.Client _client;
  final bool _ownsClient;
  final String? Function() _accessTokenProvider;
  final String? Function() _userIdProvider;

  static const Duration _requestTimeout = Duration(seconds: 30);

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<AiChatResponse> sendMessage({
    required String message,
    required String sessionId,
    List<AiChatMessage> history = const [],
    String? selectedRouteTitle,
  }) async {
    final accessToken = _accessTokenProvider()?.trim();
    final resolvedUserId = _userIdProvider()?.trim();
    if (accessToken == null ||
        accessToken.isEmpty ||
        resolvedUserId == null ||
        resolvedUserId.isEmpty) {
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
        if (selectedRouteTitle != null && selectedRouteTitle.trim().isNotEmpty)
          'selected_route_title': selectedRouteTitle.trim().substring(
            0,
            selectedRouteTitle.trim().length > 160
                ? 160
                : selectedRouteTitle.trim().length,
          ),
      },
    };

    final uri = Uri.parse('${AppConstants.transitApiBaseUrl.trim()}/ai/chat');
    final request = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
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
    final eligible = history
        .where((entry) => !entry.isError && entry.text.trim().isNotEmpty)
        .toList();
    final start = eligible.length > 10 ? eligible.length - 10 : 0;
    return eligible.skip(start).map((entry) => entry.toHistoryEntry()).toList();
  }
}
