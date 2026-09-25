import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mapparaan/main.dart';

void main() {
  testWidgets('Home screen loads', (WidgetTester tester) async {
    await tester.pumpWidget(const MapparaanApp());

    // Confirm the app builds without crashing.
    expect(find.byType(MapparaanApp), findsOneWidget);
  });
}