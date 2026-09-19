import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/desktop/desktop_design.dart';
import 'package:notes_app/desktop/home_page.dart';
import 'package:notes_app/notes_store.dart';
import 'package:notes_app/strings.dart';

/// The Windows search box, driven against a folder of its own.
///
/// The point of these is the wiring, not the query language - `note_search_test.dart` covers
/// that on its own. What is checked here is that the page really reads the notes' *bodies* and
/// puts the matching line in the row: the bug being fixed was a search that could only ever see
/// a note's first line, which passed every pure test that was ever written about it.
///
/// A temp folder, never `D:\Notes` - and the same four traps as `desktop_conflict_test.dart`:
/// real IO only inside `tester.runAsync`, fixed pumps instead of `pumpAndSettle`, a re-pump
/// after `runAsync`, and tearing the page down so its folder watcher stops holding the test
/// isolate open.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String welcomeBody = '# 欢迎使用 Notes\n'
      '\n'
      '这篇笔记本身，就是电脑 D:\\Notes 文件夹里的一个普通文本文件。\n'
      '以后 Syncthing 会把这两个文件夹同步起来。';
  const String shoppingBody = '牛奶、鸡蛋、面包、咖啡豆';

  late Directory dir;

  setUpAll(() async {
    dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}'
        'desktop_search_probe');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    await File('${dir.path}${Platform.pathSeparator}欢迎.md')
        .writeAsString(welcomeBody);
    await File('${dir.path}${Platform.pathSeparator}购物清单.md')
        .writeAsString(shoppingBody);
  });

  tearDownAll(() async {
    // The page's folder watcher can still hold the directory for a moment after the last page
    // is disposed, and Windows refuses to delete a directory in use. A temp folder left behind
    // is not worth failing the run over.
    for (int i = 0; i < 10; i++) {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

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
        if (find.text('欢迎').evaluate().isNotEmpty) break;
      }
    });
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Types into the search box and waits for the notes' bodies to be read.
  ///
  /// The typing happens **inside `runAsync`**, which looks odd but is the whole point: the first
  /// keystroke is what starts reading the notes, and real file IO begun inside the fake-async
  /// zone never completes at all - the search would sit there filtered by first lines only, and
  /// the failure looks exactly like a broken search rather than a broken test.
  Future<void> search(WidgetTester tester, String query) async {
    await tester.runAsync(() async {
      await tester.enterText(find.byType(TextField).first, query);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('a word from the middle of a note finds that note',
      (WidgetTester tester) async {
    await pumpPage(tester);

    // Both notes are listed before anything is searched for.
    expect(find.text('欢迎'), findsOneWidget);
    expect(find.text('购物清单'), findsOneWidget);

    await search(tester, 'Syncthing');

    expect(find.text('欢迎'), findsOneWidget,
        reason: 'Syncthing is on the last line of this note, not its first');
    expect(find.text('购物清单'), findsNothing);
  });

  testWidgets('the row shows the line it was found on, not the first line',
      (WidgetTester tester) async {
    await pumpPage(tester);
    await search(tester, 'Syncthing');

    expect(find.text('以后 Syncthing 会把这两个文件夹同步起来。'), findsOneWidget,
        reason: 'a result that shows an unrelated first line looks like a mistake');
    expect(find.text('欢迎使用 Notes'), findsNothing);
  });

  testWidgets('a word only in a title still finds it, and shows the first line',
      (WidgetTester tester) async {
    await pumpPage(tester);
    await search(tester, '鸡蛋');
    expect(find.text('购物清单'), findsOneWidget);

    await search(tester, '标题:购物');
    expect(find.text('购物清单'), findsOneWidget);
    expect(find.text(shoppingBody), findsOneWidget,
        reason: 'the title matched, so there is nothing better to show than the first line');
  });

  testWidgets('a word the notes do not contain says so', (WidgetTester tester) async {
    await pumpPage(tester);
    await search(tester, '火箭燃料');

    expect(find.text('欢迎'), findsNothing);
    expect(find.text('购物清单'), findsNothing);
    expect(find.text(NotesStrings.searchEmptyTitle), findsOneWidget);
    expect(find.text(NotesStrings.searchEmptyDetail), findsOneWidget);
  });

  testWidgets('excluding a word takes that note out', (WidgetTester tester) async {
    await pumpPage(tester);

    await search(tester, '文件夹');
    expect(find.text('欢迎'), findsOneWidget);

    await search(tester, '文件夹 -Syncthing');
    expect(find.text('欢迎'), findsNothing,
        reason: 'the note contains both words, and one of them was excluded');
  });

  testWidgets('clearing the box brings every note back', (WidgetTester tester) async {
    await pumpPage(tester);

    await search(tester, 'Syncthing');
    expect(find.text('购物清单'), findsNothing);

    await search(tester, '');
    expect(find.text('欢迎'), findsOneWidget);
    expect(find.text('购物清单'), findsOneWidget);
  });
}
