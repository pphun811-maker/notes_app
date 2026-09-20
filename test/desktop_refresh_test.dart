import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/desktop/desktop_design.dart';
import 'package:notes_app/desktop/home_page.dart';
import 'package:notes_app/markdown_controller.dart';
import 'package:notes_app/notes_store.dart';
import 'package:notes_app/strings.dart';

/// The status line's 刷新 button: reading the note again on demand.
///
/// The page already watches the folder, so the interesting parts are the two the watcher cannot
/// show: that pressing the button really does look at the file, and that it *says* which of the
/// two answers came back - "the folder still holds this version" is how the user finds out that
/// the sync has not delivered yet, and without it that case looks exactly like a dead button.
///
/// A temp folder, never `D:\Notes`. The four traps from `desktop_conflict_test.dart` apply, and
/// so does the one this file is really about: IO has to be started inside `tester.runAsync`,
/// because IO started in the fake-async zone never finishes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String title = '菜谱';
  const String body = '牛奶 200 毫升。\n';
  const String fromTheOtherMachine = '牛奶 200 毫升。\n鸡蛋两个。\n';

  late Directory dir;
  late String notePath;

  setUpAll(() async {
    dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}'
        'desktop_refresh_probe');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    notePath = '${dir.path}${Platform.pathSeparator}$title.md';
    await File(notePath).writeAsString(body);
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

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  String? currentTitle(WidgetTester tester) {
    final Finder field = find.byKey(const ValueKey<String>('note-title-field'));
    if (field.evaluate().isEmpty) return null;
    return tester.widget<TextField>(field).controller?.text;
  }

  /// Opens the note and leaves its editor loaded.
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
      await tester.pump();
      // The list is read from the folder asynchronously, so the row only exists once a frame
      // has been pumped after the read came back - waiting in real time alone builds nothing.
      for (int i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.text(title).evaluate().isNotEmpty) break;
      }
    });
    await settle(tester);
    expect(find.text(title), findsWidgets,
        reason: 'the note should be listed before it is opened');

    await tester.runAsync(() async {
      await tester.tap(find.text(title).first);
      await tester.pump();
      // Building the pane is what starts the read of the file.
      for (int i = 0; i < 400 && currentTitle(tester) != title; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
      expect(currentTitle(tester), title, reason: 'the note has to be up first');
    });
    await settle(tester);
    // The file has to be the one this editor just read, or the first test is measuring a race
    // with whatever wrote it last.
    expect(File(notePath).readAsStringSync(), body);
  }

  MarkdownEditingController bodyController(WidgetTester tester) {
    final TextField field = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('note-body-field')),
    );
    return field.controller! as MarkdownEditingController;
  }

  Finder refreshButton() =>
      find.byTooltip(NotesStrings.desktopRefreshTip);

  testWidgets('the 刷新 button is on the status line',
      (WidgetTester tester) async {
    await openNote(tester);

    expect(refreshButton(), findsOneWidget);
    expect(find.text(NotesStrings.desktopRefresh), findsOneWidget);
  });

  testWidgets('it says so when the folder holds nothing newer',
      (WidgetTester tester) async {
    await openNote(tester);

    await tester.runAsync(() async {
      await tester.tap(refreshButton());
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await settle(tester);

    expect(find.text(NotesStrings.refreshedNothingNew), findsOneWidget);
    expect(bodyController(tester).text, body,
        reason: 'nothing newer on disk means nothing to take');
  });

  testWidgets('it takes the version that has just arrived on disk',
      (WidgetTester tester) async {
    await openNote(tester);

    await tester.runAsync(() async {
      // What Syncthing arriving looks like from here: the file is simply different.
      await File(notePath).writeAsString(fromTheOtherMachine);
      // Straight to the button, on purpose. The page's own watcher waits 300 ms before it looks,
      // so pressing now is what makes the answer below the *button's* rather than the watcher's
      // - and the watcher's own check, when it does run, finds the editor already up to date.
      await tester.tap(refreshButton());
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await settle(tester);

    expect(bodyController(tester).text, fromTheOtherMachine,
        reason: 'the newer text should be the one on screen');
    expect(find.text(NotesStrings.refreshedNewest), findsOneWidget);
  });
}
