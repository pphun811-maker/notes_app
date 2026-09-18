/// Renders the note's Markdown while it is being edited.
///
/// The hard constraint here is that the text handed to the text field must be exactly
/// as long as the note itself, character for character. Flutter positions the caret and
/// the selection by indexing into the span that is painted, so a renderer that silently
/// drops the `##` of a heading would put the caret in the wrong place on every line that
/// has one. Markers are therefore **replaced one for one**: a hidden marker becomes a
/// zero-width space, and a checkbox's dash becomes the box glyph. Nothing is added and
/// nothing is removed, so offsets keep their meaning.
///
/// The rules are the ones the user asked for by name:
///
/// * `#` .. `######` at the start of a line is a heading - hashes hidden, text larger and
///   bold;
/// * `- ` (also `* ` and `+ `) at the start of a line is a list item - the marker hidden;
/// * `- [ ]` / `- [x]` at the start of a line is a checkbox, tappable;
/// * `> ` at the start of a line is a quote - the marker becomes an amber bar;
/// * `**bold**`, `*italic*`, `***both***`, `~~struck~~` and `` `code` `` lose their markers;
/// * `1. ` numbered lists are **left exactly as typed** - the user copies lines like that
///   into other apps and wants the characters there;
/// * a bare `[ ]` is **left exactly as typed** as well, wherever it appears, so it can be
///   used to mark up things like stage directions;
/// * `[text](url)` links are not implemented at all - the user said they will never write
///   one.
library;

import 'package:flutter/material.dart';

import 'design.dart';

/// What one character of the note means.
///
/// Flags combine rather than replace each other, so a character can be, say, bold inside a
/// level-2 heading.
class MarkdownFlags {
  /// A marker that must not be seen. Painted as a zero-width space.
  bool hidden = false;

  bool bold = false;
  bool italic = false;
  bool strike = false;
  bool code = false;
  bool quote = false;

  /// The `>` of a quote, painted as a bar.
  bool bar = false;

  /// The `-` of a task item, painted as a box.
  bool checkBox = false;
  bool checked = false;

  /// 0 for body text, 1..6 for a heading.
  int heading = 0;

  bool sameAs(MarkdownFlags other) =>
      hidden == other.hidden &&
      bold == other.bold &&
      italic == other.italic &&
      strike == other.strike &&
      code == other.code &&
      quote == other.quote &&
      bar == other.bar &&
      checkBox == other.checkBox &&
      checked == other.checked &&
      heading == other.heading;

  bool get isPlain =>
      !hidden &&
      !bold &&
      !italic &&
      !strike &&
      !code &&
      !quote &&
      !bar &&
      !checkBox &&
      heading == 0;
}

/// The zero-width space a hidden marker is painted as.
const String _zeroWidth = '\u200B';

/// U+25CB / U+25C9: an empty circle and the same circle with its centre filled in.
///
/// Circles, not the ballot boxes the first version used: the user asked for the box to be
/// round, and U+2611 is one of the characters Android renders as a colour emoji, so the
/// ticked state came out as a picture rather than as text in the app's own colour. Both of
/// these are plain geometric shapes with no emoji presentation, so the accent colour and the
/// text weight apply to them like any other character.
const String _boxEmpty = '\u25CB';
const String _boxTicked = '\u25C9';

/// U+258D, the bar a `>` is painted as.
const String _bar = '\u258D';

/// How much bigger a heading is than the body text, by level.
const List<double> _headingScale = <double>[1, 1.5, 1.3, 1.15, 1.06, 1.0, 1.0];

final RegExp _headingLine = RegExp(r'^(\s*)(#{1,6})(\s+)');
final RegExp _taskLine = RegExp(r'^(\s*)([-*+])(\s+)\[([ xX])\]');
final RegExp _bulletLine = RegExp(r'^(\s*)([-*+])(\s+)');
final RegExp _quoteLine = RegExp(r'^(\s*)(>)(\s?)');

/// Inline markers, as one alternation so that the longer ones win: scanning `**bold**`
/// with a separate italic rule would find an italic `*bold*` inside it and italicise the
/// word. The capture groups are, in order, code, bold+italic, bold, italic, strikethrough.
final RegExp _inline = RegExp(
  r'`([^`\n]*?)`'
  r'|\*\*\*([^*\n]+?)\*\*\*'
  r'|\*\*([^*\n]+?)\*\*'
  r'|\*([^*\n]+?)\*'
  r'|~~([^~\n]+?)~~',
);

/// Works out what each character of [text] is.
///
/// Pure, and separate from any styling, so the rules above can be tested without a widget
/// tree - see `test/markdown_span_test.dart`.
List<MarkdownFlags> analyseMarkdown(String text) {
  final List<MarkdownFlags> flags = List<MarkdownFlags>.generate(
    text.length,
    (_) => MarkdownFlags(),
  );
  int start = 0;
  while (start <= text.length) {
    int end = text.indexOf('\n', start);
    if (end < 0) end = text.length;
    _analyseLine(text, flags, start, end);
    if (end >= text.length) break;
    start = end + 1;
  }
  return flags;
}

void _analyseLine(String text, List<MarkdownFlags> flags, int start, int end) {
  final String line = text.substring(start, end);

  final Match? task = _taskLine.firstMatch(line);
  final Match? heading = _headingLine.firstMatch(line);
  final Match? bullet = _bulletLine.firstMatch(line);
  final Match? quote = _quoteLine.firstMatch(line);

  int content = start;
  if (task != null) {
    // `-` becomes the box; the space, the brackets and the mark inside them vanish.
    final int dash = start + task.group(1)!.length;
    flags[dash].checkBox = true;
    flags[dash].checked = task.group(4)!.toLowerCase() == 'x';
    for (int i = dash + 1; i < start + task.end; i++) {
      flags[i].hidden = true;
    }
    content = start + task.end;
  } else if (heading != null) {
    for (int i = start; i < start + heading.end; i++) {
      flags[i].hidden = true;
    }
    final int level = heading.group(2)!.length;
    for (int i = start + heading.end; i < end; i++) {
      flags[i].heading = level;
    }
    content = start + heading.end;
  } else if (bullet != null) {
    for (int i = start; i < start + bullet.end; i++) {
      flags[i].hidden = true;
    }
    content = start + bullet.end;
  } else if (quote != null) {
    final int mark = start + quote.group(1)!.length;
    flags[mark].bar = true;
    for (int i = start + quote.end; i < end; i++) {
      flags[i].quote = true;
    }
    content = start + quote.end;
  }

  // Numbered lists are deliberately not recognised: `1. ` stays on screen as typed.
  _analyseInline(text.substring(content, end), content, flags);
}

/// How long each alternative's opening (and closing) marker is, indexed by capture group.
///
/// Dart's `Match` only reports the whole match's offsets, not a group's, so the content
/// bounds are worked out from the marker length instead. Every alternative above has the
/// same marker on both sides, which is what makes that safe.
const List<int> _markerLength = <int>[0, 1, 3, 2, 1, 2];

void _analyseInline(String line, int offset, List<MarkdownFlags> flags) {
  for (final RegExpMatch match in _inline.allMatches(line)) {
    int? group;
    for (int g = 1; g <= 5; g++) {
      if (match.group(g) != null) {
        group = g;
        break;
      }
    }
    if (group == null) continue;
    final int marker = _markerLength[group];
    final int contentStart = offset + match.start + marker;
    final int contentEnd = offset + match.end - marker;
    for (int i = offset + match.start; i < contentStart; i++) {
      flags[i].hidden = true;
    }
    for (int i = contentEnd; i < offset + match.end; i++) {
      flags[i].hidden = true;
    }
    for (int i = contentStart; i < contentEnd; i++) {
      switch (group) {
        case 1:
          flags[i].code = true;
        case 2:
          flags[i].bold = true;
          flags[i].italic = true;
        case 3:
          flags[i].bold = true;
        case 4:
          flags[i].italic = true;
        case 5:
          flags[i].strike = true;
      }
    }
  }
}

/// Builds the span the text field paints.
///
/// [composing] is the region the IME is still working on; it is underlined so that typing
/// Chinese shows which characters are not committed yet.
TextSpan buildMarkdownSpan({
  required String text,
  required TextStyle base,
  required NotesPalette palette,
  TextRange? composing,
}) {
  final List<MarkdownFlags> flags = analyseMarkdown(text);
  final bool hasComposing = composing != null && composing.isValid;
  final int composingStart = hasComposing ? composing.start : -1;
  final int composingEnd = hasComposing ? composing.end : -1;

  final List<InlineSpan> spans = <InlineSpan>[];
  int i = 0;
  while (i < text.length) {
    int j = i + 1;
    while (j < text.length &&
        flags[j].sameAs(flags[i]) &&
        j != composingStart &&
        j != composingEnd) {
      j++;
    }
    final bool inComposing =
        hasComposing && i >= composingStart && j <= composingEnd;
    spans.add(
      TextSpan(
        text: _paint(text, flags[i], i, j),
        style: _styleOf(flags[i], base, palette, inComposing),
      ),
    );
    i = j;
  }
  return TextSpan(style: base, children: spans);
}

String _paint(String text, MarkdownFlags flags, int start, int end) {
  if (flags.hidden) return _zeroWidth * (end - start);
  if (flags.checkBox) return flags.checked ? _boxTicked : _boxEmpty;
  if (flags.bar) return _bar;
  return text.substring(start, end);
}

TextStyle _styleOf(
  MarkdownFlags flags,
  TextStyle base,
  NotesPalette palette,
  bool inComposing,
) {
  TextStyle style = base;
  if (flags.heading > 0) {
    // No `height` here on purpose: the line height is the text field's business. Setting one
    // made no difference at all (the rendering came out byte for byte identical), because a
    // text field's default `StrutStyle` forces every line to the height of the *field's* own
    // style. See the `strutStyle` on the editor's body field.
    style = style.copyWith(
      fontSize: base.fontSize! * _headingScale[flags.heading],
      fontWeight: NotesType.emphasis,
    );
  }
  if (flags.bold) style = style.copyWith(fontWeight: NotesType.emphasis);
  if (flags.italic) style = style.copyWith(fontStyle: FontStyle.italic);
  if (flags.strike) {
    style = style.copyWith(decoration: TextDecoration.lineThrough);
  }
  if (flags.code) {
    style = style.copyWith(
      fontFamily: 'monospace',
      backgroundColor: palette.codeBackground,
    );
  }
  if (flags.quote) style = style.copyWith(color: palette.sub);
  if (flags.checkBox) {
    style = style.copyWith(color: flags.checked ? palette.amber : palette.sub);
  }
  if (flags.bar) style = style.copyWith(color: palette.amber);
  if (inComposing) {
    style = style.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: style.color,
    );
  }
  return style;
}

/// The index of the character inside the brackets of the task item containing [offset],
/// or null when that offset is not on a task item's box.
///
/// Used to make the box tappable: a tap puts the caret somewhere, and if that somewhere is
/// the box, the box is what the user meant.
int? taskBoxIndexAt(String text, int offset) {
  if (offset < 0 || offset > text.length) return null;
  final int lineStart = offset == 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;
  int lineEnd = text.indexOf('\n', lineStart);
  if (lineEnd < 0) lineEnd = text.length;
  final Match? task = _taskLine.firstMatch(text.substring(lineStart, lineEnd));
  if (task == null) return null;
  // `- [ ]`: the dash is at 0 and the mark inside the brackets at 3.
  final int dash = lineStart + task.group(1)!.length;
  if (offset < dash || offset >= dash + 5) return null;
  return dash + 3;
}

/// Flips `[ ]` to `[x]` or back, given the index of the mark inside the brackets.
String toggleTaskAt(String text, int markIndex) {
  if (markIndex < 0 || markIndex >= text.length) return text;
  final String mark = text[markIndex] == ' ' ? 'x' : ' ';
  return text.replaceRange(markIndex, markIndex + 1, mark);
}
