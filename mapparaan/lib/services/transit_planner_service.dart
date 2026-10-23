import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart' show Color;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import 'ai_assistant_service.dart';
import 'commuter_preference_service.dart';
import 'route_planner_service.dart';

/// Reason the planner API sends when a trip is outside the City of Manila.
const String outsideServiceAreaReason = 'outside_service_area';

/// Set by the app (not the server) when the planner answered with an HTTP error.
/// This is different from "unreachable": the server is up but could not plan the
/// trip, so the app shows an error instead of sample routes.
const String serverErrorReason = 'server_error';

/// Formats a peso amount without the currency sign: whole pesos as "18",
/// otherwise two decimals ("21.75", "14.50").
String formatPesoPlain(num amount) {
  final rounded = (amount * 100).round() / 100;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(2);
}

/// Formats a peso amount with the currency sign ("₱18", "₱21.75").
String formatPeso(num amount) => '₱${formatPesoPlain(amount)}';

double? _doubleOrNull(Object? value) => value is num ? value.toDouble() : null;

extension PassengerTypeExt on PassengerType {
  String get apiValue {
    switch (this) {
      case PassengerType.general:
        return 'general';
      case PassengerType.student:
        return 'student';
      case PassengerType.senior:
        return 'senior';
      case PassengerType.pwd:
        return 'pwd';
    }
  }

  String get label {
    switch (this) {
      case PassengerType.general:
        return 'Regular';
      case PassengerType.student:
        return 'Student';
      case PassengerType.senior:
        return 'Senior';
      case PassengerType.pwd:
        return 'PWD';
    }
  }

  bool get isDiscounted => this != PassengerType.general;
}

/// Represents an individual leg of a transit journey (walk or ride).
class TransitLeg {
  final String type; // 'walk' or 'ride'
  final String from;
  final String to;
  final int minutes;
  final int? meters;
  final String? mode; // 'jeepney', 'bus', 'lrt1', 'lrt2', 'mrt3', 'pnr', etc.
  final String? modeLabel;
  final String? routeId;
  final String? routeCode;
  final String? routeName;
  final int? stops;
  final int? waitMinutes;
  final double? km;

  /// Regular fare for this leg (lowest: traditional jeepney / ordinary bus).
  final double? fare;

  /// Highest regular fare (modern jeepney / aircon bus). Same as [fare] on rail.
  final double? fareMax;
  final double? fareDiscounted;
  final double? fareDiscountedMax;
  final bool fareEstimated;
  final List<LatLng> path;

  const TransitLeg({
    required this.type,
    required this.from,
    required this.to,
    required this.minutes,
    this.meters,
    this.mode,
    this.modeLabel,
    this.routeId,
    this.routeCode,
    this.routeName,
    this.stops,
    this.waitMinutes,
    this.km,
    this.fare,
    this.fareMax,
    this.fareDiscounted,
    this.fareDiscountedMax,
    this.fareEstimated = true,
    this.path = const [],
  });

  bool get isWalk => type == 'walk';
  bool get isRide => type == 'ride';

  Color get color {
    if (isWalk) return const Color(0xFF78909C); // Slate grey
    switch (mode?.toLowerCase()) {
      case 'jeepney':
        return const Color(0xFFF57F17); // Jeepney amber/orange
      case 'bus':
        return const Color(0xFFE65100); // Deep bus orange
      case 'lrt1':
      case 'lrt2':
      case 'mrt3':
      case 'pnr':
        return const Color(0xFF0288D1); // Rail blue
      case 'uv_express':
        return const Color(0xFF5E35B1); // Purple
      default:
        return CommuterPreferencesService.current.value.colorPalette.primary;
    }
  }

  factory TransitLeg.fromJson(Map<String, dynamic> json) {
    final rawPath = json['path'] as List? ?? [];
    final points = <LatLng>[];
    for (final pt in rawPath) {
      if (pt is List && pt.length >= 2) {
        final lat = (pt[0] as num).toDouble();
        final lon = (pt[1] as num).toDouble();
        points.add(LatLng(lat, lon));
      }
    }

    return TransitLeg(
      type: json['type'] as String? ?? 'walk',
      from: json['from'] as String? ?? '',
      to: json['to'] as String? ?? '',
      minutes: (json['minutes'] as num?)?.toInt() ?? 0,
      meters: (json['meters'] as num?)?.toInt(),
      mode: json['mode'] as String?,
      modeLabel: json['mode_label'] as String?,
      routeId: json['route_id'] as String?,
      routeCode: json['route_code'] as String?,
      routeName: json['route_name'] as String?,
      stops: (json['stops'] as num?)?.toInt(),
      waitMinutes: (json['wait_minutes'] as num?)?.toInt(),
      km: (json['km'] as num?)?.toDouble(),
      fare: _doubleOrNull(json['fare']),
      fareMax: _doubleOrNull(json['fare_max']),
      fareDiscounted: _doubleOrNull(json['fare_discounted']),
      fareDiscountedMax: _doubleOrNull(json['fare_discounted_max']),
      fareEstimated: json['fare_estimated'] as bool? ?? true,
      path: points,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'from': from,
    'to': to,
    'minutes': minutes,
    'meters': meters,
    'mode': mode,
    'mode_label': modeLabel,
    'route_id': routeId,
    'route_code': routeCode,
    'route_name': routeName,
    'stops': stops,
    'wait_minutes': waitMinutes,
    'km': km,
    'fare': fare,
    'fare_max': fareMax,
    'fare_discounted': fareDiscounted,
    'fare_discounted_max': fareDiscountedMax,
    'fare_estimated': fareEstimated,
    'path': path.map((point) => [point.latitude, point.longitude]).toList(),
  };
}

/// A complete route option (fastest / cheapest / fewest transfers) returned by the transit planner.
class TransitPlanOption {
  final String preference;
  final String title;
  final String summary;
  final int etaMinutes;

  /// Lowest regular fare (traditional jeepney / ordinary bus; exact on rail).
  final double fare;

  /// Highest regular fare (modern jeepney / aircon bus). Null means no range.
  final double? fareMax;

  /// Student / senior / PWD fare, lowest and highest.
  final double fareDiscounted;
  final double? fareDiscountedMax;

  /// True when any part of the fare is a distance estimate rather than a table value.
  final bool fareEstimated;
  final String fareSource;
  final int transfers;
  final List<String> modes;
  final List<TransitLeg> legs;
  final bool isMock;

  const TransitPlanOption({
    required this.preference,
    required this.title,
    required this.summary,
    required this.etaMinutes,
    required this.fare,
    this.fareMax,
    required this.fareDiscounted,
    this.fareDiscountedMax,
    this.fareEstimated = true,
    this.fareSource = 'Estimated fare; verify before travel',
    required this.transfers,
    this.modes = const [],
    this.legs = const [],
    this.isMock = false,
  });

  /// Returns the applicable (lowest) fare based on passenger category
  double effectiveFare(PassengerType passengerType) {
    return passengerType.isDiscounted ? fareDiscounted : fare;
  }

  /// Highest applicable fare (modern jeepney / aircon bus).
  double effectiveFareUpTo(PassengerType passengerType) {
    final upTo = passengerType.isDiscounted ? fareDiscountedMax : fareMax;
    final base = effectiveFare(passengerType);
    return upTo != null && upTo > base ? upTo : base;
  }

  /// True when the fare could be higher on a modern jeepney or aircon bus.
  bool hasFareRange(PassengerType passengerType) =>
      effectiveFareUpTo(passengerType) > effectiveFare(passengerType) + 0.001;

  /// Percent saved by the discounted fare (0 when there is no discount).
  int get discountPercent => fare > 0
      ? (((fare - fareDiscounted) / fare) * 100).round().clamp(0, 100).toInt()
      : 0;

  /// Maps string preference to RoutePreference enum
  RoutePreference get routePreference {
    switch (preference.toLowerCase()) {
      case 'cheapest':
        return RoutePreference.cheapest;
      case 'fewest_transfers':
      case 'fewest':
        return RoutePreference.fewestTransfers;
      case 'fastest':
      default:
        return RoutePreference.fastest;
    }
  }

  /// All consecutive points forming the path for map rendering
  List<LatLng> get allPoints {
    final points = <LatLng>[];
    for (final leg in legs) {
      points.addAll(leg.path);
    }
    return points;
  }

  factory TransitPlanOption.fromJson(Map<String, dynamic> json) {
    final rawLegs = json['legs'] as List? ?? [];
    final parsedLegs = rawLegs
        .map((l) => TransitLeg.fromJson(l as Map<String, dynamic>))
        .toList();

    final rawModes = json['modes'] as List? ?? [];
    final parsedModes = rawModes.map((m) => m.toString()).toList();

    return TransitPlanOption(
      preference: json['preference'] as String? ?? 'fastest',
      title: json['title'] as String? ?? 'Route option',
      summary: json['summary'] as String? ?? '',
      etaMinutes: (json['eta_minutes'] as num?)?.toInt() ?? 0,
      fare: _doubleOrNull(json['fare']) ?? 0,
      fareMax: _doubleOrNull(json['fare_max']),
      fareDiscounted:
          _doubleOrNull(json['fare_discounted']) ??
          (_doubleOrNull(json['fare']) ?? 0),
      fareDiscountedMax: _doubleOrNull(json['fare_discounted_max']),
      fareEstimated: json['fare_estimated'] as bool? ?? true,
      fareSource:
          json['fare_source'] as String? ??
          'Estimated fare; verify before travel',
      transfers: (json['transfers'] as num?)?.toInt() ?? 0,
      modes: parsedModes,
      legs: parsedLegs,
      isMock: false,
    );
  }

  Map<String, dynamic> toJson() => {
    'preference': preference,
    'title': title,
    'summary': summary,
    'eta_minutes': etaMinutes,
    'fare': fare,
    'fare_max': fareMax,
    'fare_discounted': fareDiscounted,
    'fare_discounted_max': fareDiscountedMax,
    'fare_estimated': fareEstimated,
    'fare_source': fareSource,
    'transfers': transfers,
    'modes': modes,
    'legs': legs.map((leg) => leg.toJson()).toList(),
  };

  /// Converts a legacy RouteOption to TransitPlanOption fallback
  factory TransitPlanOption.fromMock(
    RouteOption mock, {
    required LatLng origin,
    required LatLng destination,
    PassengerType passengerType = PassengerType.general,
    List<LatLng>? fallbackPath,
  }) {
    final prefString = mock.preference == RoutePreference.cheapest
        ? 'cheapest'
        : mock.preference == RoutePreference.fewestTransfers
        ? 'fewest_transfers'
        : 'fastest';

    return TransitPlanOption(
      preference: prefString,
      title: mock.title,
      summary: mock.summary,
      etaMinutes: mock.etaMinutes,
      fare: mock.fare,
      fareMax: mock.fareMax,
      fareDiscounted: mock.fareDiscounted,
      fareDiscountedMax: mock.fareDiscountedMax,
      fareEstimated: true,
      fareSource: 'Rough distance-based estimate (offline); verify before travel.',
      transfers: mock.transfers,
      modes: [mock.modeLabel],
      legs: [
        TransitLeg(
          type: 'ride',
          from: 'Your origin',
          to: 'Destination',
          minutes: mock.etaMinutes,
          modeLabel: mock.modeLabel,
          fare: mock.fare,
          fareMax: mock.fareMax,
          fareDiscounted: mock.fareDiscounted,
          fareDiscountedMax: mock.fareDiscountedMax,
          path: fallbackPath ?? [origin, destination],
        ),
      ],
      isMock: true,
    );
  }
}

/// What the planner API answered: routes, or an empty list with a [reason]
/// such as [outsideServiceAreaReason] (the data covers the City of Manila only).
class TransitPlanResult {
  final List<TransitPlanOption> options;
  final String? reason;
  final String? message;

  const TransitPlanResult({this.options = const [], this.reason, this.message});

  bool get isOutsideServiceArea => reason == outsideServiceAreaReason;
  bool get isServerError => reason == serverErrorReason;
}

/// Service that coordinates with the backend transit planner API,
/// falling back to local mocked calculations if the server is unreachable.
class TransitPlannerService {
  TransitPlannerService._();

  /// Resolves the API base URL based on runtime platform
  static String get effectiveBaseUrl {
    final configured = AppConstants.transitApiBaseUrl.trim();
    if (configured.isEmpty) return '';
    // In web browsers, 10.0.2.2 cannot be reached; translate to the loopback
    // address. 127.0.0.1 rather than "localhost": on Windows "localhost" can try
    // IPv6 first, and each request then waits for a timeout before IPv4 is used.
    if (kIsWeb && configured.contains('10.0.2.2')) {
      return configured.replaceAll('10.0.2.2', '127.0.0.1');
    }
    return configured;
  }

  /// Calls the transit planner API using a JSON body so coordinates are not
  /// placed in request URLs or routine access logs.
  ///
  /// Returns a list of real options on success, or `null` if the API is offline
  /// or unreachable. An empty list means the server answered with no routes
  /// (including trips outside Manila); use [planTransitResult] to tell why.
  static Future<List<TransitPlanOption>?> planTransit({
    required LatLng origin,
    required LatLng destination,
    PassengerType passengerType = PassengerType.general,
    DateTime? departureTime,
    Set<String> avoidModes = const {},
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final result = await planTransitResult(
      origin: origin,
      destination: destination,
      passengerType: passengerType,
      departureTime: departureTime,
      avoidModes: avoidModes,
      timeout: timeout,
    );
    if (result == null || result.isServerError) return null;
    return result.options;
  }

  /// Like [planTransit], but also reports the server's reason when it returns
  /// no options (for example [outsideServiceAreaReason], or [serverErrorReason]
  /// when the server answered with an HTTP error). Returns `null` only when the
  /// API is offline or unreachable.
  static Future<TransitPlanResult?> planTransitResult({
    required LatLng origin,
    required LatLng destination,
    PassengerType passengerType = PassengerType.general,
    DateTime? departureTime,
    Set<String> avoidModes = const {},
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final baseUrl = effectiveBaseUrl;
      if (baseUrl.isEmpty) return null;
      final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/plan');
      final request = <String, dynamic>{
        'from': '${origin.latitude},${origin.longitude}',
        'to': '${destination.latitude},${destination.longitude}',
        'passenger': passengerType.apiValue,
        if (departureTime != null) 'when': departureTime.toIso8601String(),
        if (avoidModes.isNotEmpty) 'avoid': avoidModes.join(','),
      };
      final response = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: json.encode(request),
          )
          .timeout(timeout);
      if (response.statusCode != 200) {
        debugPrint('Transit planner API returned HTTP ${response.statusCode}');
        return const TransitPlanResult(
          reason: serverErrorReason,
          message: 'The route planner ran into a problem. Please try again.',
        );
      }

      final dynamic decoded = json.decode(utf8.decode(response.bodyBytes));
      final List rawOptions;
      String? reason;
      String? message;
      if (decoded is List) {
        rawOptions = decoded;
      } else if (decoded is Map<String, dynamic> &&
          decoded['options'] is List) {
        rawOptions = decoded['options'] as List;
        reason = decoded['reason'] as String?;
        message = decoded['message'] as String?;
      } else {
        debugPrint('Transit planner API returned an invalid response shape');
        return null;
      }

      return TransitPlanResult(
        options: rawOptions
            .map(
              (item) =>
                  TransitPlanOption.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        reason: reason,
        message: message,
      );
    } catch (error) {
      debugPrint(
        'Transit planner API unavailable (${error.runtimeType}); using fallback routes.',
      );
      return null;
    }
  }

  /// Builds fallback options using RoutePlannerService when API is offline
  static List<TransitPlanOption> getFallbackOptions({
    required LatLng destination,
    required LatLng? userLocation,
    RoutePreference preference = RoutePreference.fastest,
    PassengerType passengerType = PassengerType.general,
    Set<String> avoidModes = const {},
    List<LatLng>? fallbackPath,
  }) {
    final origin = userLocation ?? const LatLng(14.5943, 120.9721);
    final mocked = RoutePlannerService.generateRouteOptions(
      destination: destination,
      userLocation: userLocation,
      preference: preference,
    );

    return mocked
        .where(
          (option) => !avoidModes.any(
            (mode) => option.modeLabel.toLowerCase().contains(mode),
          ),
        )
        .map(
          (m) => TransitPlanOption.fromMock(
            m,
            origin: origin,
            destination: destination,
            passengerType: passengerType,
            fallbackPath: fallbackPath,
          ),
        )
        .toList();
  }
}