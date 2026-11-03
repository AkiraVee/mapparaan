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
        'No friends are selected. This photo stays private; selecting a friend will also reveal its saved place and exact map pin.',
      ),
      findsOneWidget,
    );
    expect(find.text('Keep private'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Keep private'),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Sharing reveals this photo, its saved place, and the exact map pin to the selected friends. The location cannot be hidden separately.',
      ),
      findsOneWidget,
    );
    expect(find.text('Share with 1 friend'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Share with 1 friend'));
    await tester.pumpAndSettle();

    expect(result?.friendIds, ['friend-id']);
    expect(result?.friendIds, isNotEmpty);
  });

  testWidgets('existing photo shares can be made private', (tester) async {
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
                    initialFriendIds: const ['friend-id'],
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

    expect(find.text('Update sharing'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(find.text('Make private'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Make private'));
    await tester.pumpAndSettle();
    expect(result?.friendIds, isEmpty);
  });
}
