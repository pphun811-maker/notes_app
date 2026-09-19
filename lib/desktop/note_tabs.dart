/// Which notes are open in the Windows interface, and which one is being edited.
///
/// A plain value class rather than a widget or a notifier: the rules of the tab set - never
/// open the same note twice, a closed tab picks its neighbour, a renamed file keeps its tab -
/// are the part that can be wrong in a way nobody notices until work is lost, so they are kept
/// where a plain `test()` can reach them. `HANDOFF_PHASE6.md` section 5 asks for exactly this.
///
/// Every method returns the new state instead of mutating: the page holds one of these in its
/// own state, and comparing `old == new` is what tells it whether to rebuild.
library;

import 'dart:io';

/// Notes are identified by their path.
///
/// `File` does compare by path, but the rest of this app compares `.path` explicitly and the
/// two must agree - a note that is "already open" has to mean the same thing in the model and
/// in the interface.
String _key(File file) => file.path;

class NoteTabs {
  const NoteTabs._(this.files, this.currentIndex);

  /// Nothing open.
  const NoteTabs.empty() : this._(const <File>[], 0);

  /// The open notes, left to right.
  final List<File> files;

  /// Which of them is being edited. Always a valid index, or 0 when there is nothing open.
  final int currentIndex;

  /// True when no note is open at all.
  bool get isEmpty => files.isEmpty;

  bool get isNotEmpty => files.isNotEmpty;

  /// The note being edited, or null when nothing is open.
  File? get current => files.isEmpty ? null : files[currentIndex];

  int get length => files.length;

  /// Whether [file] is open, at any position.
  bool contains(File file) => files.any((File f) => _key(f) == _key(file));

  /// The position of [file], or -1.
  int indexOf(File file) {
    for (int i = 0; i < files.length; i++) {
      if (_key(files[i]) == _key(file)) return i;
    }
    return -1;
  }

  /// Opens [file], or selects it when it is already open.
  ///
  /// The same note twice is the thing this exists to prevent: two editors over one file would
  /// each autosave over the other, and the one that saved last would win with no warning at
  /// all.
  NoteTabs open(File file) {
    final int existing = indexOf(file);
    if (existing >= 0) return select(existing);
    final List<File> next = <File>[...files, file];
    // A new tab belongs to the right of the one it was opened from, and is looked at straight
    // away.
    return NoteTabs._(next, next.length - 1);
  }

  /// Makes the tab at [index] the current one. Ignores an index that is not there.
  NoteTabs select(int index) {
    if (index < 0 || index >= files.length) return this;
    if (index == currentIndex) return this;
    return NoteTabs._(files, index);
  }

  /// Closes the tab at [index].
  ///
  /// The next tab to the right becomes current, or the one to the left when the closed tab was
  /// the last: the selection stays where the eye already was, which is what every browser does
  /// and what the hand expects.
  NoteTabs close(int index) {
    if (index < 0 || index >= files.length) return this;
    final List<File> next = <File>[...files]..removeAt(index);
    if (next.isEmpty) return const NoteTabs.empty();
    int current = currentIndex;
    if (index < current) {
      current--;
    } else if (index == current) {
      current = index >= next.length ? next.length - 1 : index;
    }
    return NoteTabs._(next, current);
  }

  /// Closes [file] wherever it is.
  NoteTabs closeFile(File file) => close(indexOf(file));

  /// Follows a rename: whatever tab held [from] now holds [to].
  ///
  /// The tab keeps its position, and stays current if it was. A rename that left the tab
  /// pointing at the old path would make the next refresh decide the note had been deleted and
  /// close the editor the user is typing in.
  NoteTabs replace(File from, File to) {
    final int index = indexOf(from);
    if (index < 0) return this;
    // Renaming onto a note that is already open would leave two tabs over one file, which is
    // the one thing this class exists to prevent: the duplicate is dropped and the surviving
    // tab takes the new name.
    final int duplicate = indexOf(to);
    final List<File> next = <File>[...files];
    if (duplicate >= 0 && duplicate != index) {
      next.removeAt(duplicate);
      final int at = duplicate < index ? index - 1 : index;
      next[at] = to;
      final int current = currentIndex == duplicate ? at : currentIndex;
      return NoteTabs._(next, _clampCurrent(current, next.length));
    }
    next[index] = to;
    return NoteTabs._(next, currentIndex);
  }

  /// Drops the tab for a file that is no longer in the folder.
  ///
  /// Deleting a note from the sidebar, or Syncthing removing one, has to take its tab with it;
  /// an editor left open over a file that is gone is an editor that will write it back.
  NoteTabs forget(File file) => closeFile(file);

  /// Keeps only the tabs whose files are in [present], matching by path.
  ///
  /// The current tab survives if it can; otherwise the selection lands on the last one left,
  /// the same rule [close] uses.
  NoteTabs retainOnly(Iterable<File> present) {
    final Set<String> keep = present.map(_key).toSet();
    if (files.every((File f) => keep.contains(_key(f)))) return this;
    final File? wasCurrent = current;
    final List<File> next =
        files.where((File f) => keep.contains(_key(f))).toList(growable: false);
    if (next.isEmpty) return const NoteTabs.empty();
    int at = wasCurrent == null
        ? 0
        : next.indexWhere((File f) => _key(f) == _key(wasCurrent));
    // The current note is one of the ones that went: land on the last tab left, the same rule
    // [close] uses.
    if (at < 0) at = next.length - 1;
    return NoteTabs._(next, at);
  }

  static int _clampCurrent(int value, int length) {
    if (length == 0) return 0;
    if (value < 0) return 0;
    if (value >= length) return length - 1;
    return value;
  }

  @override
  bool operator ==(Object other) {
    if (other is! NoteTabs) return false;
    if (other.currentIndex != currentIndex) return false;
    if (other.files.length != files.length) return false;
    for (int i = 0; i < files.length; i++) {
      if (_key(other.files[i]) != _key(files[i])) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        currentIndex,
        Object.hashAll(files.map(_key)),
      );

  @override
  String toString() =>
      'NoteTabs(${files.map((File f) => f.path.split(Platform.pathSeparator).last).join(', ')}'
      ' @ $currentIndex)';
}
