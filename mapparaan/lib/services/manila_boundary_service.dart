import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class ManilaBoundary {
  final List<List<List<LatLng>>> polygons;

  const ManilaBoundary(this.polygons);

  factory ManilaBoundary.fromGeoJson(Map<String, dynamic> geoJson) {
    final geometries = geoJson['type'] == 'FeatureCollection'
        ? (geoJson['features'] as List)
              .map((feature) => feature['geometry'])
              .toList()
        : [geoJson['type'] == 'Feature' ? geoJson['geometry'] : geoJson];
    final polygons = <List<List<LatLng>>>[];
    for (final geometry in geometries) {
      final type = geometry['type'];
      final rawPolygons = type == 'Polygon'
          ? [geometry['coordinates']]
          : type == 'MultiPolygon'
          ? geometry['coordinates']
          : throw const FormatException(
              'Unsupported Manila boundary geometry.',
            );

      for (final rawPolygon in rawPolygons as List) {
        final rings = <List<LatLng>>[];
        for (final rawRing in rawPolygon as List) {
          final ring = <LatLng>[];
          for (final rawPoint in rawRing as List) {
            if (rawPoint is! List ||
                rawPoint.length < 2 ||
                rawPoint[0] is! num ||
                rawPoint[1] is! num) {
              throw const FormatException(
                'Invalid Manila boundary coordinate.',
              );
            }
            final longitude = (rawPoint[0] as num).toDouble();
            final latitude = (rawPoint[1] as num).toDouble();
            if (!latitude.isFinite ||
                latitude < -90 ||
                latitude > 90 ||
                !longitude.isFinite ||
                longitude < -180 ||
                longitude > 180) {
              throw const FormatException(
                'Invalid Manila boundary coordinate.',
              );
            }
            ring.add(LatLng(latitude, longitude));
          }
          if (ring.length < 4) {
            throw const FormatException('Invalid Manila boundary ring.');
          }
          rings.add(ring);
        }
        if (rings.isEmpty) {
          throw const FormatException('Manila boundary polygon has no rings.');
        }
        polygons.add(rings);
      }
    }

    if (polygons.isEmpty) {
      throw const FormatException('Manila boundary has no polygons.');
    }
    return ManilaBoundary(polygons);
  }

  List<List<LatLng>> get outerRings =>
      polygons.map((polygon) => polygon.first).toList(growable: false);

  bool contains(LatLng point) {
    for (final polygon in polygons) {
      if (!_containsRing(point, polygon.first)) continue;
      final isInHole = polygon
          .skip(1)
          .any((ring) => _containsRing(point, ring) && !_isOnRing(point, ring));
      if (!isInHole) return true;
    }
    return false;
  }

  static bool _containsRing(LatLng point, List<LatLng> ring) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[j];
      final b = ring[i];
      if (_isOnSegment(point, a, b)) return true;
      if ((a.latitude > point.latitude) != (b.latitude > point.latitude) &&
          point.longitude <
              (b.longitude - a.longitude) *
                      (point.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude) {
        inside = !inside;
      }
    }
    return inside;
  }

  static bool _isOnRing(LatLng point, List<LatLng> ring) {
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      if (_isOnSegment(point, ring[j], ring[i])) return true;
    }
    return false;
  }

  static bool _isOnSegment(LatLng point, LatLng a, LatLng b) {
    const epsilon = 1e-10;
    final cross =
        (point.latitude - a.latitude) * (b.longitude - a.longitude) -
        (point.longitude - a.longitude) * (b.latitude - a.latitude);
    if (cross.abs() > epsilon) return false;
    return point.latitude >=
            (a.latitude < b.latitude ? a.latitude : b.latitude) - epsilon &&
        point.latitude <=
            (a.latitude > b.latitude ? a.latitude : b.latitude) + epsilon &&
        point.longitude >=
            (a.longitude < b.longitude ? a.longitude : b.longitude) - epsilon &&
        point.longitude <=
            (a.longitude > b.longitude ? a.longitude : b.longitude) + epsilon;
  }
}

class ManilaBoundaryService {
  ManilaBoundaryService._();

  static Future<ManilaBoundary>? _boundary;

  static Future<ManilaBoundary> load() {
    return _boundary ??= _loadBoundary();
  }

  static Future<ManilaBoundary> _loadBoundary() async {
    final encoded = await rootBundle.loadString(
      'data/reference/manila_boundary.geojson',
    );
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Manila boundary is not a GeoJSON object.');
    }
    return ManilaBoundary.fromGeoJson(decoded);
  }
}
