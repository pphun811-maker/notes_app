import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/design.dart';
import 'package:notes_app/mobile/home_page.dart';
import 'package:notes_app/mobile/widgets.dart';
import 'package:notes_app/notes_store.dart';
import 'package:notes_app/strings.dart';

/// The permission screen, which has never once been shown on the phone.
///
/// This device grants "All files access" without asking, so `hasStorageAccess` has only ever
/// returned true and the branch below has never run: the app has always gone straight to the
/// list. A screen nobody has looked at is a screen that can break unnoticed - and it is
/// exactly the screen a fresh install, a reinstall, or a system update that drops the
/// permission would land on, at the moment the user can least afford a blank page.
///
/// The page is reached here through [NotesHomePage.storageAccess], because the real call
/// answers `true` without touching the channel on any non-Android host. What that leaves
/// uncovered is the Kotlin side; `MainActivity.kt` was read alongside this instead - the
/// channel is `notes_app/storage`, the three method names match the Dart strings exactly, and
/// "去授权" opens this app's own entry in the system's all-files-access screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  /// Flipped by the tests to act out the user granting the permission.
  bool granted = false;

  /// How many times the page has asked whether it may read the folder.
  int checks = 0;

  setUpAll(() async {
    dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}'
        'notes_permission_probe');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
    await File('${dir.path}${Platform.pathSeparator}甲.md')
        .writeAsString('# 甲的正文');
  });

  setUp(() {
    granted = false;
    checks = 0;
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1240, 2772);
    tester.view.devicePixelRatio = 3.5;
    tester.view.padding = const FakeViewPadding(top: 139);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NotesTheme.light(),
          home: NotesHomePage(
            store: NotesStore(dir),
            storageAccess: () async {
              checks++;
              return granted;
            },
          ),
        ),
      );
      for (int i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Lets a tapped button finish its work.
  ///
  /// Alternates the two clocks, and the order matters. A tap starts `_load`, whose
  /// continuation is queued as a microtask on the *fake* clock; only once that has run does
  /// the next real file call start, and that one needs real time. Waiting on real time first -
  /// the obvious way round - leaves the load stuck half-done, and the page looks as if the tap
  /// did nothing. One round advances the load by one step, and listing the folder is a whole
  /// chain of steps (`exists`, `list`, `stat`, `readAsString` per note), so it is a loop.
  Future<void> settle(WidgetTester tester) async {
    for (int round = 0; round < 30; round++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
    }
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('no permission means the guide, not the list',
      (WidgetTester tester) async {
    await pumpHome(tester);

    expect(find.text(NotesStrings.permissionTitle), findsOneWidget);
    expect(find.text(NotesStrings.permissionDetail), findsOneWidget);
    expect(find.text(NotesStrings.grantAccess), findsOneWidget);
    expect(find.text(NotesStrings.recheckAccess), findsOneWidget);

    expect(find.byType(NoteRow), findsNothing,
        reason: 'the note is there, but without permission the app must not claim to list it');
    expect(find.text(NotesStrings.listTitle), findsNothing);
  });

  testWidgets('再检查一次 stays on the guide while access is still refused',
      (WidgetTester tester) async {
    await pumpHome(tester);

    await tester.tap(find.text(NotesStrings.recheckAccess));
    await settle(tester);

    expect(find.text(NotesStrings.permissionTitle), findsOneWidget,
        reason: 'still refused: the guide stays rather than showing an empty list');
    expect(find.byType(NoteRow), findsNothing);
  });

  testWidgets('再检查一次 picks the notes up once access is given',
      (WidgetTester tester) async {
    await pumpHome(tester);
    expect(find.byType(NoteRow), findsNothing);

    // The user flips the switch in the system screen and comes back.
    granted = true;
    final int before = checks;
    await tester.tap(find.text(NotesStrings.recheckAccess));
    await settle(tester);

    expect(checks, greaterThan(before), reason: 'the button re-asks the platform');
    expect(find.text(NotesStrings.permissionTitle), findsNothing);
    expect(find.byType(NoteRow), findsOneWidget,
        reason: 'the notes appear without restarting the app');
  });
}
