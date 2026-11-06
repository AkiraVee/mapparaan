import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapparaan/screens/ai_chat_screen.dart';
import 'package:mapparaan/widgets/mapparaan_drawer.dart';

void main() {
  testWidgets('opens the existing AI chat from the home navigation drawer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          drawer: const MapparaanDrawer(),
          body: Builder(
            builder: (context) => IconButton(
              tooltip: 'Open navigation menu',
              icon: const Icon(Icons.menu),
              onPressed: Scaffold.of(context).openDrawer,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MapParaan AI'));
    await tester.pumpAndSettle();

    expect(find.byType(AiChatScreen), findsOneWidget);
  });
}
