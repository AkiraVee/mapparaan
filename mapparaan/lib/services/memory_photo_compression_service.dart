import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

class MemoryPhotoCompressionService {
  MemoryPhotoCompressionService._();

  static const int maxUploadBytes = 8 * 1024 * 1024;
  static const int maxDimension = 1600; // Restored this line!
  static const List<int> _qualityLevels = [82, 72, 62, 52, 42];
  static const List<int> _dimensionLimits = [1600, 1200, 900, 700];

  static Future<Uint8List> compress(Uint8List input) async {
    if (input.isEmpty) {
      throw const FormatException('The selected image is empty.');
    }

    for (final dimension in _dimensionLimits) {
      for (final quality in _qualityLevels) {
        final compressed = await FlutterImageCompress.compressWithList(
          input,
          minWidth: dimension,
          minHeight: dimension,
          quality: quality,
          format: CompressFormat.jpeg,
          autoCorrectionAngle: true,
          keepExif: false,
        );
        if (compressed.isNotEmpty && compressed.length <= maxUploadBytes) {
          return compressed;
        }
      }
    }

    throw const FormatException(
      'This image is too complex to compress under the 8 MB upload limit.',
    );
  }
}
