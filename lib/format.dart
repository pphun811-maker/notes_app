/// Formats a note's modified time the way the list page shows it.
///
/// **The date is deliberately not zero-padded.** `v5_light.png` shows
/// `2026/09/18`, but the user asked for `2026/9/18` and the mock-up was never
/// redrawn. See `design/README.md` ("known inconsistencies", item 1) and
/// `HANDOFF_PHASE3.md` section 6.3. Do not "fix" this back to the padded form.
String formatNoteDate(DateTime time) {
  final DateTime local = time.toLocal();
  return '${local.year}/${local.month}/${local.day}';
}

/// The line under the title in the *desktop* editor: when it was last written, then where the
/// file actually is.
///
/// The path is here because a note is an ordinary `.md` file in a folder the user owns, and the
/// desktop is where they can go and open it with something else. The phone has no such place to
/// send them, which is why this is not [formatNoteSubtitle].
String formatNoteHeading(DateTime time, String path) =>
    '${formatNoteDate(time)} · $path';

/// The one-line subtitle of a note row: the date, then the note's first line.
///
/// The date-only form is used when the note has no body yet, so a freshly created
/// note does not show a dangling separator.
String formatNoteSubtitle(DateTime modified, String preview) {
  final String date = formatNoteDate(modified);
  return preview.isEmpty ? date : '$date · $preview';
}
