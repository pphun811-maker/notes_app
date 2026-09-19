import 'package:flutter/material.dart';

import '../design.dart';
import '../markdown_span.dart';

/// A text controller that paints the note as formatted Markdown.
///
/// Only what is drawn changes. The note on disk keeps every marker exactly as typed, so
/// `notes_store.dart`, the file format and the Syncthing contract are all untouched - which
/// is also what lets "复制为 Markdown" hand back the original characters.
///
/// The two interfaces that use this are meant to look nothing alike, so the three things that
/// differ between them are parameters rather than constants: the palette the span is painted
/// with, the weight emphasis uses, and the family inline code is set in. The Android editor
/// passes none of them and gets exactly what it always got.
class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({
    super.text,
    this.palette,
    this.emphasis,
    this.monoFamily,
  });

  /// Overrides the palette the span is painted with.
  ///
  /// Defaults to the phone's, taken from the ambient theme, which is what the Android editor
  /// wants. The Windows interface passes its own. Mutable because the system theme can be
  /// switched while a note is open, and the body has to repaint with it.
  NotesPalette? palette;

  /// Overrides the weight headings and `**bold**` are drawn at.
  FontWeight? emphasis;

  /// Overrides the family inline `` `code` `` is drawn in.
  String? monoFamily;

  /// Draws the file's own characters instead of the rendered note.
  ///
  /// The markers (`#`, `**`, `>`) are *always* in the file - the renderer only changes what is
  /// drawn, hiding them behind zero-width characters. So showing them again is a switch over
  /// this one method rather than a second way of holding the note, and nothing about loading or
  /// saving is involved. Mutable for the same reason as [palette]: the Windows editor repaints
  /// the body by rebuilding the field, and this is read during that rebuild.
  bool sourceMode = false;

  /// Ranges to paint a background behind, as `(start, end, colour)` offsets into the note.
  ///
  /// The editor's find bar is what sets these. They are painted *over* the finished span rather
  /// than inside the renderer: the renderer's business is what Markdown means, and this is the
  /// editor's - what the user is looking for. The two can be combined at all because the
  /// renderer replaces every marker one character for one (a hidden `#` is drawn as one
  /// zero-width space), so an offset in the note is the same offset in what is drawn.
  ///
  /// Later marks win where they overlap, which is how the match being looked at is painted over
  /// the other matches rather than fighting with them.
  List<(int, int, Color)> highlights = const <(int, int, Color)>[];

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final TextStyle base = style ?? const TextStyle();
    final TextSpan span = sourceMode
        ? _plainSpan(base, withComposing)
        : buildMarkdownSpan(
            text: text,
            base: base,
            palette: palette ?? NotesPalette.of(context),
            composing: withComposing ? value.composing : null,
            emphasis: emphasis ?? NotesType.emphasis,
            monoFamily: monoFamily ?? 'monospace',
          );
    if (highlights.isEmpty) return span;
    return _paintHighlights(span, _segments(highlights), 0);
  }

  /// The marked ranges, cut into non-overlapping pieces in order, each with the colour of the
  /// last mark covering it.
  ///
  /// Splitting on the marks' own boundaries keeps this proportional to the number of matches
  /// rather than to the length of the note.
  static List<(int, int, Color)> _segments(List<(int, int, Color)> marks) {
    final Set<int> bounds = <int>{};
    for (final (int start, int end, Color _) in marks) {
      bounds.add(start);
      bounds.add(end);
    }
    final List<int> sorted = bounds.toList()..sort();
    final List<(int, int, Color)> parts = <(int, int, Color)>[];
    for (int i = 0; i + 1 < sorted.length; i++) {
      final int from = sorted[i];
      final int to = sorted[i + 1];
      Color? colour;
      for (final (int start, int end, Color candidate) in marks) {
        if (start <= from && to <= end) colour = candidate;
      }
      if (colour != null) parts.add((from, to, colour));
    }
    return parts;
  }

  /// Rebuilds [span] with [parts] given a background, walking the tree and tracking the offset
  /// each leaf sits at.
  TextSpan _paintHighlights(
    TextSpan span,
    List<(int, int, Color)> parts,
    int start,
  ) {
    final List<InlineSpan>? children = span.children;
    if (children != null && children.isNotEmpty) {
      int at = start;
      final List<InlineSpan> rebuilt = <InlineSpan>[];
      for (final InlineSpan child in children) {
        if (child is TextSpan) {
          rebuilt.add(_paintHighlights(child, parts, at));
        } else {
          rebuilt.add(child);
        }
        at += child.toPlainText().length;
      }
      return TextSpan(style: span.style, children: rebuilt);
    }

    final String text = span.text ?? '';
    if (text.isEmpty) return span;
    final int from = start;
    final int to = start + text.length;
    final List<InlineSpan> pieces = <InlineSpan>[];
    int at = from;
    for (final (int markStart, int markEnd, Color colour) in parts) {
      if (markEnd <= from || markStart >= to) continue;
      final int a = markStart < from ? from : markStart;
      final int b = markEnd > to ? to : markEnd;
      if (a > at) {
        pieces.add(TextSpan(text: text.substring(at - from, a - from), style: span.style));
      }
      pieces.add(TextSpan(
        text: text.substring(a - from, b - from),
        style: (span.style ?? const TextStyle()).copyWith(backgroundColor: colour),
      ));
      at = b;
    }
    if (pieces.isEmpty) return span;
    if (at < to) {
      pieces.add(TextSpan(text: text.substring(at - from), style: span.style));
    }
    return TextSpan(style: span.style, children: pieces);
  }

  /// The whole note, as typed, with nothing styled but the IME's uncommitted text.
  ///
  /// The underline matters here too: it is the only sign that a Chinese IME is mid-word, and
  /// losing it would make typing look broken rather than unformatted.
  TextSpan _plainSpan(TextStyle base, bool withComposing) {
    final TextRange composing = value.composing;
    if (!withComposing || !composing.isValid || composing.isCollapsed) {
      return TextSpan(text: text, style: base);
    }
    return TextSpan(
      style: base,
      children: <InlineSpan>[
        TextSpan(text: text.substring(0, composing.start)),
        TextSpan(
          text: text.substring(composing.start, composing.end),
          style: base.copyWith(decoration: TextDecoration.underline),
        ),
        TextSpan(text: text.substring(composing.end)),
      ],
    );
  }
}
