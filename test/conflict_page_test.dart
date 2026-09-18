import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/design.dart';
import 'package:notes_app/mobile/conflict_page.dart';
import 'package:notes_app/mobile/home_page.dart';
import 'package:notes_app/mobile/widgets.dart';
import 'package:notes_app/notes_store.dart';
import 'package:notes_app/strings.dart';

/// The conflict-copy path, end to end through the widgets.
///
/// The bug this pins down was found by reading the folder, not by using the app: Syncthing
/// writes `xxx.sync-conflict-<stamp>.md` next to a note both devices changed, and the list
/// page used to draw it as an ordinary note with a title made of digits. The file may hold the
/// only copy of what was typed on the other device, so "hidden from the list" and "reachable
/// from somewhere" both have to hold - each of those is one assertion below.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('notes_app/storage');
  const String copyName = '甲.sync-conflict-20260918-053116-EPZ7ICC.md';
  late Directory dir;

  setUpAll(() async {
    dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}'
        'notes_conflict_probe');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
    await File('${dir.path}${Platform.pathSeparator}甲.md')
        .writeAsString('# 甲的正文');
    await File('${dir.path}${Platform.pathSeparator}乙.md')
        .writeAsString('# 乙的正文');
    await File('${dir.path}${Platform.pathSeparator}$copyName')
        .writeAsString('# 甲的另一份\n来自电脑的内容');
  });

  void configure(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall call) async =>
          call.method == 'hasStorageAccess' ? true : null,
    );
    tester.view.physicalSize = const Size(1240, 2772);
    tester.view.devicePixelRatio = 3.5;
    tester.view.padding = const FakeViewPadding(top: 139);
  }

  Future<void> pumpHome(WidgetTester tester) async {
    configure(tester);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NotesTheme.light(),
          home: NotesHomePage(store: NotesStore(dir)),
        ),
      );
      for (int i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (find.byType(NoteRow).evaluate().length >= 2) break;
      }
    });
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> openConflictPage(WidgetTester tester) async {
    configure(tester);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NotesTheme.light(),
          home: ConflictCopiesPage(store: NotesStore(dir)),
        ),
      );
      for (int i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (find.byType(NoteRow).evaluate().isNotEmpty) break;
      }
    });
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('the list shows the notes and not the copy, and says the copy exists',
      (WidgetTester tester) async {
    await pumpHome(tester);

    expect(find.byType(NoteRow), findsNWidgets(2),
        reason: 'the copy must not be drawn as a note');
    expect(find.text('甲'), findsOneWidget);
    expect(find.text('乙'), findsOneWidget);
    expect(find.text(copyName.substring(0, copyName.length - 3)), findsNothing,
        reason: 'the generated name must not appear as a title');

    expect(find.text(NotesStrings.conflictsFound(1)), findsOneWidget,
        reason: 'hiding the copy must not hide the fact that it is there');
  });

  testWidgets('tapping the banner opens the conflict page',
      (WidgetTester tester) async {
    await pumpHome(tester);

    await tester.tap(find.text(NotesStrings.conflictsFound(1)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The heading and the explanation need no file IO, so they are on screen as soon as the
    // push settles; the listing itself is covered above, where the page is pumped inside
    // `runAsync`.
    expect(find.text(NotesStrings.conflicts), findsOneWidget,
        reason: 'the page heading');
    expect(find.text(NotesStrings.conflictsExplain), findsOneWidget);
  });

  testWidgets('a copy is listed under the note it belongs to and opens',
      (WidgetTester tester) async {
    await openConflictPage(tester);

    // The row is named after the note, not after the generated file name.
    expect(find.byType(NoteRow), findsOneWidget);
    expect(find.text('甲'), findsOneWidget);

    await tester.tap(find.text('甲'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Only the push is checked here. The pushed page reads a real file, and a future created
    // outside `runAsync` never completes under the fake clock - the trap documented in
    // `selection_test.dart`. Its contents are covered by the test below, which starts inside
    // `runAsync` instead of navigating into it.
    expect(find.byType(ConflictCopyPage), findsOneWidget,
        reason: 'tapping a copy opens it');
  });

  testWidgets('an opened copy shows its contents, and its real file name',
      (WidgetTester tester) async {
    configure(tester);
    final File file = File('${dir.path}${Platform.pathSeparator}$copyName');

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NotesTheme.light(),
          home: ConflictCopyPage(
            store: NotesStore(dir),
            copy: Note(file: file, modified: DateTime.now(), preview: ''),
          ),
        ),
      );
      for (int i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (find.byType(SelectableText).evaluate().isNotEmpty) break;
      }
    });
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Both the copy's real file name and its contents are selectable text on this page, so
    // the assertion is over the set of them rather than over one widget.
    final Iterable<String?> shown = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((SelectableText text) => text.data);

    expect(shown, contains('# 甲的另一份\n来自电脑的内容'),
        reason: 'the whole point of the page is that the contents stay reachable');
    expect(shown, contains(copyName),
        reason: 'the generated file name is shown, just not as a title');
  });

  // Last in the file on purpose: `appSettings` is a singleton, so the dismissal this test
  // makes outlives it. Every test above needs the notice still on screen.
  testWidgets('the notice can be swiped away without touching the notes',
      (WidgetTester tester) async {
    await pumpHome(tester);
    expect(find.text(NotesStrings.conflictsFound(1)), findsOneWidget);

    await tester.drag(
      find.text(NotesStrings.conflictsFound(1)),
      const Offset(-600, 0),
    );
    await tester.pump();
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text(NotesStrings.conflictsFound(1)), findsNothing,
        reason: 'the notice is gone');
    expect(find.byType(NoteRow), findsNWidgets(2),
        reason: 'only the notice goes; the notes are untouched');
    expect(find.text('甲'), findsOneWidget);

    // The copy itself is still there - dismissing a notice must never delete anything.
    expect(
      File('${dir.path}${Platform.pathSeparator}$copyName').existsSync(),
      isTrue,
    );
  });
}
