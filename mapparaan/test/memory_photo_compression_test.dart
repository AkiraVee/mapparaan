import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapparaan/services/memory_photo_compression_service.dart';

void main() {
  late FlutterImageCompressPlatform originalPlatform;
  late _FakeImageCompressPlatform fakePlatform;

  setUp(() {
    originalPlatform = FlutterImageCompressPlatform.instance;
    fakePlatform = _FakeImageCompressPlatform();
    FlutterImageCompressPlatform.instance = fakePlatform;
  });

  tearDown(() {
    FlutterImageCompressPlatform.instance = originalPlatform;
  });

  test('retries with lower quality and emits JPEG without EXIF', () async {
    fakePlatform.outputForCall = (callIndex, quality) {
      return callIndex == 0
          ? Uint8List(MemoryPhotoCompressionService.maxUploadBytes + 1)
          : Uint8List(100);
    };

    final compressed = await MemoryPhotoCompressionService.compress(
      Uint8List.fromList([1, 2, 3]),
    );

    expect(compressed, hasLength(100));
    expect(fakePlatform.calls, hasLength(2));
    expect(fakePlatform.calls.first.quality, 82);
    expect(fakePlatform.calls.last.quality, 72);
    expect(fakePlatform.calls.first.format, CompressFormat.jpeg);
    expect(fakePlatform.calls.first.autoCorrectionAngle, isTrue);
    expect(fakePlatform.calls.first.keepExif, isFalse);
  });

  test('rejects output that remains above the upload limit', () async {
    final oversized = Uint8List(
      MemoryPhotoCompressionService.maxUploadBytes + 1,
    );
    fakePlatform.outputForCall = (_, _) => oversized;

    await expectLater(
      MemoryPhotoCompressionService.compress(Uint8List.fromList([1])),
      throwsFormatException,
    );
    expect(fakePlatform.calls, hasLength(20));
  });

  test('rejects empty input', () {
    expect(
      MemoryPhotoCompressionService.compress(Uint8List(0)),
      throwsFormatException,
    );
  });
}

class _FakeImageCompressPlatform extends UnsupportedFlutterImageCompress {
  final List<_CompressionCall> calls = [];
  Uint8List Function(int callIndex, int quality) outputForCall = (_, _) =>
      Uint8List(100);

  @override
  Future<Uint8List> compressWithList(
    Uint8List image, {
    int minWidth = 1920,
    int minHeight = 1080,
    int quality = 95,
    int rotate = 0,
    int inSampleSize = 1,
    bool autoCorrectionAngle = true,
    CompressFormat format = CompressFormat.jpeg,
    bool keepExif = false,
  }) async {
    calls.add(
      _CompressionCall(
        minWidth: minWidth,
        minHeight: minHeight,
        quality: quality,
        autoCorrectionAngle: autoCorrectionAngle,
        format: format,
        keepExif: keepExif,
      ),
    );
    return outputForCall(calls.length - 1, quality);
  }
}

class _CompressionCall {
  final int minWidth;
  final int minHeight;
  final int quality;
  final bool autoCorrectionAngle;
  final CompressFormat format;
  final bool keepExif;

  const _CompressionCall({
    required this.minWidth,
    required this.minHeight,
    required this.quality,
    required this.autoCorrectionAngle,
    required this.format,
    required this.keepExif,
  });
}
