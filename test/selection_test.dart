import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/design.dart';
import 'package:notes_app/mobile/home_page.dart';
import 'package:notes_app/mobile/widgets.dart';
import 'package:notes_app/notes_store.dart';

/// Exercises multi-select mode, which the design specifies in
/// `design/final/v4_select.png` and HANDOFF_PHASE3 section 5.4.
///
/// This exists because the mode could not be driven from `adb`: neither
/// `input swipe x y x y <duration>` nor a raw `motionevent DOWN/UP` pair made the
/// page enter selection, so the behaviour is pinned down here instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('notes_app/storage');
  late Directory dir;

  setUpAll(() async {
    dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}'
        'notes_select_probe');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
    final Map<String, String> fixture = <String, String>{
      '甲': '甲的内容',
      '乙': '乙的内容',
      '丙': '丙的内容',
    };
    for (final MapEntry<String, String> note in fixture.entries) {
      final File file =
          File('${dir.path}${Platform.pathSeparator}${note.key}.md');
      await file.writeAsString(note.value);
    }
  });

  /// Builds the page with three notes loaded and no pending real IO.
  ///
  /// The real file IO that `_load` performs has to run inside `runAsync`, because
  /// `testWidgets` bodies otherwise run under a fake clock where a real `await`
  /// never completes.
  Future<void> pumpPage(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall call) async => call.method == 'hasStorageAccess' ? true : null,
    );
    tester.view.physicalSize = const Size(1240, 2772);
    tester.view.devicePixelRatio = 3.5;
    tester.view.padding = const FakeViewPadding(top: 139);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NotesTheme.light(),
          home: NotesHomePage(store: NotesStore(dir)),
        ),
      );
      for (int i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (find.byType(NoteRow).evaluate().length == 3) break;
      }
    });
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('long press enters multi-select and ticks that note',
      (WidgetTester tester) async {
    await pumpPage(tester);
    expect(find.byType(NoteRow), findsNWidgets(3));
    expect(find.textContaining('已选'), findsNothing,
        reason: 'the selection bar is not shown before selecting');

    await tester.longPress(find.byType(NoteRow).first);
    await tester.pump(const Duration(milliseconds: 50));

    // The bar replaces the header: "已选 1 篇", 全选, and a bin.
    expect(find.text('已选 1 篇'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.text('笔记'), findsNothing,
        reason: 'the big title gives way to the selection bar');
    expect(find.byIcon(Icons.add), findsNothing,
        reason: 'the new-note "+" is hidden while selecting');
    expect(find.byIcon(Icons.search), findsNothing,
        reason: 'the search icon is hidden while selecting');

    final NoteRow first = tester.widget<NoteRow>(find.byType(NoteRow).first);
    expect(first.selected, isTrue, reason: 'the long-pressed row is ticked');
    final NoteRow second = tester.widget<NoteRow>(find.byType(NoteRow).at(1));
    expect(second.selected, isFalse);
  });

  testWidgets('tapping rows adds and removes them',
      (WidgetTester tester) async {
    await pumpPage(tester);
    await tester.longPress(find.byType(NoteRow).first);
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byType(NoteRow).at(1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('已选 2 篇'), findsOneWidget);

    // Tapping an already-ticked row unticks it.
    await tester.tap(find.byType(NoteRow).at(1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('已选 1 篇'), findsOneWidget);
  });

  testWidgets('全选 selects everything and 取消全选 clears it',
      (WidgetTester tester) async {
    await pumpPage(tester);
    await tester.longPress(find.byType(NoteRow).first);
    await tester.pump(const Duration(milliseconds: 50));

    // The label's tap target must clear the bin's: the bin is painted later in
    // the Stack, so any overlap silently swallows taps meant for 全选. That is
    // exactly the bug this test was written to catch.
    final Finder selectAll = find.widgetWithText(TextButton, '全选');
    final Rect allRect = tester.getRect(selectAll);
    final Rect binRect = tester.getRect(find.byIcon(Icons.delete_outline));
    expect(allRect.right <= binRect.left, isTrue,
        reason: 'the 全选 target must not sit under the bin '
            '(全选 right=${allRect.right}, bin left=${binRect.left})');

    // A real tap, not a direct callback: the callback was already correct.
    await tester.tap(selectAll);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('已选 3 篇'), findsOneWidget);
    expect(find.text('取消全选'), findsOneWidget);

    // "取消全选" empties the selection, which leaves multi-select mode entirely.
    await tester.tap(find.widgetWithText(TextButton, '取消全选'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('已选'), findsNothing);
    expect(find.text('笔记'), findsOneWidget);

    // ...and entering it again still works.
    await tester.longPress(find.byType(NoteRow).first);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('已选 1 篇'), findsOneWidget);

    // The close button leaves multi-select mode.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('已选'), findsNothing);
    expect(find.text('笔记'), findsOneWidget);
    // The three top-bar icons come back.
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
  });

  testWidgets('deleting asks for confirmation first',
      (WidgetTester tester) async {
    await pumpPage(tester);
    await tester.longPress(find.byType(NoteRow).first);
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));

    // A confirmation dialog, not an immediate delete.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('删除这篇笔记？'), findsOneWidget);

    // Backing out leaves all three notes alone.
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(NoteRow), findsNWidgets(3));
    expect(dir.listSync().whereType<File>().length, 3);
  });
}
