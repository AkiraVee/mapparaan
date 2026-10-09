import 'package:mapparaan/services/place_search_service.dart';
import 'package:mapparaan/services/route_planner_service.dart';

enum PassengerType { general, student, senior, pwd }

class MapparaanIntent {
  final String rawQuery;
  final String? origin;
  final String? destination;
  final String? preference;

  const MapparaanIntent({
    required this.rawQuery,
    this.origin,
    this.destination,
    this.preference,
  });
}

class AiQueryResolution {
  final String rawQuery;
  final String? origin;
  final String? destination;
  final RoutePreference? preference;
  final PassengerType passengerType;

  const AiQueryResolution({
    required this.rawQuery,
    this.origin,
    this.destination,
    this.preference,
    this.passengerType = PassengerType.general,
  });

  static AiQueryResolution fromQuery(String rawQuery) {
    final parsed = AiAssistantService.parse(rawQuery);
    return AiQueryResolution(
      rawQuery: rawQuery,
      origin: parsed.origin,
      destination: parsed.destination,
      preference: _preferenceFromString(parsed.preference),
      passengerType: PassengerType.general,
    );
  }

  static RoutePreference? _preferenceFromString(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'fewest transfers':
      case 'least transfers':
        return RoutePreference.fewestTransfers;
      case 'cheapest':
        return RoutePreference.cheapest;
      case 'fastest':
        return RoutePreference.fastest;
      default:
        return null;
    }
  }
}

class SearchSelection {
  final PlaceResult place;
  final AiQueryResolution? resolution;

  const SearchSelection({
    required this.place,
    this.resolution,
  });
}

class AiAssistantService {
  static const List<String> _preferenceKeywords = [
    'fewest transfers',
    'least transfers',
    'cheapest',
    'fastest',
  ];

  static MapparaanIntent parse(String rawQuery) {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      return MapparaanIntent(rawQuery: query);
    }

    final normalized = query.toLowerCase();
    String? preference;
    for (final keyword in _preferenceKeywords) {
      if (normalized.contains(keyword)) {
        preference = keyword;
        break;
      }
    }

    String cleanQuery = query;
    if (preference != null) {
      cleanQuery = cleanQuery
          .replaceFirst(RegExp(RegExp.escape(preference), caseSensitive: false), '')
          .trim();
    }

    String? origin;
    String? destination;

    final fromMatch = RegExp(
      r'\bfrom\s+(.+?)\s+\bto\b\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(cleanQuery);
    if (fromMatch != null) {
      origin = fromMatch.group(1)?.trim();
      destination = fromMatch.group(2)?.trim();
    } else {
      final toMatch = RegExp(
        r'\bto\s+(.+)$',
        caseSensitive: false,
      ).firstMatch(cleanQuery);
      if (toMatch != null) {
        final beforeTo = cleanQuery.substring(0, toMatch.start).trim();
        final afterTo = toMatch.group(1)?.trim();
        if (beforeTo.isNotEmpty && beforeTo != 'to') {
          origin = beforeTo;
        }
        destination = afterTo;
      }

      if (destination == null) {
        final destinationMatch = RegExp(
          r'\b(?:find|search|look for|goto|go to|punta sa|para sa|travel to)\s+(.+)$',
          caseSensitive: false,
        ).firstMatch(cleanQuery);
        if (destinationMatch != null) {
          destination = destinationMatch.group(1)?.trim();
        }
      }

      if (destination == null) {
        final simpleMatch = RegExp(
          r'\b(?:going to|to)\s+(.+)$',
          caseSensitive: false,
        ).firstMatch(cleanQuery);
        if (simpleMatch != null) {
          destination = simpleMatch.group(1)?.trim();
        }
      }
    }

    if (destination == null && origin == null) {
      destination = cleanQuery;
    }

    return MapparaanIntent(
      rawQuery: query,
      origin: origin,
      destination: destination,
      preference: preference,
    );
  }

  static Future<List<PlaceResult>> resolveQuery(String rawQuery) async {
    final intent = parse(rawQuery);
    final target = intent.destination ?? intent.origin ?? rawQuery.trim();
    if (target.isEmpty) return const [];
    return PlaceSearchService.search(target);
  }
}
