import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/design.dart';
import 'package:notes_app/mobile/home_page.dart';
import 'package:notes_app/notes_store.dart';
import 'package:notes_app/mobile/widgets.dart';

/// Locks the list page's geometry to the numbers in
/// `design/final/v5_light.png` and `HANDOFF_PHASE3.md` section 5.4.
///
/// The design is drawn on a 412 x 900 dp canvas whose origin is the *content*
/// area, so what this test asserts are the relationships the design actually
/// fixes: the card's internal padding, the row rhythm, and the text insets.
/// Those are independent of the phone's cutout and of how tall the bar is.
///
/// Three traps worth knowing before editing this file:
///
///  * `testWidgets` runs its body inside a FakeAsync zone, so a real `await` on
///    file IO there **never completes** and the test hangs printing nothing. The
///    page loads notes through real IO, so the load is driven inside
///    `tester.runAsync` and the fixture is written in `setUpAll`.
///  * `pumpAndSettle` also hangs, because the page keeps something animating.
///    Fixed-duration pumps are used instead.
///  * Frames pumped inside `runAsync` do not advance the fake clock, so frames
///    are pumped again once the real-async block has finished.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('notes_app/storage');
  late Directory dir;

  setUpAll(() async {
    dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}'
        'notes_layout_probe');    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
    final Map<String, String> fixture = <String, String>{
      '购物清单': '牛奶、鸡蛋、面包、咖啡豆',
      '会议记录': '讨论了第三季度的排期',
      '读书笔记': '第一章讲的是注意力机制',
    };
    for (final MapEntry<String, String> note in fixture.entries) {
      final File file = File('${dir.path}${Platform.pathSeparator}${note.key}.md');
      await file.writeAsString(note.value);
    }
  });

  testWidgets('the note card matches the designed geometry',
      (WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall call) async => call.method == 'hasStorageAccess' ? true : null,
    );

    // The user's phone, exactly as `adb shell dumpsys window` reports it:
    // 1240x2772 physical at density 3.5 -> 354.3 x 792 dp, a 139px display
    // cutout (39.7dp) at the top, and no bottom navigation-bar inset.
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
        if (find.text('购物清单').evaluate().isNotEmpty) break;
      }
    });
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final Finder header = find.byKey(const ValueKey<String>('notes-header'));
    expect(header, findsOneWidget, reason: 'the header should be on screen');

    final double headerTop = tester.getRect(header).top;
    final double headerHeight = tester.getRect(header).height;

    // Take the rows in the order they are actually rendered rather than assuming
    // which note lands first: the store sorts by modified time, and the three
    // fixture files can share a timestamp.
    final List<Rect> rows = find
        .byType(NoteRow)
        .evaluate()
        .map((Element e) => tester.getRect(find.byElementPredicate((Element x) => x == e)))
        .toList();
    expect(rows.length, 3, reason: 'the fixture has three notes');
    final Rect card = tester.getRect(find.byType(NoteCard).first);
    final Finder innerList = find.byType(ListView).at(1);
    final Rect inner = tester.getRect(innerList);
    final Rect titleInFirstRow = tester.getRect(
      find
          .descendant(
            of: find.byType(NoteRow).first,
            matching: find.byType(Text),
          )
          .first,
    );
    final Rect subtitleInFirstRow = tester.getRect(
      find
          .descendant(
            of: find.byType(NoteRow).first,
            matching: find.byType(Text),
          )
          .last,
    );

    for (final Rect r in rows) {
      debugPrint('row top=${r.top.toStringAsFixed(1)} h=${r.height.toStringAsFixed(1)}');
    }

    // Row rhythm: one row is 84dp, title-row to title-row.
    expect(rows[1].top - rows[0].top, closeTo(84, 0.01),
        reason: 'row pitch must be 84dp (design 5.4)');
    expect(rows[2].top - rows[1].top, closeTo(84, 0.01),
        reason: 'row pitch must be 84dp (design 5.4)');

    // Title top is 20dp into the row; the subtitle 28dp below the title.
    expect(titleInFirstRow.top - rows[0].top, closeTo(20, 0.01),
        reason: 'title sits 20dp into the row');
    expect(subtitleInFirstRow.top - titleInFirstRow.top, closeTo(28, 0.01),
        reason: 'subtitle is 28dp below the title (row 48 - title 20)');

    // Text is inset 34dp from the screen edge, measured absolutely: the design
    // quotes `TEXT_X = 34` on its 412dp canvas and the mock-up really does put
    // the first ink at 34.67dp, with the card already at 16dp.
    expect(titleInFirstRow.left, closeTo(NotesMetrics.rowTextLeft, 0.01),
        reason: 'row text starts 34dp from the screen edge (design 5.4)');
    expect(inner.left, closeTo(NotesMetrics.cardMargin, 0.01),
        reason: 'the card sits at the 16dp page margin');

    // The hairline fades out over the same 34dp..W-34dp span as the text.
    //
    // Measure the box that actually paints the line, not the divider widget:
    // a `RenderPadding` is itself full-width and only insets its *child*, so
    // measuring the padding reports the whole card and hides the real inset.
    final Finder hairline = find
        .descendant(
          of: find.byType(FadingDivider).first,
          matching: find.byType(DecoratedBox),
        )
        .first;
    final Rect divider = tester.getRect(hairline);
    expect(divider.left, closeTo(NotesMetrics.rowTextLeft, 0.01),
        reason: 'the separator starts where the text does (design 5.4)');
    expect(divider.height, closeTo(1, 0.01), reason: 'the hairline is 1dp');
    expect(divider.width,
        closeTo(354.3 - 2 * NotesMetrics.rowTextLeft, 0.05),
        reason: 'the separator ends at W - 34dp; the slack is 1240/3.5 rounding');

    // Three rows, two 1dp hairlines, and nothing else: the card's own 4dp/12dp
    // of padding lives on the wrapper, not on this list.
    expect(inner.height,
        closeTo(3 * NotesMetrics.rowHeight + 2 * NotesMetrics.dividerHeight, 0.01),
        reason: 'the shrink-wrapped list must not add its own padding');

    // The card starts 168dp below the header, per the design's card top.
    // Measure the card itself, not the list inside it: the card adds 4dp of top
    // padding, which would otherwise be mistaken for part of the gap.
    expect(card.top - headerTop - headerHeight, closeTo(168, 0.01),
        reason: 'card top must be 168dp below the header (design 5.4)');
    expect(card.height,
        closeTo(3 * NotesMetrics.rowHeight +
            2 * NotesMetrics.dividerHeight +
            NotesMetrics.cardPaddingTop +
            NotesMetrics.cardPaddingBottom, 0.01),
        reason: 'card height = rows + hairlines + 4dp/12dp padding (design 5.4)');

    // The header block itself is the designed 96dp plus the status bar inset.
    expect(headerHeight, closeTo(96 + 139 / 3.5, 0.01),
        reason: 'header is 96dp tall plus the status-bar inset');
  });
}
