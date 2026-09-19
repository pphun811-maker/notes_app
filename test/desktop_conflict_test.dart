import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/desktop/desktop_design.dart';
import 'package:notes_app/desktop/home_page.dart';
import 'package:notes_app/notes_store.dart';
import 'package:notes_app/strings.dart';

/// The Windows interface's conflict-copy notice, driven against a folder of its own.
///
/// **A temp folder and never `D:\Notes`.** To see this notice at all a conflict copy has to
/// exist, and one written into the real notes folder is a file Syncthing carries to the user's
/// phone. The whole point of the notice is that the app must cope with copies arriving, so the
/// tests bring their own.
///
/// Same three traps as `layout_probe_test.dart`, which this is modelled on: `testWidgets` runs
/// inside a FakeAsync zone so real file IO only completes inside `tester.runAsync`; the page
/// keeps something animating, so `pumpAndSettle` hangs and fixed pumps are used instead; and
/// frames pumped inside `runAsync` do not advance the fake clock, so the page is pumped again
/// afterwards.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String copyName = '欢迎.sync-conflict-20260920-031500-EPZ7ICC.md';
  late Directory dir;

  setUpAll(() async {
    dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}'
        'desktop_conflict_probe');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    await File('${dir.path}${Platform.pathSeparator}欢迎.md')
        .writeAsString('# 欢迎使用 Notes\n\n正文。');
    await File('${dir.path}${Platform.pathSeparator}$copyName')
        .writeAsString('手机上写的那一版');
  });

  tearDownAll(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Pumps the page and waits for the notes to arrive over real IO.
  Future<void> pumpPage(WidgetTester tester) async {
    // A fourth trap, and the one that cost the most time here: the Windows page *watches the
    // notes folder*. That is a live `Directory.watch` subscription, and leaving it running
    // keeps the test isolate alive - all three tests pass and then `flutter test` hangs for
    // ever with no output at all. Tearing the page down runs `dispose`, which cancels it.
    addTearDown(() async {
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
    });

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: NotesHomePage(
            store: NotesStore(dir),
            accent: SystemAccent.fallback,
          ),
        ),
      );
      for (int i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (find.text(NotesStrings.conflictsFound(1)).evaluate().isNotEmpty) {
          break;
        }
      }
    });
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('the copy is announced, and is never listed as a note',
      (WidgetTester tester) async {
    await pumpPage(tester);

    expect(find.text(NotesStrings.conflictsFound(1)), findsOneWidget,
        reason: 'the strip has to say a copy is there');
    expect(find.text(NotesStrings.desktopConflictsView), findsOneWidget);

    // The note itself is listed once. The copy's generated name - which is what the sidebar
    // would show as its "title" - must be nowhere near the list.
    expect(find.text('欢迎'), findsWidgets);
    expect(find.textContaining('sync-conflict'), findsNothing,
        reason: 'a copy is not a note and must never be listed as one');
    expect(find.text(NotesStrings.desktopEmptyNote), findsNothing);
  });

  testWidgets('查看 lists the copy and says which note it belongs to',
      (WidgetTester tester) async {
    await pumpPage(tester);

    await tester.tap(find.text(NotesStrings.desktopConflictsView));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text(NotesStrings.conflicts), findsWidgets,
        reason: 'the dialog names itself');
    expect(find.text(NotesStrings.desktopConflictBelongsTo('欢迎')), findsOneWidget,
        reason: 'the generated file name is unreadable on its own');
    expect(find.text(copyName), findsOneWidget,
        reason: 'the user has to be able to find the actual file');
    expect(find.text(NotesStrings.conflictsExplain), findsOneWidget);
    expect(find.text(NotesStrings.desktopMenuReveal), findsOneWidget);
    expect(find.text(NotesStrings.desktopConflictsClose), findsOneWidget);
  });

  testWidgets('the note list is untouched by the copy being there',
      (WidgetTester tester) async {
    await pumpPage(tester);

    // Inside `runAsync`, or the real file IO never completes: `testWidgets` runs its body in a
    // FakeAsync zone, and a bare `await` on a file there hangs the run with no output at all.
    late List<String> titles;
    late List<String> copies;
    await tester.runAsync(() async {
      final NotesStore store = NotesStore(dir);
      titles = (await store.listNotes()).map((Note n) => n.title).toList();
      copies = (await store.listConflictCopies())
          .map((Note n) => n.file.uri.pathSegments.last)
          .toList();
    });

    expect(titles, <String>['欢迎']);
    expect(copies, <String>[copyName]);
  });
}
