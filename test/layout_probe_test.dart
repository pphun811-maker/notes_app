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

    final Rect headerRect = tester.getRect(header);
    final double headerTop = headerRect.top;
    final double headerHeight = headerRect.height;

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

    // Row rhythm: the tightened pitch the user asked for.
    expect(rows[1].top - rows[0].top,
        closeTo(NotesMetrics.rowHeight + NotesMetrics.dividerHeight, 0.01),
        reason: 'row pitch = row + hairline');
    expect(rows[2].top - rows[1].top,
        closeTo(NotesMetrics.rowHeight + NotesMetrics.dividerHeight, 0.01),
        reason: 'row pitch = row + hairline');

    // Title top is 16dp into the row; the subtitle 22dp below the title.
    expect(titleInFirstRow.top - rows[0].top,
        closeTo(NotesMetrics.rowTitleTop, 0.01),
        reason: 'the title sits 16dp into the row');
    expect(subtitleInFirstRow.top - titleInFirstRow.top,
        closeTo(NotesMetrics.rowSubtitleTop - NotesMetrics.rowTitleTop, 0.01),
        reason: 'title-to-subtitle spacing was tightened from 28 to 22dp');

    // Text is inset 30dp from the screen edge, measured absolutely: the design
    // quoted `TEXT_X = 34` on its 412dp canvas, and the user pulled it in so the
    // hairlines can run wider than the text.
    expect(titleInFirstRow.left, closeTo(NotesMetrics.rowTextLeft, 0.01),
        reason: 'row text starts 30dp from the screen edge');
    expect(inner.left, closeTo(NotesMetrics.cardMargin, 0.01),
        reason: 'the card sits at the 16dp page margin');

    // The hairline runs wider than the text and fades out 24dp in from each edge.
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
    expect(divider.left, closeTo(NotesMetrics.dividerInset, 0.01),
        reason: 'the separator starts 24dp from the screen edge');
    expect(divider.height, closeTo(1, 0.01), reason: 'the hairline is 1dp');
    expect(divider.width,
        closeTo(354.3 - 2 * NotesMetrics.dividerInset, 0.05),
        reason: 'the separator ends 24dp from the right edge; '
            'the slack is 1240/3.5 rounding');

    // Three rows, two 1dp hairlines, and nothing else: the card's own 4dp/12dp
    // of padding lives on the wrapper, not on this list.
    expect(inner.height,
        closeTo(3 * NotesMetrics.rowHeight + 2 * NotesMetrics.dividerHeight, 0.01),
        reason: 'the shrink-wrapped list must not add its own padding');

    // The card's top edge is a fixed distance from the top of the page, NOT from
    // the bottom of the header. Measuring it absolutely is the whole point: the
    // original bug was reading `cardTop` as "below the header", which pushed it a
    // full header-height down and opened the dead band under the bar.
    // The three top-bar icons: "+", search, more. They replaced the floating
    // button, so their spacing is now the only way to reach "new note".
    final Rect plus = tester.getRect(find.byIcon(Icons.add));
    final Rect magnifier = tester.getRect(find.byIcon(Icons.search));
    final Rect more = tester.getRect(find.byIcon(Icons.more_horiz));
    for (final Rect r in <Rect>[plus, magnifier, more]) {
      expect(r.width, closeTo(24, 0.01), reason: 'all three icons are 24dp');
      expect(r.height, closeTo(24, 0.01), reason: 'all three icons are 24dp');
    }
    // Right to left: more, search, "+", evenly spaced 50dp apart.
    expect(more.center.dx - magnifier.center.dx, closeTo(50, 0.01),
        reason: 'more and search are 50dp apart');
    expect(magnifier.center.dx - plus.center.dx, closeTo(50, 0.01),
        reason: 'search and the new-note "+" are 50dp apart');
    // To the right of the title, so the "笔记" heading is never overlapped.
    expect(plus.left, greaterThan(NotesMetrics.headerLeft + 62.5),
        reason: 'the "+" clears the 31dp title');
    // The "+" shares the row with the other two icons.
    expect((plus.center.dy - magnifier.center.dy).abs(), lessThan(0.01),
        reason: 'the "+" sits on the same line as the search icon');

    // The card hangs directly off the header: a small sliver of page background,
    // not a whole screen. This is the relationship the user asked for, and it is
    // the one the original code got wrong by treating `cardTop` as an offset
    // below the header.
    expect(card.top - (headerTop + headerHeight),
        closeTo(NotesMetrics.cardGap, 0.01),
        reason: 'the card must sit just below the top bar, not mid-screen');
    expect(card.top, lessThan(200),
        reason: 'the card must stay near the top of the screen');
    expect(card.height,
        closeTo(3 * NotesMetrics.rowHeight +
            2 * NotesMetrics.dividerHeight +
            NotesMetrics.cardPaddingTop +
            NotesMetrics.cardPaddingBottom, 0.01),
        reason: 'card height = rows + hairlines + 4dp/12dp padding');

    // The bar is the tightened height plus the status-bar inset.
    expect(headerHeight, closeTo(NotesMetrics.barHeight + 139 / 3.5, 0.01),
        reason: 'the bar is 72dp tall plus the status-bar inset');
    expect(headerHeight, lessThan(200),
        reason: 'the header must stay compact - the user rejected the tall one');
  });
}
