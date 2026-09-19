import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/desktop/desktop_design.dart';
import 'package:notes_app/desktop/home_page.dart';
import 'package:notes_app/markdown_controller.dart';
import 'package:notes_app/notes_store.dart';
import 'package:notes_app/strings.dart';

/// Ctrl+F - finding a word inside the note that is open.
///
/// These matter more than usual: **this feature cannot be driven on a real machine at all.**
/// Synthetic key events never reach Flutter (HANDOFF_PHASE7 section 6; `SendInput` with
/// `KEYEVENTF_UNICODE` fails too), so there is no way to press Ctrl+F or type into the bar from
/// outside the app. A widget test is not a convenience here, it is the only way this is checked
/// before the user tries it.
///
/// The four traps from `desktop_conflict_test.dart` apply: real IO only inside `tester.runAsync`,
/// fixed pumps rather than `pumpAndSettle`, a re-pump after `runAsync`, and tearing the page down
/// so its folder watcher stops holding the test isolate open.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String noteTitle = '菜谱';
  const String noteBody = '# 菜谱\n'
      '\n'
      '牛奶 200 毫升。\n'
      '鸡蛋两个。\n'
      '再来一点牛奶。\n'
      '面粉适量。\n'
      '最后把牛奶倒进去。\n';

  late Directory dir;

  setUpAll(() async {
    dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}'
        'desktop_find_probe');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    await File('${dir.path}${Platform.pathSeparator}$noteTitle.md')
        .writeAsString(noteBody);
  });

  tearDownAll(() async {
    for (int i = 0; i < 10; i++) {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  /// Pumps the page, opens the note, and leaves the editor loaded.
  ///
  /// The two `runAsync` blocks are separate on purpose. `tester.tap` needs the row to be in a
  /// *built* tree, and nothing is rebuilt while real IO is running, so the list has to be pumped
  /// on screen first - and the tap then has to be inside `runAsync` again, because opening the
  /// note is what starts the editor's read of the file.
  Future<void> openNote(WidgetTester tester) async {
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
        if (find.text(noteTitle).evaluate().isNotEmpty) break;
      }
    });
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Twice, in fact: this note's own first line is its title, so the row's title and its
    // one-line preview hold the same word.
    expect(find.text(noteTitle), findsWidgets,
        reason: 'the note should be listed before it is opened');

    await tester.runAsync(() async {
      await tester.tap(find.text(noteTitle).first);
      // The pane is created by the *next* frame, and creating it is what starts the editor's
      // read of the file. Skipping this pump leaves that read started in the fake-async zone,
      // where it never finishes: the pane then sits on its spinner for ever, never builds the
      // find bar, and every test below fails as if the shortcut were broken.
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pressCtrlF(WidgetTester tester) async {
    // `controlLeft`, not `control`: `SingleActivator(control: true)` asks the keyboard whether
    // a *side* is held, and the generic key does not set that.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> typeInFind(WidgetTester tester, String term) async {
    await tester.enterText(
      find.byKey(const ValueKey<String>('note-find-field')),
      term,
    );
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The controller the note's body is drawn from - the last field on screen.
  MarkdownEditingController bodyController(WidgetTester tester) {
    final EditableText body =
        tester.widgetList<EditableText>(find.byType(EditableText)).last;
    return body.controller as MarkdownEditingController;
  }

  testWidgets('Ctrl+F opens the bar', (WidgetTester tester) async {
    await openNote(tester);

    expect(find.byKey(const ValueKey<String>('note-find-field')), findsNothing,
        reason: 'the bar is not there until it is asked for');

    await pressCtrlF(tester);
    expect(find.byKey(const ValueKey<String>('note-find-field')), findsOneWidget);
    expect(find.text(NotesStrings.findHint), findsOneWidget);
  });

  testWidgets('it counts every hit in the note', (WidgetTester tester) async {
    await openNote(tester);
    await pressCtrlF(tester);

    await typeInFind(tester, '牛奶');

    expect(find.text(NotesStrings.findCount(1, 3)), findsOneWidget,
        reason: '牛奶 appears on three separate lines, not just the first');
  });

  testWidgets('the arrows step through them and wrap', (WidgetTester tester) async {
    await openNote(tester);
    await pressCtrlF(tester);
    await typeInFind(tester, '牛奶');

    await tester.tap(find.byTooltip(NotesStrings.findNext));
    await tester.pump();
    expect(find.text(NotesStrings.findCount(2, 3)), findsOneWidget);

    await tester.tap(find.byTooltip(NotesStrings.findNext));
    await tester.pump();
    expect(find.text(NotesStrings.findCount(3, 3)), findsOneWidget);

    await tester.tap(find.byTooltip(NotesStrings.findNext));
    await tester.pump();
    expect(find.text(NotesStrings.findCount(1, 3)), findsOneWidget,
        reason: 'going past the last one comes back to the first');

    await tester.tap(find.byTooltip(NotesStrings.findPrevious));
    await tester.pump();
    expect(find.text(NotesStrings.findCount(3, 3)), findsOneWidget,
        reason: 'and back past the first goes to the last');
  });

  testWidgets('the caret lands on the hit being looked at',
      (WidgetTester tester) async {
    await openNote(tester);
    await pressCtrlF(tester);
    await typeInFind(tester, '牛奶');

    final MarkdownEditingController body = bodyController(tester);
    final TextSelection first = body.selection;
    expect(body.text.substring(first.start, first.end), '牛奶');
    expect(first.start, body.text.indexOf('牛奶'),
        reason: 'the caret starts at the first hit in the note');

    await tester.tap(find.byTooltip(NotesStrings.findNext));
    await tester.pump();

    final TextSelection second = body.selection;
    expect(second.start, greaterThan(first.start));
    expect(body.text.substring(second.start, second.end), '牛奶');
  });

  testWidgets('every hit is marked, and the current one stands out',
      (WidgetTester tester) async {
    await openNote(tester);
    await pressCtrlF(tester);
    await typeInFind(tester, '牛奶');

    final MarkdownEditingController body = bodyController(tester);
    expect(body.highlights.length, 3, reason: 'all three are marked');
    final Set<Color> colours =
        body.highlights.map(((int, int, Color) m) => m.$3).toSet();
    expect(colours.length, 2,
        reason: 'the one being looked at is drawn differently from the others');

    await tester.tap(find.byTooltip(NotesStrings.findNext));
    await tester.pump();
    expect(body.highlights.length, 3);
  });

  testWidgets('the marks go away when the bar is closed',
      (WidgetTester tester) async {
    await openNote(tester);
    await pressCtrlF(tester);
    await typeInFind(tester, '牛奶');
    expect(bodyController(tester).highlights, isNotEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byKey(const ValueKey<String>('note-find-field')), findsNothing);
    expect(bodyController(tester).highlights, isEmpty);
  });

  testWidgets('a word that is not there says so', (WidgetTester tester) async {
    await openNote(tester);
    await pressCtrlF(tester);
    await typeInFind(tester, '火箭燃料');

    expect(find.text(NotesStrings.findNoMatch), findsOneWidget);
    expect(bodyController(tester).highlights, isEmpty);
  });

  testWidgets('the search is case-insensitive', (WidgetTester tester) async {
    await openNote(tester);
    await pressCtrlF(tester);
    await typeInFind(tester, '菜谱');

    // Once in the heading, once in the note's own title field - the title is a separate field,
    // so what this checks is that a hit inside the body is found whatever its case.
    expect(find.text(NotesStrings.findCount(1, 1)), findsOneWidget);
  });
}
