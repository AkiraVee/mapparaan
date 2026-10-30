import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapparaan/services/manila_boundary_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'loads the administrative polygon and checks city edge coordinates',
    () async {
      final boundary = await ManilaBoundaryService.load();

      expect(boundary.contains(const LatLng(14.59, 120.976)), isTrue);
      expect(boundary.contains(const LatLng(14.6567, 121.0287)), isFalse);
      expect(boundary.contains(boundary.outerRings.first.first), isTrue);
    },
  );

  test('excludes polygon holes while including their boundary', () {
    final boundary = ManilaBoundary.fromGeoJson({
      'type': 'Polygon',
      'coordinates': [
        [
          [120.0, 14.0],
          [121.0, 14.0],
          [121.0, 15.0],
          [120.0, 15.0],
          [120.0, 14.0],
        ],
        [
          [120.4, 14.4],
          [120.6, 14.4],
          [120.6, 14.6],
          [120.4, 14.6],
          [120.4, 14.4],
        ],
      ],
    });

    expect(boundary.contains(const LatLng(14.2, 120.2)), isTrue);
    expect(boundary.contains(const LatLng(14.5, 120.5)), isFalse);
    expect(boundary.contains(const LatLng(14.4, 120.5)), isTrue);
  });
}
