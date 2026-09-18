/// Turns the Markdown the user typed into the text they see on screen.
///
/// This backs "复制为纯文本", whose whole promise is *copy what you are looking at*:
/// the same rules the editor renders with, applied to a string instead of to a span.
/// Keeping it a pure function is what makes that promise testable - see
/// `test/markdown_text_test.dart`.
///
/// The rules come from what the user asked for by name:
///
/// * `#`, `##`, ... at the start of a line mark a heading; the hashes are not part of
///   what is displayed;
/// * `- ` at the start of a line marks a list item, and its dash is dropped too;
/// * `> ` marks a quote, and the marker is dropped;
/// * `**bold**`, `*italic*`, `~~struck~~` and `` `code` `` lose their markers;
/// * `1. ` numbered lists are **not** rendered - the user wants those characters kept
///   literally, because they copy lines like that into other apps;
/// * `[ ]` on its own is **not** a checkbox either. Only `- [ ]` at the start of a line
///   is, so the user can keep using a bare `[ ]` to mark up things like stage
///   directions (HANDOFF_PHASE4 section 12, "checkbox rule");
/// * `[text](url)` links are **not implemented at all** - the user said they will never
///   write one, so the characters are left exactly as typed.
library;

/// The result of stripping Markdown markers from [source].
String markdownToPlainText(String source) {
  final StringBuffer out = StringBuffer();
  final List<String> lines = source.split('\n');
  for (int i = 0; i < lines.length; i++) {
    if (i > 0) out.write('\n');
    out.write(_plainLine(lines[i]));
  }
  return out.toString();
}

/// One line: drop the block marker it starts with, then the inline markers.
String _plainLine(String line) {
  String stripped = line;

  // A task item first, because `- [ ]` also starts with a bullet.
  final RegExp task = RegExp(r'^\s*[-*+]\s+\[[ xX]\]\s?');
  final RegExp bullet = RegExp(r'^\s*[-*+]\s+');
  final RegExp heading = RegExp(r'^\s*#{1,6}\s+');
  final RegExp quote = RegExp(r'^\s*>\s?');

  if (task.hasMatch(stripped)) {
    // The checkbox itself is content, not punctuation: only the bullet goes.
    stripped = stripped.replaceFirst(RegExp(r'^\s*[-*+]\s+'), '');
  } else if (bullet.hasMatch(stripped)) {
    stripped = stripped.replaceFirst(bullet, '');
  } else if (heading.hasMatch(stripped)) {
    stripped = stripped.replaceFirst(heading, '');
  } else if (quote.hasMatch(stripped)) {
    stripped = stripped.replaceFirst(quote, '');
  }

  return _plainInline(stripped);
}

/// Inline markers: emphasis, strikethrough and inline code.
///
/// The order matters. Code goes first so that a `*` inside backticks is not read as
/// emphasis, then three-, two- and one-star emphasis, each removing the pairs that
/// are left. No lookbehind is used: it is not worth depending on for a rule this
/// small, and the tests in `test/markdown_text_test.dart` pin the result down.
String _plainInline(String line) {
  String out = line;
  out = out.replaceAllMapped(
    RegExp(r'`([^`]*)`'),
    (Match m) => m.group(1) ?? '',
  );
  out = out.replaceAllMapped(
    RegExp(r'\*\*\*([^*]+)\*\*\*'),
    (Match m) => m.group(1) ?? '',
  );
  out = out.replaceAllMapped(
    RegExp(r'\*\*([^*]+)\*\*'),
    (Match m) => m.group(1) ?? '',
  );
  out = out.replaceAllMapped(
    RegExp(r'\*([^*\n]+)\*'),
    (Match m) => m.group(1) ?? '',
  );
  out = out.replaceAllMapped(
    RegExp(r'~~([^~]+)~~'),
    (Match m) => m.group(1) ?? '',
  );
  return out;
}
