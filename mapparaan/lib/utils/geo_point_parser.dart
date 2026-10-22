import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

LatLng parseGeoPointGeometry(Object? geometry) {
  late final LatLng point;
  if (geometry is Map) {
    if (geometry['type'] != 'Point') {
      throw const FormatException('Geometry is not a point');
    }

    final coordinates = geometry['coordinates'];
    if (coordinates is! List ||
        coordinates.length < 2 ||
        coordinates[0] is! num ||
        coordinates[1] is! num) {
      throw const FormatException('Invalid GeoJSON point coordinates');
    }
    point = LatLng(
      (coordinates[1] as num).toDouble(),
      (coordinates[0] as num).toDouble(),
    );
  } else if (geometry is String) {
    point = _parsePointString(geometry);
  } else {
    throw const FormatException('Unsupported point geometry encoding');
  }

  if (!point.latitude.isFinite ||
      !point.longitude.isFinite ||
      point.latitude < -90 ||
      point.latitude > 90 ||
      point.longitude < -180 ||
      point.longitude > 180) {
    throw const FormatException('Point coordinates are outside valid bounds');
  }
  return point;
}

LatLng _parsePointString(String geometry) {
  final wktMatch = RegExp(
    r'^POINT\s*\(\s*(-?[\d.eE+-]+)\s+(-?[\d.eE+-]+)\s*\)$',
    caseSensitive: false,
  ).firstMatch(geometry.trim());
  if (wktMatch != null) {
    return LatLng(
      double.parse(wktMatch.group(2)!),
      double.parse(wktMatch.group(1)!),
    );
  }

  final hex = geometry.trim();
  if (hex.length < 42 ||
      hex.length.isOdd ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
    throw const FormatException('Unsupported point geometry encoding');
  }
  final bytes = Uint8List.fromList([
    for (var index = 0; index < hex.length; index += 2)
      int.parse(hex.substring(index, index + 2), radix: 16),
  ]);
  final data = ByteData.sublistView(bytes);
  final endian = bytes[0] == 1 ? Endian.little : Endian.big;
  if (bytes[0] != 0 && bytes[0] != 1) {
    throw const FormatException('Invalid point geometry byte order');
  }

  final geometryType = data.getUint32(1, endian);
  if ((geometryType & 0x000000FF) != 1) {
    throw const FormatException('Geometry is not a point');
  }
  final hasSrid = (geometryType & 0x20000000) != 0;
  if (hasSrid && data.getUint32(5, endian) != 4326) {
    throw const FormatException('Point geometry must use SRID 4326');
  }
  final coordinateOffset = hasSrid ? 9 : 5;
  if (bytes.length < coordinateOffset + 16) {
    throw const FormatException('Point geometry data is incomplete');
  }
  final longitude = data.getFloat64(coordinateOffset, endian);
  final latitude = data.getFloat64(coordinateOffset + 8, endian);
  return LatLng(latitude, longitude);
}
