/// Finding text inside the note that is open.
///
/// Separate from `note_search.dart`, which answers "which notes match": this one answers "where
/// in this note", and the two want different things. That one is a query language over a whole
/// folder; this one is a literal string the user is stepping through, and it has to be able to
/// say *where* each hit is so the editor can put the caret on it.
///
/// Pure string handling, no file access, so it can be tested on its own.
library;

/// Every place [term] appears in [text], left to right, ignoring case.
///
/// A regular expression rather than `toLowerCase().indexOf`, because lower-casing can change a
/// string's length - `'İ'.toLowerCase()` is two code units - and every offset after such a
/// character would then point one place off. `caseSensitive: false` matches against the original
/// string, so the offsets are positions in [text] itself.
///
/// Matches do not overlap: `aa` in `aaaa` gives 0 and 2, not 0, 1 and 2. Stepping through
/// overlapping hits looks like the search has got stuck.
List<int> findMatchOffsets(String text, String term) {
  if (term.isEmpty || text.isEmpty) return const <int>[];
  final RegExp pattern = RegExp(RegExp.escape(term), caseSensitive: false);
  return pattern
      .allMatches(text)
      .map((RegExpMatch match) => match.start)
      .toList(growable: false);
}

/// Which match "next" lands on, wrapping round at the end.
///
/// Wrapping rather than stopping: a find box that goes dead at the last hit makes the user
/// wonder whether it is broken, and there is nowhere for it to say so.
int nextMatch(int current, int count) {
  if (count <= 0) return -1;
  return (current + 1) % count;
}

/// Which match "previous" lands on, wrapping round at the start.
int previousMatch(int current, int count) {
  if (count <= 0) return -1;
  return (current - 1 + count) % count;
}

/// The match to start from when a search has just been typed.
///
/// The first hit at or after [from] - the caret - so that pressing Ctrl+F in the middle of a
/// note finds the next one down rather than jumping back to the top of the file. Falls back to
/// the first hit when there is nothing below the caret.
int firstMatchFrom(List<int> offsets, int from) {
  if (offsets.isEmpty) return -1;
  for (int i = 0; i < offsets.length; i++) {
    if (offsets[i] >= from) return i;
  }
  return 0;
}
