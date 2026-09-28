// ignore_for_file: must_call_super
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:mapparaan/main.dart';

class _TestMapLibrePlatform extends MapLibreMethodChannel {
  @override
  void dispose() {
    // Platform views do not initialize native method channels during headless widget tests.
    // Avoid accessing uninitialized late _channel.
  }
}

void main() {
  setUp(() {
    MapLibrePlatform.createInstance = () => _TestMapLibrePlatform();
  });

  testWidgets('Home screen loads', (WidgetTester tester) async {
    await tester.pumpWidget(const MapparaanApp());

    // Confirm the app builds without crashing.
    expect(find.byType(MapparaanApp), findsOneWidget);
  });
}