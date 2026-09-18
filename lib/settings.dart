/// The handful of things the app remembers between visits.
///
/// Two so far: the editor's text settings (font size, line height, and whether the body is
/// drawn in the monospace face), and which conflict-copy notices the user has swiped away.
/// They are stored in the app's **private** directory, not in the notes folder - the notes
/// folder is shared with the PC through Syncthing, and a settings file appearing there would
/// sync to the other machine and show up as a stray file in the folder the user browses.
///
/// Nothing here touches `notes_store.dart`: a note is still just a `.md` file, and the two
/// have nothing to say to each other.
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'design.dart';

/// The editor's remembered text settings.
class NotesSettings {
  const NotesSettings({
    required this.fontSize,
    required this.lineHeight,
    required this.monoFont,
  });

  /// What a fresh install uses: the design's size and the line height the user settled on.
  static const NotesSettings defaults = NotesSettings(
    fontSize: NotesEditorMetrics.bodyFontSize,
    lineHeight: NotesEditorMetrics.bodyLineHeight,
    monoFont: false,
  );

  final double fontSize;
  final double lineHeight;
  final bool monoFont;

  NotesSettings copyWith({
    double? fontSize,
    double? lineHeight,
    bool? monoFont,
  }) {
    return NotesSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      monoFont: monoFont ?? this.monoFont,
    );
  }

  /// One line per value, `key=value`. A file small enough that a format with any more
  /// machinery in it would be the wrong answer.
  String encode() =>
      'fontSize=$fontSize\nlineHeight=$lineHeight\nmonoFont=$monoFont\n';

  /// Reads back [encode], falling back to the defaults for anything missing or unreadable.
  ///
  /// Never throws: a settings file that has been damaged must not stop a note from opening.
  static NotesSettings decode(String text) {
    double fontSize = defaults.fontSize;
    double lineHeight = defaults.lineHeight;
    bool monoFont = defaults.monoFont;
    for (final String line in text.split('\n')) {
      final int split = line.indexOf('=');
      if (split <= 0) continue;
      final String key = line.substring(0, split).trim();
      final String value = line.substring(split + 1).trim();
      switch (key) {
        case 'fontSize':
          fontSize = double.tryParse(value) ?? fontSize;
        case 'lineHeight':
          lineHeight = double.tryParse(value) ?? lineHeight;
        case 'monoFont':
          monoFont = value == 'true';
      }
    }
    return NotesSettings(
      fontSize: fontSize,
      lineHeight: lineHeight,
      monoFont: monoFont,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NotesSettings &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.monoFont == monoFont;

  @override
  int get hashCode => Object.hash(fontSize, lineHeight, monoFont);

  @override
  String toString() =>
      'NotesSettings($fontSize, $lineHeight, mono=$monoFont)';
}

/// The one settings store for the app.
///
/// A single instance rather than one threaded down through every widget: there is exactly
/// one settings file, and the pages that care about it are far apart in the tree.
final NotesSettingsStore appSettings = NotesSettingsStore();

/// Reads and writes [NotesSettings], and keeps the last value to hand.
///
/// The in-memory copy matters: without it every note would open at the default size and
/// jump to the remembered one a moment later, which is a visible flicker on every tap.
class NotesSettingsStore {
  NotesSettingsStore({Future<String?> Function()? configDirectory})
      : _configDirectory = configDirectory ?? _androidConfigDirectory;

  static const MethodChannel _channel = MethodChannel('notes_app/storage');
  static const String _fileName = 'settings.txt';

  /// The key the conflict-copy dismissals are written under, one line per name.
  ///
  /// A repeated key rather than one line holding a joined list: a file name can contain
  /// almost anything, and this way no separator has to be chosen that a name could contain.
  static const String _dismissedKey = 'dismissedConflicts';

  final Future<String?> Function() _configDirectory;

  NotesSettings _value = NotesSettings.defaults;

  /// The conflict copies whose notice the user has swiped away, oldest first.
  ///
  /// Kept by file name. A conflict copy always gets a fresh name from Syncthing - it carries
  /// the moment it was made - so a *new* conflict is never in this list, and its notice is
  /// shown even though an earlier one was dismissed.
  List<String> _dismissedConflicts = <String>[];

  bool _loaded = false;

  /// The current settings, whether or not they have been read from disk yet.
  NotesSettings get value => _value;

  /// The names the user has dismissed, oldest first.
  List<String> get dismissedConflicts =>
      List<String>.unmodifiable(_dismissedConflicts);

  /// Whether the user has already swiped away the notice for [fileName].
  bool isConflictDismissed(String fileName) =>
      _dismissedConflicts.contains(fileName);

  NotesSettingsStore.forTesting(this._value)
      : _loaded = true,
        _configDirectory = _androidConfigDirectory;

  /// Reads the settings file once. Later calls do nothing.
  Future<NotesSettings> load() async {
    if (_loaded) return _value;
    _loaded = true;
    final File? file = await _file();
    if (file == null) return _value;
    try {
      if (await file.exists()) {
        final String text = await file.readAsString();
        _value = NotesSettings.decode(text);
        _dismissedConflicts = _decodeDismissed(text);
      }
    } on FileSystemException {
      // Keep the defaults; a note must still open.
    }
    return _value;
  }

  /// Remembers [settings]. Never throws - failing to remember a font size must not
  /// interrupt writing a note.
  Future<void> save(NotesSettings settings) async {
    _value = settings;
    _loaded = true;
    await _write();
  }

  /// Remembers that the user swiped [fileName]'s notice away.
  ///
  /// The in-memory list is updated before the first `await`, so the banner is gone by the
  /// time the caller rebuilds - a `Dismissible` throws if the widget it dismissed is still in
  /// the tree on the next frame. The write itself is best-effort, like every other setting.
  Future<void> dismissConflict(String fileName) async {
    if (_dismissedConflicts.contains(fileName)) return;
    _dismissedConflicts = <String>[..._dismissedConflicts, fileName];
    _loaded = true;
    await _write();
  }

  /// Never throws - failing to remember a font size must not interrupt writing a note.
  Future<void> _write() async {
    final File? file = await _file();
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(_encode(), flush: true);
    } on FileSystemException {
      // Nothing to be done about it here, and nothing worth interrupting the user for.
    }
  }

  String _encode() {
    final StringBuffer buffer = StringBuffer(_value.encode());
    for (final String name in _dismissedConflicts) {
      buffer.writeln('$_dismissedKey=$name');
    }
    return buffer.toString();
  }

  /// The dismissed names in [text], in the order they were written.
  ///
  /// `NotesSettings.decode` ignores keys it does not know, so the two readers can share one
  /// file without either having to know the other's keys.
  static List<String> _decodeDismissed(String text) {
    final List<String> names = <String>[];
    for (final String line in text.split('\n')) {
      final int split = line.indexOf('=');
      if (split <= 0) continue;
      if (line.substring(0, split).trim() != _dismissedKey) continue;
      final String name = line.substring(split + 1).trim();
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
    }
    return names;
  }

  File? _cached;

  Future<File?> _file() async {
    if (_cached != null) return _cached;
    final String? directory = await _configDirectory();
    if (directory == null) return null;
    return _cached = File('$directory${Platform.pathSeparator}$_fileName');
  }

  /// Android hands over its private files directory through the channel that already exists
  /// for storage permissions. Anywhere else there is nothing to remember yet: the desktop
  /// UI is frozen, so there is no setting on it to keep.
  static Future<String?> _androidConfigDirectory() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('getConfigDirectory');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
