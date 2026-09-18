/// Syncthing's conflicted copies, by name only.
///
/// When both ends of a sync have changed the same note, Syncthing keeps both versions: the
/// winner stays under its own name and the loser is written next to it as
///
///     <title>.sync-conflict-<YYYYMMDD>-<HHMMSS>-<DEVICE>.md
///
/// The app must never present one of those as an ordinary note. Its "title" is the whole
/// generated name - a long run of digits and letters that says nothing to the reader - so it
/// is easy to open or delete by accident, and it may hold the only copy of what was typed on
/// the other device. The list hides them ([NotesStore.listNotes]); this file is what lets the
/// conflict page say *which* note a copy belongs to.
///
/// This is deliberately pure string handling with no file access, so it can be tested
/// without a temporary folder - the same shape as `note_title.dart`.
library;

abstract final class SyncConflict {
  /// The infix Syncthing puts between the original name and the stamp.
  static const String marker = '.sync-conflict-';

  /// True when [fileName] is a Syncthing conflict copy.
  ///
  /// [fileName] may be given with or without its `.md`. Matching ignores case, because the
  /// marker is compared against a file name that may have been typed or renamed by hand on
  /// the other end of the sync, where the app has no say.
  static bool isConflictCopy(String fileName) =>
      _withoutExtension(fileName).toLowerCase().contains(marker);

  /// The title of the note [fileName] is a copy of.
  ///
  /// Returns `''` when [fileName] is not a conflict copy, and also when the marker sits at
  /// the very start (a file called `.sync-conflict-….md` belongs to no named note); callers
  /// fall back to the file's own name in that case. The name may be given with or without
  /// its `.md`.
  static String originalTitle(String fileName) {
    final String name = _withoutExtension(fileName);
    final int at = name.toLowerCase().indexOf(marker);
    return at <= 0 ? '' : name.substring(0, at);
  }

  /// Strips one trailing `.md`, leaving anything else - including a name that has no
  /// extension at all - untouched.
  static String _withoutExtension(String fileName) {
    const String md = '.md';
    return fileName.toLowerCase().endsWith(md)
        ? fileName.substring(0, fileName.length - md.length)
        : fileName;
  }
}
