/// The search box's query language, and what it finds.
///
/// **Plain typing searches the whole note.** The list only ever shows a note's first line, but
/// a search that could only see that line is not a search - the word being looked for is almost
/// never in the first line. So a bare word is matched against the title *and* every line of the
/// body.
///
/// On top of that, a few things can be asked for by writing them:
///
/// | written | means |
/// |---|---|
/// | `牛奶` | the note must contain 牛奶 somewhere |
/// | `"两个 词"` | that exact run of characters, spaces and all |
/// | `-牛奶` | the note must **not** contain it |
/// | `标题:购物` / `title:购物` | only in the title (the file name) |
/// | `之后:2026/9/1` / `after:2026/9/1` | changed on or after that day |
/// | `之前:2026/9/20` / `before:2026/9/20` | changed before that day |
///
/// Several words all have to be there - this is an "and", not an "or", because narrowing is
/// what a second word is for.
///
/// Anything that looks like an operator but does not parse is searched for as ordinary text
/// rather than being dropped: a filter that silently disappeared would answer a question the
/// user did not ask, and they would have no way to tell.
///
/// Deliberately pure string handling with no file access, the same shape as `sync_conflict.dart`
/// and `note_title.dart`, so it can be tested without a temporary folder.
library;

/// One search, parsed.
class NoteQuery {
  const NoteQuery({
    this.terms = const <String>[],
    this.excluded = const <String>[],
    this.phrases = const <String>[],
    this.titleTerms = const <String>[],
    this.after,
    this.before,
  });

  /// Nothing asked for: every note matches.
  static const NoteQuery empty = NoteQuery();

  /// Words that must all appear, in the title or anywhere in the body. Already lower-cased.
  final List<String> terms;

  /// Words that must appear in the title. Already lower-cased.
  final List<String> titleTerms;

  /// Runs of characters that must appear verbatim. Already lower-cased.
  final List<String> phrases;

  /// Words that must not appear anywhere. Already lower-cased.
  final List<String> excluded;

  /// Changed on or after this moment.
  final DateTime? after;

  /// Changed strictly before this moment.
  final DateTime? before;

  /// Whether nothing at all was asked for.
  bool get isEmpty =>
      terms.isEmpty &&
      titleTerms.isEmpty &&
      phrases.isEmpty &&
      excluded.isEmpty &&
      after == null &&
      before == null;

  /// Whether the note's text is looked at, as opposed to only its date.
  bool get looksAtText =>
      terms.isNotEmpty ||
      titleTerms.isNotEmpty ||
      phrases.isNotEmpty ||
      excluded.isNotEmpty;

  /// Parses what the user typed. Never throws; never rejects a query.
  static NoteQuery parse(String raw) {
    final List<String> terms = <String>[];
    final List<String> titleTerms = <String>[];
    final List<String> phrases = <String>[];
    final List<String> excluded = <String>[];
    DateTime? after;
    DateTime? before;

    for (final String token in _tokenise(raw)) {
      bool negated = false;
      String rest = token;
      if (rest.length > 1 && rest.startsWith('-')) {
        negated = true;
        rest = rest.substring(1);
      }

      final _Operator? operator = _operatorOf(rest);
      if (operator != null && !negated) {
        final String value = rest.substring(operator.spelling.length);
        if (operator.takesDate) {
          // Mid-typing: `之后:` on its own asks for nothing yet. Falling through would search
          // for the literal characters and empty the list on the way to typing the date.
          if (value.trim().isEmpty) continue;
          final DateTime? when = parseDate(value);
          if (when != null) {
            if (operator.isLowerBound) {
              after = when;
            } else {
              before = when;
            }
            continue;
          }
          // A value that is not a date is searched for as ordinary text, so a typo narrows
          // nothing and hides nothing.
        } else {
          final String wanted = _unquote(value).toLowerCase();
          if (wanted.isEmpty) continue;
          titleTerms.add(wanted);
          continue;
        }
      }

      if (negated) {
        final String wanted = _unquote(rest).toLowerCase();
        if (wanted.isNotEmpty) excluded.add(wanted);
        continue;
      }
      if (_isPhrase(rest)) {
        final String phrase = _unquote(rest).toLowerCase();
        if (phrase.isNotEmpty) phrases.add(phrase);
        continue;
      }
      if (rest.isNotEmpty) terms.add(rest.toLowerCase());
    }

    return NoteQuery(
      terms: terms,
      titleTerms: titleTerms,
      phrases: phrases,
      excluded: excluded,
      after: after,
      before: before,
    );
  }

  /// What this query found in one note, or null when it does not match.
  NoteMatch? match({
    required String title,
    required String body,
    required DateTime modified,
  }) {
    if (after != null && modified.isBefore(after!)) return null;
    if (before != null && !modified.isBefore(before!)) return null;

    final String lowerTitle = title.toLowerCase();
    final String lowerBody = body.toLowerCase();

    for (final String term in terms) {
      if (!lowerTitle.contains(term) && !lowerBody.contains(term)) return null;
    }
    for (final String term in titleTerms) {
      if (!lowerTitle.contains(term)) return null;
    }
    for (final String phrase in phrases) {
      if (!lowerTitle.contains(phrase) && !lowerBody.contains(phrase)) return null;
    }
    for (final String term in excluded) {
      if (lowerTitle.contains(term) || lowerBody.contains(term)) return null;
    }
    return NoteMatch(snippet: _snippet(body));
  }

  /// The first line of [body] that one of the words was found on, or null when the title is
  /// what matched.
  ///
  /// When the title is what matched there is nothing better to show than the note's own first
  /// line, which is what the row shows anyway; repeating the title underneath itself would say
  /// the same thing twice.
  String? _snippet(String body) {
    final List<String> needles = <String>[...terms, ...phrases];
    if (needles.isEmpty) return null;
    for (final String line in body.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final String lower = trimmed.toLowerCase();
      for (final String needle in needles) {
        if (lower.contains(needle)) {
          return trimmed.replaceFirst(RegExp(r'^#+\s*'), '');
        }
      }
    }
    return null;
  }

  /// `2026/9/1`, `2026-09-01`, `2026/9` and `2026` all name a day; anything else is null.
  ///
  /// A year on its own starts at January 1st, a year and month at the 1st of that month - the
  /// beginning of the period, which is what "after" wants and what "before" then excludes.
  static DateTime? parseDate(String value) {
    final RegExpMatch? parts = RegExp(r'^(\d{4})(?:[/\-.](\d{1,2}))?(?:[/\-.](\d{1,2}))?$')
        .firstMatch(value.trim());
    if (parts == null) return null;
    final int year = int.parse(parts.group(1)!);
    final int month = parts.group(2) == null ? 1 : int.parse(parts.group(2)!);
    final int day = parts.group(3) == null ? 1 : int.parse(parts.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }

  @override
  String toString() => 'NoteQuery(terms=$terms, title=$titleTerms, phrases=$phrases, '
      'excluded=$excluded, after=$after, before=$before)';
}

/// What a query found in a note.
class NoteMatch {
  const NoteMatch({this.snippet});

  /// The line the words were found on, with any leading `#` taken off - it is shown in the
  /// list's one-line slot, and a run of hashes there is noise rather than information.
  ///
  /// Null when the title is what matched.
  final String? snippet;
}

/// The operator words, longest spelling first so `标题:` is not shadowed by a shorter prefix.
class _Operator {
  const _Operator(this.spelling, {this.takesDate = false, this.isLowerBound = false});

  final String spelling;
  final bool takesDate;
  final bool isLowerBound;
}

const List<_Operator> _operators = <_Operator>[
  _Operator('标题:'),
  _Operator('title:'),
  _Operator('之后:', takesDate: true, isLowerBound: true),
  _Operator('after:', takesDate: true, isLowerBound: true),
  _Operator('之前:', takesDate: true),
  _Operator('before:', takesDate: true),
];

_Operator? _operatorOf(String token) {
  final String lower = token.toLowerCase();
  for (final _Operator operator in _operators) {
    if (lower.startsWith(operator.spelling)) return operator;
  }
  return null;
}

/// Splits on whitespace, except inside `"`, which holds a run of characters together.
///
/// An unterminated quote runs to the end of what was typed rather than being thrown away: the
/// user is halfway through typing when this is called on every keystroke.
List<String> _tokenise(String raw) {
  final List<String> tokens = <String>[];
  final StringBuffer current = StringBuffer();
  bool inQuotes = false;
  for (int i = 0; i < raw.length; i++) {
    final String ch = raw[i];
    if (ch == '"') {
      inQuotes = !inQuotes;
      current.write(ch);
      continue;
    }
    if (!inQuotes && (ch == ' ' || ch == '\t' || ch == '\n')) {
      if (current.isNotEmpty) {
        tokens.add(current.toString());
        current.clear();
      }
      continue;
    }
    current.write(ch);
  }
  if (current.isNotEmpty) tokens.add(current.toString());
  return tokens;
}

/// Whether [token] is meant as a phrase.
///
/// A token that *opens* with `"` counts, closed or not: the query is parsed on every keystroke,
/// and the closing quote has not been typed yet.
bool _isPhrase(String token) => token.startsWith('"');

String _unquote(String token) {
  if (!token.startsWith('"')) return token;
  final String rest = token.substring(1);
  return rest.isNotEmpty && rest.endsWith('"')
      ? rest.substring(0, rest.length - 1)
      : rest;
}
