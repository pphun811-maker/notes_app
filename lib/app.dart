import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'design.dart';
import 'desktop/home_page.dart' as desktop;
import 'mobile/home_page.dart' as mobile;
import 'strings.dart';

/// The app shell: theme, title, and *which* UI to show.
///
/// The phone and the PC are going to look different from here on. Only the looks
/// are split; `notes_store.dart` stays shared and untouched, so the Syncthing
/// contract, the file format, and the unit tests are unaffected.
///
/// The desktop UI is the phase-2 interface, moved across unchanged and frozen for
/// now - the user wants Android finished first.
void main() {
  runApp(const NotesApp());
}

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilt when the user picks a theme from the Windows interface's own button. Following
    // the system is the starting point; picking one overrides it until they go back.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (BuildContext context, ThemeMode mode, Widget? _) {
        return MaterialApp(
          title: NotesStrings.appTitle,
          debugShowCheckedModeBanner: false,
          theme: NotesTheme.light(),
          darkTheme: NotesTheme.dark(),
          // The app follows the system setting until the user says otherwise.
          themeMode: mode,
          home: const _Root(),
        );
      },
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    // `defaultTargetPlatform` rather than `dart:io`'s `Platform`, so this also
    // behaves correctly under `flutter test`.
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => const mobile.NotesHomePage(),
      _ => const desktop.NotesHomePage(),
    };
  }
}
