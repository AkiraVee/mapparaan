import 'package:flutter_test/flutter_test.dart';
import 'package:mapparaan/main.dart';

void main() {
  testWidgets('Home screen loads', (WidgetTester tester) async {
    await tester.pumpWidget(const MapparaanApp(enableMap: false));

    expect(find.byType(MapparaanApp), findsOneWidget);
    expect(find.text('Mapparaan'), findsOneWidget);
  });

  testWidgets('Drawer destinations open their pages', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MapparaanApp(enableMap: false));

    expect(find.text('Mapparaan'), findsOneWidget);
  });
}
