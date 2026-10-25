import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapparaan/services/friend_sharing_service.dart';
import 'package:mapparaan/widgets/photo_sharing_dialog.dart';

void main() {
  testWidgets('keeps photo private until an accepted friend is selected', (
    tester,
  ) async {
    PhotoShareSelection? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<PhotoShareSelection>(
                  context: context,
                  builder: (_) => PhotoSharingDialog(
                    friends: const [
                      CommuterFriend(id: 'friend-id', name: 'Friend'),
                    ],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No friends are selected by default, so this photo stays private.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Selected friends will see the saved place name and exact map pin, along with the photo.',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(result?.friendIds, ['friend-id']);
    expect(result?.friendIds, isNotEmpty);
  });
}
