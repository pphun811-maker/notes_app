import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/desktop/desktop_design.dart';
import 'package:notes_app/desktop/home_page.dart';
import 'package:notes_app/markdown_controller.dart';
import 'package:notes_app/notes_store.dart';
import 'package:notes_app/strings.dart';

/// The keys that were added after F2/Delete were asked for, and the tab strip's right-click menu.
///
/// F2 and Delete cannot be driven on a real machine either - synthetic key events never reach
/// Flutter (`HANDOFF_PHASE7` section 6) - so this is the only place they are checked before the
/// user presses them. The tab menu *could* be clicked by hand, and was, but the part worth
/// locking down is the one that is easy to get wrong and hard to see: that closing "the others"
/// writes each of them before it throws their editors away.
///
/// The four traps from `desktop_conflict_test.dart` apply: real IO only inside `tester.runAsync`,
/// fixed pumps rather than `pumpAndSettle`, a re-pump after `runAsync`, and tearing the page down
/// so its folder watcher stops holding the test isolate open.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String cook = '菜谱';
  const String shopping = '购物清单';
  const String cookBody = '牛奶 200 毫升。\n鸡蛋两个。\n';
  const String shoppingBody = '牛奶、鸡蛋、面包\n咖啡豆\n';

  late Directory dir;
  late String cookPath;
  late String shoppingPath;

  String pathOf(String title) =>
      '${dir.path}${Platform.pathSeparator}$title.md';

  setUpAll(() async {
    dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}'
        'desktop_shortcuts_probe');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    cookPath = pathOf(cook);
    shoppingPath = pathOf(shopping);
    await File(cookPath).writeAsString(cookBody);
    await File(shoppingPath).writeAsString(shoppingBody);
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

  Finder tab(String title) =>
      find.byKey(ValueKey<String>('note-tab-${pathOf(title)}'));

  /// Pumps the page and leaves it sitting on the note list.
  Future<void> pumpPage(WidgetTester tester) async {
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
        if (find.text(cook).evaluate().isNotEmpty) break;
      }
    });
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Opens the note whose title is [title], with its editor loaded.
  ///
  /// The tap goes inside `runAsync` because opening a note is what starts the editor's read of
  /// the file, and IO started in the fake-async zone never finishes (HANDOFF_PHASE8 section 6.5).
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The title held by the field of the pane on screen, or null while there is none.
  ///
  /// The stack keeps every open note's pane built but skips the ones that are not on screen, so
  /// a finder with the defaults sees exactly one of these: the note being looked at.
  String? currentTitle(WidgetTester tester) {
    final Finder field = find.byKey(const ValueKey<String>('note-title-field'));
    if (field.evaluate().isEmpty) return null;
    return tester.widget<TextField>(field).controller?.text;
  }

  Future<void> openNote(WidgetTester tester, String title) async {
    await tester.runAsync(() async {
      await tester.tap(find.text(title).first);
      await tester.pump();
      // The pane for a note that was not open is created by the next frame, and building it is
      // what starts the read of its file - so what says the note is up is its own name appearing
      // in the title field, not a fixed wait.
      for (int i = 0; i < 400 && currentTitle(tester) != title; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
      expect(currentTitle(tester), title,
          reason: 'the note that was opened has to be up before it is used');
    });
    await settle(tester);
  }

  // --- F2 -------------------------------------------------------------------

  testWidgets('F2 puts the caret in the title with the whole name selected',
      (WidgetTester tester) async {
    await pumpPage(tester);
    await openNote(tester, cook);

    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await settle(tester);

    final TextField title = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('note-title-field')),
    );
    expect(FocusManager.instance.primaryFocus, title.focusNode,
        reason: 'the key should have moved the caret into the title');
    expect(
      title.controller!.selection,
      TextSelection(
        baseOffset: 0,
        extentOffset: title.controller!.text.length,
      ),
      reason: 'the whole name is selected, so typing replaces it',
    );
  });

  // --- Delete ---------------------------------------------------------------

  testWidgets('Delete asks before it deletes the note on screen',
      (WidgetTester tester) async {
    await pumpPage(tester);
    await openNote(tester, cook);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await settle(tester);

    expect(find.text(NotesStrings.confirmDeleteOne), findsOneWidget);
    expect(find.text(NotesStrings.desktopDeleteDetail(cook)), findsOneWidget);
  });

  testWidgets('Delete in the middle of a sentence still deletes a character',
      (WidgetTester tester) async {
    await pumpPage(tester);
    await openNote(tester, cook);

    await tester.tap(find.byKey(const ValueKey<String>('note-body-field')));
    await settle(tester);

    final TextField field = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('note-body-field')),
    );
    final MarkdownEditingController body =
        field.controller as MarkdownEditingController;
    body.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    final String before = body.text;

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await settle(tester);

    expect(find.text(NotesStrings.confirmDeleteOne), findsNothing,
        reason: 'the key belongs to the field while the caret is in it');
    expect(body.text.length, before.length - 1,
        reason: 'the character after the caret is what should have gone');
    expect(File(cookPath).existsSync(), isTrue,
        reason: 'nothing was deleted from the folder');
  });

  // --- the tab strip's right-click menu -------------------------------------

  testWidgets('a right-click on a tab offers the tab menu',
      (WidgetTester tester) async {
    await pumpPage(tester);
    await openNote(tester, cook);

    await tester.tap(tab(cook), buttons: kSecondaryMouseButton);
    await settle(tester);

    expect(find.text(NotesStrings.desktopMenuCloseTab), findsOneWidget);
    expect(find.text(NotesStrings.desktopMenuCloseOthers), findsOneWidget);
    expect(find.text(NotesStrings.desktopMenuReveal), findsOneWidget);
  });

  testWidgets('关闭 closes that one tab and nothing else',
      (WidgetTester tester) async {
    await pumpPage(tester);
    await openNote(tester, cook);
    await openNote(tester, shopping);

    await tester.tap(tab(cook), buttons: kSecondaryMouseButton);
    await settle(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text(NotesStrings.desktopMenuCloseTab));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await settle(tester);

    expect(tab(cook), findsNothing);
    expect(tab(shopping), findsOneWidget,
        reason: 'the other tab is the one that should be left alone');
    expect(File(cookPath).existsSync(), isTrue,
        reason: 'closing a tab is not deleting a note');
  });

  testWidgets('关闭其它 leaves the tab it was opened on, and writes the rest',
      (WidgetTester tester) async {
    await pumpPage(tester);
    await openNote(tester, cook);

    // Everything from the typing to the click on the menu item happens inside one `runAsync`, so
    // the note is still unsaved when that click runs: the autosave is half a second away, and in
    // the fake zone its timer would fire on the *test* clock instead and start a real write that
    // never finishes (HANDOFF_PHASE8 section 6.5). That is what makes this a test of the write on
    // the way out rather than of the autosave - and the check just before the click says so out
    // loud, so a run where the autosave did get there first fails instead of passing quietly.
    //
    // The note that is typed into is the one that gets closed, so the pane being flushed is the
    // one holding unsaved text, and the tab being left open is the one that was never touched.
    const String typed = '再买点咖啡豆';
    await tester.runAsync(() async {
      await tester.enterText(
        find.byKey(const ValueKey<String>('note-body-field')),
        '$cookBody$typed\n',
      );
      await tester.pump();

      // A second note, to have something for the menu item to leave open.
      await tester.tap(find.text(shopping).first);
      await tester.pump();
      for (int i = 0; i < 400 && currentTitle(tester) != shopping; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
      expect(currentTitle(tester), shopping,
          reason: 'the note that was opened has to be up before the menu is used');

      await tester.tap(tab(shopping), buttons: kSecondaryMouseButton);
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(File(cookPath).readAsStringSync(), isNot(contains(typed)),
          reason: 'if the autosave has already run, this proves nothing');

      await tester.tap(find.text(NotesStrings.desktopMenuCloseOthers));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await settle(tester);

    expect(tab(shopping), findsOneWidget);
    expect(tab(cook), findsNothing);
    expect(File(cookPath).readAsStringSync(), contains(typed),
        reason: 'the tab that was closed had to be written on the way out');
    expect(File(shoppingPath).readAsStringSync(), isNot(contains(typed)),
        reason: 'and the note that was left open is not the one that was written');
  });
}
