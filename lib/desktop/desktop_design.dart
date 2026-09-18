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

  /// The window buttons at the right-hand end of that band.
  static const double windowButtonWidth = 46;

  static const double sidebarDefault = 292;
  static const double sidebarMin = 220;
  static const double sidebarMax = 420;
  static const double sidebarHandle = 5;

  /// A note in the sidebar: two lines, and the date on the right.
  static const double rowHeight = 56;
  static const double listIconLeft = 20;
  static const double listTextLeft = 36;

  static const double tabWidth = 176;
  static const double tabRadius = 9;

  /// The paragraph column. Wider than this and the eye loses the line it was on.
  static const double bodyMaxWidth = 700;
  static const double bodyFontSize = 16;
  static const double bodyLineHeight = 1.65;
  static const double titleFontSize = 30;
  static const double statusHeight = 32;

  static const double radiusControl = 8;
  static const double radiusRow = 10;
}

/// Weights for the Windows interface.
///
/// The phone's [NotesType.emphasis] is w800 because ColorOS Notes measures that way on a font
/// with a single Regular face. Segoe UI and Microsoft YaHei ship real weights, and w800 there
/// reads as shouting, so the desktop asks for one step and nothing more.
abstract final class NotesDesktopType {
  static const FontWeight body = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight emphasis = FontWeight.w600;
  static const FontWeight strong = FontWeight.w700;

  /// Inline code: Consolas, which every Windows has, rather than the generic `monospace`.
  static const String monoFamily = 'Consolas';
}
