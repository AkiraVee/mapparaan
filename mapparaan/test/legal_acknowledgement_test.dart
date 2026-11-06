import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapparaan/screens/auth_screen.dart';
import 'package:mapparaan/screens/legal_document_screen.dart';
import 'package:mapparaan/legal/legal_documents.dart';

void main() {
  testWidgets('signup stays disabled until both notices are reviewed', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    await tester.ensureVisible(find.text("Don't have an account? Sign Up"));
    await tester.tap(find.text("Don't have an account? Sign Up"));
    await tester.pumpAndSettle();

    final createAccount = find.widgetWithText(FilledButton, 'Create Account');
    expect(tester.widget<FilledButton>(createAccount).onPressed, isNull);

    await _reviewDocument(tester, 'Read Terms of Service');
    final termsCheckbox = find.byType(CheckboxListTile).first;
    expect(tester.widget<CheckboxListTile>(termsCheckbox).onChanged, isNotNull);
    await tester.ensureVisible(termsCheckbox);
    await tester.tap(termsCheckbox);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(termsCheckbox).value, isTrue);
    expect(tester.widget<FilledButton>(createAccount).onPressed, isNull);

    await tester.ensureVisible(find.text('Read Data Privacy Notice'));
    await tester.tap(find.text('Read Data Privacy Notice'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -5000),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('legal-document-done')));
    await tester.pumpAndSettle();

    final privacyCheckbox = find.byType(CheckboxListTile).last;
    expect(
      tester.widget<CheckboxListTile>(privacyCheckbox).onChanged,
      isNotNull,
    );
    await tester.ensureVisible(privacyCheckbox);
    await tester.tap(privacyCheckbox);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(privacyCheckbox).value, isTrue);
    expect(tester.widget<FilledButton>(createAccount).onPressed, isNotNull);
  });

  testWidgets('a document cannot be marked read before reaching its end', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: LegalDocumentScreen(document: LegalDocuments.privacy)),
    );

    final done = find.byKey(const ValueKey('legal-document-done'));
    expect(tester.widget<FilledButton>(done).onPressed, isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -5000),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(done).onPressed, isNotNull);
  });
}

Future<void> _reviewDocument(WidgetTester tester, String linkLabel) async {
  await tester.ensureVisible(find.text(linkLabel));
  await tester.tap(find.text(linkLabel));
  await tester.pumpAndSettle();
  await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -5000));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('legal-document-done')));
  await tester.pumpAndSettle();
}
