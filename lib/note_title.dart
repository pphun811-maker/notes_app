/// Turns what the user typed into a file name that is safe on both Android and Windows.
///
/// The title *is* the file name - that has been the contract since the first phase, and it
/// is what lets Syncthing treat a note as an ordinary file. So editing the title in the
/// editor renames the file, and a name only has to be impossible on one of the two systems
/// to cause trouble. Windows is the stricter of the two: it forbids `\ / : * ? " < > |`,
/// refuses names that end in a space or a dot, and reserves a handful of device names.
///
/// Returns the empty string when nothing usable is left. The caller must read that as "keep
/// the old name", never as a name - an empty file name is not a thing either system allows.
library;

import 'dart:convert';

/// How long the finished file name may be, in bytes.
///
/// Both file systems cap a single name at 255 bytes; `.md` takes three of them, and Chinese
/// characters take three bytes each, so this has to be counted in bytes rather than in
/// characters.
const int _maxNameBytes = 255;

/// Names Windows will not accept at all, whatever the extension.
const Set<String> _reservedNames = <String>{
  'CON', 'PRN', 'AUX', 'NUL',
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
};

/// Characters that cannot appear in a name on Windows, and are turned into a space.
const String _illegal = r'\/:*?"<>|';

String sanitiseNoteTitle(String title) {
  final StringBuffer out = StringBuffer();
  bool pendingSpace = false;
  for (final int rune in title.runes) {
    if (rune < 0x20 || rune == 0x7F) continue;
    final String character = String.fromCharCode(rune);
    if (character == ' ' || _illegal.contains(character)) {
      // Collapse runs of separators into one space, and never start with one.
      pendingSpace = out.isNotEmpty;
      continue;
    }
    if (pendingSpace) {
      out.write(' ');
      pendingSpace = false;
    }
    out.write(character);
  }

  String name = out.toString().trim();
  // Windows refuses a name that ends in a dot, and silently dropping it there would make
  // the two ends disagree about the name.
  while (name.endsWith('.')) {
    name = name.substring(0, name.length - 1).trimRight();
  }
  if (name.isEmpty) return '';
  if (_reservedNames.contains(name.toUpperCase())) return '_$name';

  final List<int> runes = name.runes.toList();
  while (runes.isNotEmpty && utf8.encode('${String.fromCharCodes(runes)}.md').length > _maxNameBytes) {
    runes.removeLast();
  }
  name = String.fromCharCodes(runes).trimRight();
  while (name.endsWith('.')) {
    name = name.substring(0, name.length - 1).trimRight();
  }
  return name;
}
