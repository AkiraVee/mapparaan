import 'package:shared_preferences/shared_preferences.dart';

import 'route_planner_service.dart';

class TripHistoryEntry {
  final String id;
  final String origin;
  final String destination;
  final RoutePreference? preference;
  final int durationMinutes;
  final double fareEstimate;
  final DateTime createdAt;
  final String? routeSummary;
  final String? etaLabel;

  TripHistoryEntry({
    String? id,
    required this.origin,
    required this.destination,
    this.preference,
    this.durationMinutes = 0,
    this.fareEstimate = 0,
    DateTime? createdAt,
    this.routeSummary,
    this.etaLabel,
  })  : id = id ?? '${origin}::${destination}::${DateTime.now().toUtc().toIso8601String()}',
        createdAt = createdAt ?? DateTime.now();

  String get summary => routeSummary ?? '$origin → $destination';

  String get etaText => etaLabel ?? '${createdAt.toLocal().toString().substring(0, 16)}';

  static String _escapeField(String value) => value.replaceAll('::', '\u0000');

  static String _unescapeField(String value) => value.replaceAll('\u0000', '::');

  factory TripHistoryEntry.fromLegacyString(String raw) {
    final parts = raw.split('::');
    if (parts.length >= 7) {
      final pref = RoutePreference.values.firstWhere(
        (value) => value.name == parts[3],
        orElse: () => RoutePreference.fastest,
      );
      final candidateOrigin = parts.length > 7
          ? _unescapeField(parts.sublist(1, parts.length - 5).join('::'))
          : _unescapeField(parts[1]);
      final candidateDestination = parts.length > 7
          ? _unescapeField(parts[parts.length - 5])
          : _unescapeField(parts[2]);

      return TripHistoryEntry(
        id: parts[0],
        origin: candidateOrigin,
        destination: candidateDestination,
        preference: pref,
        durationMinutes: int.tryParse(parts[parts.length - 3]) ?? 0,
        fareEstimate: double.tryParse(parts[parts.length - 2]) ?? 0,
        createdAt: DateTime.tryParse(parts.last) ?? DateTime.now(),
      );
    }
    throw FormatException('Invalid trip-history value: $raw');
  }

  String serialize() =>
      '$id::${_escapeField(origin)}::${_escapeField(destination)}::${preference?.name ?? RoutePreference.fastest.name}::${durationMinutes}::${fareEstimate}::${createdAt.toUtc().toIso8601String()}';
}

class TripHistoryService {
  static const String _key = 'trip_history';
  static final List<TripHistoryEntry> _entries = <TripHistoryEntry>[];

  static List<TripHistoryEntry> get entries => List.unmodifiable(_entries);

  static Future<List<TripHistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const <String>[];
    final loaded = raw.map(TripHistoryEntry.fromLegacyString).toList();
    _entries
      ..clear()
      ..addAll(loaded);
    return List.unmodifiable(loaded);
  }

  static Future<void> addEntry(TripHistoryEntry entry) async {
    final current = await load();
    final updated = [...current, entry];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      updated.map((item) => item.serialize()).toList(),
    );
    _entries
      ..clear()
      ..addAll(updated);
  }
}
