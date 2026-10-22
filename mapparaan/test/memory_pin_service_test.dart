import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapparaan/utils/geo_point_parser.dart';

void main() {
  group('parseGeoPointGeometry', () {
    test('parses a GeoJSON point returned by PostgREST', () {
      final point = parseGeoPointGeometry({
        'type': 'Point',
        'coordinates': [-122.4194, 37.7749],
      });

      expect(point.longitude, -122.4194);
      expect(point.latitude, 37.7749);
    });

    test('continues to parse WKT points', () {
      final point = parseGeoPointGeometry('POINT(-122.4194 37.7749)');

      expect(point.longitude, -122.4194);
      expect(point.latitude, 37.7749);
    });

    test('rejects malformed GeoJSON coordinates', () {
      expect(
        () => parseGeoPointGeometry({
          'type': 'Point',
          'coordinates': ['west', 37.7749],
        }),
        throwsFormatException,
      );
    });

    test('rejects coordinates outside geographic bounds', () {
      expect(
        () => parseGeoPointGeometry({
          'type': 'Point',
          'coordinates': [200, 37.7749],
        }),
        throwsFormatException,
      );
    });

    test('parses EWKB points with SRID 4326', () {
      final data = ByteData(25)
        ..setUint8(0, 1)
        ..setUint32(1, 0x20000001, Endian.little)
        ..setUint32(5, 4326, Endian.little)
        ..setFloat64(9, 120.9842, Endian.little)
        ..setFloat64(17, 14.59, Endian.little);
      final encoded = [
        for (var i = 0; i < data.lengthInBytes; i++)
          data.getUint8(i).toRadixString(16).padLeft(2, '0'),
      ].join();

      final point = parseGeoPointGeometry(encoded);

      expect(point.longitude, closeTo(120.9842, 1e-8));
      expect(point.latitude, closeTo(14.59, 1e-8));
    });

    test('rejects EWKB points with an unexpected SRID', () {
      final data = ByteData(25)
        ..setUint8(0, 1)
        ..setUint32(1, 0x20000001, Endian.little)
        ..setUint32(5, 3857, Endian.little)
        ..setFloat64(9, 120.9842, Endian.little)
        ..setFloat64(17, 14.59, Endian.little);
      final encoded = [
        for (var i = 0; i < data.lengthInBytes; i++)
          data.getUint8(i).toRadixString(16).padLeft(2, '0'),
      ].join();

      expect(() => parseGeoPointGeometry(encoded), throwsFormatException);
    });
  });
}
