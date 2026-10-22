import 'package:supabase_flutter/supabase_flutter.dart';

class TripHistoryEntry {
  final String id;
  final String origin;
  final String destination;
  final String preference;
  final int durationMinutes;
  final double fareEstimate;
  final String? routeSummary;
  final DateTime createdAt;

  TripHistoryEntry({
    this.id = '',
    required this.origin,
    required this.destination,
    required this.preference,
    required this.durationMinutes,
    this.fareEstimate = 0,
    this.routeSummary,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get etaText {
    final elapsed = DateTime.now().difference(createdAt);
    if (elapsed.inDays > 0) return '${elapsed.inDays}d ago';
    if (elapsed.inHours > 0) return '${elapsed.inHours}h ago';
    if (elapsed.inMinutes > 0) return '${elapsed.inMinutes}m ago';
    return 'Just now';
  }
}

typedef TripRecord = TripHistoryEntry;

class TripHistoryService {
  static SupabaseClient? get _clientOrNull {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static Future<List<TripHistoryEntry>> load() => fetchTripHistory();

  static Future<List<TripHistoryEntry>> fetchTripHistory() async {
    final client = _clientOrNull;
    final userId = client?.auth.currentUser?.id;
    if (userId == null) return [];

    final List<dynamic> response = await client!
        .from('trip_history')
        .select(
          'id, origin_name, dest_name, preference, duration_minutes, '
          'fare_estimate, route_summary, created_at',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return response.map((row) {
      return TripHistoryEntry(
        id: row['id'].toString(),
        origin: row['origin_name'],
        destination: row['dest_name'],
        preference: row['preference'] ?? 'fastest',
        durationMinutes: row['duration_minutes'] ?? 0,
        fareEstimate: (row['fare_estimate'] as num?)?.toDouble() ?? 0.0,
        routeSummary: row['route_summary'] ?? '',
        createdAt: DateTime.parse(row['created_at']),
      );
    }).toList();
  }

  static Future<void> addEntry(TripHistoryEntry entry) => logTrip(
    origin: entry.origin,
    destination: entry.destination,
    preference: entry.preference,
    durationMinutes: entry.durationMinutes,
    fareEstimate: entry.fareEstimate,
    routeSummary: entry.routeSummary ?? '',
  );

  static Future<void> clear() async {
    final client = _clientOrNull;
    final userId = client?.auth.currentUser?.id;
    if (userId == null) return;
    await client!.from('trip_history').delete().eq('user_id', userId);
  }

  static Future<void> deleteEntry(String id) async {
    final client = _clientOrNull;
    final userId = client?.auth.currentUser?.id;
    if (userId == null) return;
    await client!
        .from('trip_history')
        .delete()
        .eq('user_id', userId)
        .eq('id', id);
  }

  static Future<void> logTrip({
    required String origin,
    required String destination,
    required String preference,
    required int durationMinutes,
    required double fareEstimate,
    required String routeSummary,
  }) async {
    final client = _clientOrNull;
    final userId = client?.auth.currentUser?.id;
    if (userId == null) return;

    await client!.from('trip_history').insert({
      'user_id': userId,
      'origin_name': origin,
      'dest_name': destination,
      'preference': preference,
      'duration_minutes': durationMinutes,
      'fare_estimate': fareEstimate,
      'route_summary': routeSummary,
    });
  }
}
