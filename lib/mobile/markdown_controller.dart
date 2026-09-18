import 'package:flutter/material.dart';

import '../design.dart';
import '../markdown_span.dart';

/// A text controller that paints the note as formatted Markdown.
///
/// Only what is drawn changes. The note on disk keeps every marker exactly as typed, so
/// `notes_store.dart`, the file format and the Syncthing contract are all untouched - which
/// is also what lets "复制为 Markdown" hand back the original characters.
class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return buildMarkdownSpan(
      text: text,
      base: style ?? const TextStyle(),
      palette: NotesPalette.of(context),
      composing: withComposing ? value.composing : null,
    );
  }
}
