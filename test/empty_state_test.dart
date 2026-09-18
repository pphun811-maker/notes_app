import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/design.dart';
import 'package:notes_app/mobile/home_page.dart';
import 'package:notes_app/mobile/widgets.dart';
import 'package:notes_app/notes_store.dart';
import 'package:notes_app/strings.dart';

/// The empty and no-match screens, neither of which has ever been drawn on the phone.
///
/// The folder always has notes in it, so "还没有笔记" had never been seen - and the line it
/// carried ("点右下角的『新建』") had been wrong ever since the floating button was removed and
/// the "+" moved to the top bar. A screen nobody looks at is a screen whose text can rot, so
/// both are rendered here against a temporary folder rather than by emptying the real one,
/// which Syncthing would have carried straight to the PC.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory empty;
  late Directory oneNote;

  setUpAll(() async {
    final String root = Directory.systemTemp.path;
    empty = Directory('$root${Platform.pathSeparator}notes_empty_probe');
    oneNote = Directory('$root${Platform.pathSeparator}notes_match_probe');
    for (final Directory dir in <Directory>[empty, oneNote]) {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await dir.create(recursive: true);
    }
    await File('${oneNote.path}${Platform.pathSeparator}购物清单.md')
        .writeAsString('# 牛奶\n鸡蛋');
  });

  Future<void> pumpHome(WidgetTester tester, Directory dir,
      {bool pumpUntilNote = true}) async {
    tester.view.physicalSize = const Size(1240, 2772);
    tester.view.devicePixelRatio = 3.5;
    tester.view.padding = const FakeViewPadding(top: 139);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NotesTheme.light(),
          home: NotesHomePage(
            store: NotesStore(dir),
            storageAccess: () async => true,
          ),
        ),
      );
      for (int i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (pumpUntilNote && find.byType(NoteRow).evaluate().isNotEmpty) break;
      }
    });
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('an empty folder says so, and says which folder it looked in',
      (WidgetTester tester) async {
    await pumpHome(tester, empty);

    expect(find.text(NotesStrings.emptyTitle), findsOneWidget);
    expect(find.textContaining('点顶栏'), findsOneWidget,
        reason: 'the old wording pointed at a button that no longer exists');
    expect(find.textContaining(empty.path), findsOneWidget,
        reason: 'the folder is the one piece of information that explains an empty list');
    expect(find.byType(NoteRow), findsNothing);

    // The top bar stays: its "+" is how the first note gets written, which is what the
    // empty state is telling the user to press.
    expect(find.text(NotesStrings.listTitle), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('a search that matches nothing says that, not "还没有笔记"',
      (WidgetTester tester) async {
    await pumpHome(tester, oneNote);
    expect(find.byType(NoteRow), findsOneWidget);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(NotesStrings.searchEmptyTitle), findsOneWidget);
    expect(find.text(NotesStrings.searchEmptyDetail), findsOneWidget);
    expect(find.text(NotesStrings.emptyTitle), findsNothing,
        reason: 'the folder is not empty, only the search is');

    // Clearing the query brings the note back rather than leaving the message up.
    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(NoteRow), findsOneWidget);
  });
}
