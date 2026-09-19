/// The Windows interface's own design tokens.
///
/// **Deliberately not `lib/design.dart`.** That file's palette was sampled pixel by pixel from
/// ColorOS Notes on the user's OnePlus, and its metrics are the phone's dp - a 74dp list row, a
/// 44dp touch target. Reusing them would give a phone app in a big window, which is exactly
/// what the user asked us not to build. What the two interfaces do share is everything that is
/// not drawing: the data layer, the save rules, the Markdown renderer, the file-name rules and
/// the strings.
///
/// The look itself is one decision, recorded in `design/final/desktop_win_*.png`: nothing is
/// outlined, panels separate by tone, and the note's surface is the same colour as the selected
/// tab so the two read as one shape.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../design.dart';

/// The accent Windows is set to, and its dark-theme pairing.
///
/// The user asked the app to follow the system accent. This machine's is the default
/// `#0078D4`, but the point is that it is read rather than assumed.
class SystemAccent {
  const SystemAccent({required this.light, required this.dark});

  /// Windows' own defaults, used when the registry cannot be read or says nothing useful.
  /// A wrong accent is not worth failing a launch over.
  static const SystemAccent fallback = SystemAccent(
    light: Color(0xFF0078D4),
    dark: Color(0xFF4CC2FF),
  );

  final Color light;
  final Color dark;

  Color of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Reads `AccentPalette` out of the registry.
  ///
  /// Three formats are involved and they disagree, which is why this is spelled out.
  /// `…\Explorer\Accent\AccentPalette` is 32 bytes: eight shades, four bytes each, in
  /// R,G,B,A order. Windows pairs entry 3 (`#0078D4` on a default install) with the light
  /// theme and entry 1 (`#4CC2FF`) with the dark one. The `DWM\AccentColor` DWORD holds the
  /// same colour in ABGR order, which is a different value for the same shade - reading it
  /// without swapping the channels is how this goes wrong.
  static Future<SystemAccent> read() async {
    if (!Platform.isWindows) return fallback;
    try {
      final ProcessResult result = await Process.run('reg', <String>[
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent',
        '/v',
        'AccentPalette',
      ]);
      if (result.exitCode != 0) return fallback;
      final RegExpMatch? match = RegExp(r'REG_BINARY\s+([0-9A-Fa-f]+)')
          .firstMatch(result.stdout.toString());
      if (match == null) return fallback;
      final String raw = match.group(1)!;
      if (raw.length < 32) return fallback;
      Color shade(int index) {
        final int at = index * 8;
        return Color.fromARGB(
          255,
          int.parse(raw.substring(at, at + 2), radix: 16),
          int.parse(raw.substring(at + 2, at + 4), radix: 16),
          int.parse(raw.substring(at + 4, at + 6), radix: 16),
        );
      }

      return SystemAccent(light: shade(3), dark: shade(1));
    } on ProcessException {
      return fallback;
    }
  }
}

/// The colour set the Windows interface draws with, resolved for the current brightness.
class NotesDesktopPalette {
  const NotesDesktopPalette({
    required this.page,
    required this.frame,
    required this.surface,
    required this.ink,
    required this.sub,
    required this.faint,
    required this.hover,
    required this.line,
    required this.code,
    required this.bar,
    required this.field,
    required this.fieldLine,
    required this.accent,
    required this.isDark,
  });

  /// The sidebar column.
  final Color page;

  /// The strip the tabs sit on: a shade darker than [page], which is what lets the selected
  /// tab be [surface] and therefore look joined to the editor below it.
  final Color frame;

  /// The editor, and the selected tab. One colour, on purpose.
  final Color surface;

  final Color ink;
  final Color sub;
  final Color faint;
  final Color hover;
  final Color line;
  final Color code;
  final Color bar;
  final Color field;
  final Color fieldLine;
  final Color accent;
  final bool isDark;

  /// The band drawn behind selected text.
  ///
  /// Spelled out rather than left to Material. The colour a `TextField` selects with otherwise
  /// comes from the *app's* colour scheme, which is the phone's amber - the desktop's own
  /// palette never reaches it, and selecting a note's title drew a gold band under a blue
  /// caret. Measured before it was fixed: `#785C1C`, which is exactly `#FFB814` at 40% over
  /// this surface.
  Color get selection => accent.withValues(alpha: 0.35);

  static NotesDesktopPalette light(SystemAccent accent) =>
      NotesDesktopPalette(
        page: const Color(0xFFF0F0F2),
        frame: const Color(0xFFE7E7EA),
        surface: const Color(0xFFFFFFFF),
        ink: const Color(0xFF1C1C1E),
        sub: const Color(0xFF5C5C61),
        faint: const Color(0xFF9A9AA0),
        hover: const Color(0xFFE9E9EC),
        line: const Color(0xFFD6D6DA),
        code: const Color(0xFFF3F3F5),
        bar: const Color(0xFFD5D5D9),
        field: const Color(0xFFFFFFFF),
        fieldLine: const Color(0xFFE1E1E5),
        accent: accent.light,
        isDark: false,
      );

  static NotesDesktopPalette dark(SystemAccent accent) => NotesDesktopPalette(
        page: const Color(0xFF141416),
        frame: const Color(0xFF0E0E10),
        surface: const Color(0xFF1E1E21),
        ink: const Color(0xFFEDEDF0),
        sub: const Color(0xFFA3A3AA),
        faint: const Color(0xFF77777E),
        hover: const Color(0xFF212125),
        line: const Color(0xFF2A2A2F),
        code: const Color(0xFF26262A),
        bar: const Color(0xFF3C3C43),
        field: const Color(0xFF1B1B1E),
        fieldLine: const Color(0xFF2B2B30),
        accent: accent.dark,
        isDark: true,
      );

  /// The renderer's palette, built from these tokens.
  ///
  /// `buildMarkdownSpan` takes a [NotesPalette] - the phone's palette type - so that the
  /// project has exactly one Markdown renderer. Only three of its fields are ever read
  /// (`codeBackground`, `sub` and `amber`); the rest are filled in with desktop values so that
  /// nothing can quietly paint a phone colour.
  NotesPalette get rendererPalette => NotesPalette(
        page: page,
        card: surface,
        ink: ink,
        sub: sub,
        divider: line,
        amber: accent,
        accentText: accent,
        ring: faint,
        toolbar: surface,
        codeBackground: code,
        panelButton: hover,
        chipSelected: hover,
        isDark: isDark,
      );
}

/// Layout numbers, in logical pixels.
///
/// Nothing here is dp from the phone. The row is 56 rather than 74, the touch targets are
/// mouse-sized, and the strip that holds the tabs is 38 rather than a 72dp app bar.
abstract final class NotesDesktopMetrics {
  /// The tab strip, at the very top of the window. There is no title bar above it: the OS one
  /// is removed and the app's own band takes its place.
  static const double band = 38;

  /// The sidebar title, which starts the sidebar's own column rather than sitting in the band.
  ///
  /// It began life centred in the band, then lower in the band, and neither was what the user
  /// wanted: the word belongs *under* the tab strip, heading the note list, with nothing of it
  /// left up in the window's chrome. [sidebarTitleTop] is the gap between the line the band
  /// ends at and the top of the row holding it.
  ///
  /// `height: 1.0` keeps the text's line box exactly [sidebarTitleSize] tall, so the row's
  /// height and the room the title takes are worked out rather than guessed.
  static const double sidebarTitleSize = 17;
  static const double sidebarTitleTop = 6;

  /// What is left of the band's left-hand part once the note list is folded away.
  ///
  /// The buttons that live there have to stay reachable - a button that hides itself cannot be
  /// pressed again - so the band keeps a narrow rail for them and the tab strip starts after
  /// that, the same way it starts after the whole sidebar when the list is open.
  ///
  /// Wide enough for **both** of them (6 + 34 + 2 + 34 + 8): the rail was 46 when there was
  /// only the fold button, and the second button then painted underneath the tab strip, where
  /// it was invisible and a click on it started a window drag instead.
  static const double sidebarRail = 84;

  /// The window buttons at the right-hand end of that band.
  static const double windowButtonWidth = 46;

  static const double sidebarDefault = 292;
  static const double sidebarMin = 220;
  static const double sidebarMax = 420;
  static const double sidebarHandle = 5;

  /// What the note pane is never squeezed below, in logical pixels.
  ///
  /// The window can be dragged down to 480 (see `WM_GETMINMAXINFO` in the runner). At that
  /// width the sidebar cannot keep its designed 292 and still leave a pane worth reading, so it
  /// gives way first - down to [sidebarMin] and no further, because below that the note list's
  /// own two lines stop fitting.
  static const double paneMin = 260;

  /// A note in the sidebar: two lines, and the date on the right.
  static const double rowHeight = 56;
  static const double listIconLeft = 20;
  static const double listTextLeft = 36;

  static const double tabWidth = 176;

  /// The narrowest a tab is drawn before the strip scrolls instead.
  ///
  /// Wide enough for a few characters and the close button. Below this the title would be one
  /// letter and a dot, which is not something anybody can pick a note out of.
  static const double tabMinWidth = 96;

  static const double tabRadius = 9;

  /// The "+" at the end of the tab strip, and the room it takes out of the tabs' width.
  ///
  /// Measured off the mock-up rather than chosen: the last tab ends at x=830 and the glyph's ink
  /// runs 839..849, so a 28-wide box butted straight against the tab centres it where the design
  /// has it. It keeps this room even when the tabs no longer fit - it is how a note gets written
  /// in a strip that has run out of space, so it must never be what gets squeezed out.
  static const double newTabWidth = 28;

  /// The paragraph column. Wider than this and the eye loses the line it was on.
  static const double bodyMaxWidth = 700;
  static const double bodyFontSize = 16;
  static const double bodyLineHeight = 1.65;
  static const double titleFontSize = 30;
  static const double statusHeight = 32;

  static const double radiusControl = 8;
  static const double radiusRow = 10;
}

/// The families the Windows interface is drawn in.
///
/// Only the Chinese half needed naming. The Latin text was already coming out as Segoe UI -
/// measured rather than assumed: a 12px line of `2026/9/18 · 欢迎使用 Notes` is 225 physical
/// pixels wide on screen, against Segoe UI's 223 - so the user's "the Latin is fine" is what
/// the app was doing anyway.
///
/// Chinese was a different matter: nothing named a family for it. The theme sets no
/// `fontFamily`, and Flutter's Windows typography names a face for Latin (Segoe UI) but leaves
/// the one it uses for Chinese to the engine's fallback, which is whatever the system reaches
/// for rather than a decision anybody made. [fontFamilyFallback] is consulted per character,
/// so naming Segoe UI first and the Chinese faces after it keeps the Latin exactly as it was
/// and makes the Chinese deliberate.
///
/// The `UI` variant is the one Windows itself draws menus and dialogs in; plain
/// `Microsoft YaHei` is the fallback for a machine that has only that.
abstract final class NotesDesktopType {
  static const String fontFamily = 'Segoe UI';
  static const List<String> fontFamilyFallback = <String>[
    'Microsoft YaHei UI',
    'Microsoft YaHei',
  ];

  static const FontWeight body = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight emphasis = FontWeight.w600;
  static const FontWeight strong = FontWeight.w700;

  /// Inline code: Consolas, which every Windows has, rather than the generic `monospace`.
  static const String monoFamily = 'Consolas';
}
