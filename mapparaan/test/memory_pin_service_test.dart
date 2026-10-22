import 'package:flutter_test/flutter_test.dart';
import 'package:mapparaan/services/memory_pin_service.dart';

void main() {
  group('parseMemoryPinPoint', () {
    test('parses a GeoJSON point returned by PostgREST', () {
      final point = parseMemoryPinPoint({
        'type': 'Point',
        'coordinates': [-122.4194, 37.7749],
      });

      expect(point.longitude, -122.4194);
      expect(point.latitude, 37.7749);
    });

    test('continues to parse WKT points', () {
      final point = parseMemoryPinPoint('POINT(-122.4194 37.7749)');

      expect(point.longitude, -122.4194);
      expect(point.latitude, 37.7749);
    });

    test('rejects malformed GeoJSON coordinates', () {
      expect(
        () => parseMemoryPinPoint({
          'type': 'Point',
          'coordinates': ['west', 37.7749],
        }),
        throwsFormatException,
      );
    });
  });
}
