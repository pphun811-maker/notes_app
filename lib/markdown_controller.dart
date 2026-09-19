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

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final TextStyle base = style ?? const TextStyle();
    if (sourceMode) return _plainSpan(base, withComposing);
    return buildMarkdownSpan(
      text: text,
      base: base,
      palette: palette ?? NotesPalette.of(context),
      composing: withComposing ? value.composing : null,
      emphasis: emphasis ?? NotesType.emphasis,
      monoFamily: monoFamily ?? 'monospace',
    );
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
