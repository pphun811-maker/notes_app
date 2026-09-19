/// The handful of things the app remembers between visits.
///
/// The editor's text settings (font size, line height, and whether the body is drawn in the
/// monospace face), which conflict-copy notices the user has swiped away, and whether the
/// desktop's note list is folded away.
///
/// They are stored in a directory belonging to the app, not in the notes folder - the notes
/// folder is shared with the PC through Syncthing, and a settings file appearing there would
/// sync to the other machine and show up as a stray file in the folder the user browses.
///
/// Nothing here touches `notes_store.dart`: a note is still just a `.md` file, and the two
/// have nothing to say to each other.
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'design.dart';

/// The editor's remembered text settings, plus the two bits of desktop state.
class NotesSettings {
  const NotesSettings({
    required this.fontSize,
    required this.lineHeight,
    required this.monoFont,
    this.sidebarCollapsed = false,
    this.themeMode = 'system',
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

  /// Whether the Windows interface's note list is folded away.
  ///
  /// Desktop-only, and given a default rather than being `required`: the phone has no sidebar,
  /// and every existing `NotesSettings(...)` call site is about the editor.
  final bool sidebarCollapsed;

  /// `'system'`, `'light'` or `'dark'` - see `themeModeName` in `design.dart`.
  ///
  /// A string rather than a `ThemeMode` so that this file stays out of the widgets layer; the
  /// mapping lives next to the notifier it feeds.
  final String themeMode;

  NotesSettings copyWith({
    double? fontSize,
    double? lineHeight,
    bool? monoFont,
    bool? sidebarCollapsed,
    String? themeMode,
  }) {
    return NotesSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      monoFont: monoFont ?? this.monoFont,
      sidebarCollapsed: sidebarCollapsed ?? this.sidebarCollapsed,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  /// One line per value, `key=value`. A file small enough that a format with any more
  /// machinery in it would be the wrong answer.
  String encode() => 'fontSize=$fontSize\n'
      'lineHeight=$lineHeight\n'
      'monoFont=$monoFont\n'
      'sidebarCollapsed=$sidebarCollapsed\n'
      'themeMode=$themeMode\n';

  /// Reads back [encode], falling back to the defaults for anything missing or unreadable.
  ///
  /// Never throws: a settings file that has been damaged must not stop a note from opening.
  static NotesSettings decode(String text) {
    double fontSize = defaults.fontSize;
    double lineHeight = defaults.lineHeight;
    bool monoFont = defaults.monoFont;
    bool sidebarCollapsed = defaults.sidebarCollapsed;
    String themeMode = defaults.themeMode;
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
        case 'sidebarCollapsed':
          sidebarCollapsed = value == 'true';
        case 'themeMode':
          if (value.isNotEmpty) themeMode = value;
      }
    }
    return NotesSettings(
      fontSize: fontSize,
      lineHeight: lineHeight,
      monoFont: monoFont,
      sidebarCollapsed: sidebarCollapsed,
      themeMode: themeMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NotesSettings &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.monoFont == monoFont &&
      other.sidebarCollapsed == sidebarCollapsed &&
      other.themeMode == themeMode;

  @override
  int get hashCode => Object.hash(
        fontSize,
        lineHeight,
        monoFont,
        sidebarCollapsed,
        themeMode,
      );

  @override
  String toString() => 'NotesSettings($fontSize, $lineHeight, mono=$monoFont, '
      'sidebarCollapsed=$sidebarCollapsed, themeMode=$themeMode)';
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
      : _configDirectory = configDirectory ?? _platformConfigDirectory;

  static const MethodChannel _channel = MethodChannel('notes_app/storage');
  static const String _fileName = 'settings.txt';

  /// The key the conflict-copy dismissals are written under, one line per name.
  ///
  /// A repeated key rather than one line holding a joined list: a file name can contain
  /// almost anything, and this way no separator has to be chosen that a name could contain.
  static const String _dismissedKey = 'dismissedConflicts';

  /// The key the pinned notes are written under, one line per title - same reasoning as
  /// [_dismissedKey], and a title is a file name.
  ///
  /// Kept in this machine's own settings rather than in the notes themselves: a note is a plain
  /// `.md` file that Syncthing carries to the phone, and "this one is at the top of the list"
  /// is a fact about *this* list, not about the note. Writing it into the file would change the
  /// user's text and sync that change to the phone, where nothing would read it.
  static const String _pinnedKey = 'pinnedNote';

  final Future<String?> Function() _configDirectory;

  NotesSettings _value = NotesSettings.defaults;

  /// The conflict copies whose notice the user has swiped away, oldest first.
  ///
  /// Kept by file name. A conflict copy always gets a fresh name from Syncthing - it carries
  /// the moment it was made - so a *new* conflict is never in this list, and its notice is
  /// shown even though an earlier one was dismissed.
  List<String> _dismissedConflicts = <String>[];

  /// The titles the user has pinned, in the order they were pinned.
  ///
  /// By title, which is the file name without its extension. A rename therefore moves the pin
  /// with it only because the page says so (see `_afterRename` in `home_page.dart`); nothing
  /// here can notice a file moving on its own.
  List<String> _pinnedNotes = <String>[];

  bool _loaded = false;

  /// The current settings, whether or not they have been read from disk yet.
  NotesSettings get value => _value;

  /// The names the user has dismissed, oldest first.
  List<String> get dismissedConflicts =>
      List<String>.unmodifiable(_dismissedConflicts);

  /// The titles the user has pinned, in the order they were pinned.
  List<String> get pinnedNotes => List<String>.unmodifiable(_pinnedNotes);

  /// Whether the note called [title] is pinned.
  bool isPinned(String title) => _pinnedNotes.contains(title);

  /// Whether the user has already swiped away the notice for [fileName].
  bool isConflictDismissed(String fileName) =>
      _dismissedConflicts.contains(fileName);

  NotesSettingsStore.forTesting(this._value)
      : _loaded = true,
        _configDirectory = _platformConfigDirectory;

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
        _pinnedNotes = _decodeList(text, _pinnedKey);
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

  /// Pins [title], or unpins it when it is already pinned.
  ///
  /// The in-memory list changes before the first `await` so the list is already in its new order
  /// by the time the caller rebuilds; the write itself is best-effort, like every other setting.
  Future<void> togglePinned(String title) async {
    final List<String> next = <String>[..._pinnedNotes];
    if (!next.remove(title)) next.add(title);
    _pinnedNotes = next;
    _loaded = true;
    await _write();
  }

  /// Follows a rename, so a pinned note stays pinned under its new title.
  ///
  /// A no-op when [from] was not pinned, which is what keeps this safe to call on every rename.
  Future<void> renamePinned(String from, String to) async {
    if (from == to) return;
    final int at = _pinnedNotes.indexOf(from);
    if (at < 0) return;
    final List<String> next = <String>[..._pinnedNotes];
    next[at] = to;
    _pinnedNotes = next;
    await _write();
  }

  /// Never throws - failing to remember a font size must not interrupt writing a note.
  ///
  /// Written beside the real file and then moved into place, because a write in place can be
  /// interrupted between the truncate and the write. The result of that is not a damaged file
  /// anybody notices: it is an **empty** one, which reads back as the defaults - silently
  /// resetting the font size, the line height, the theme, the folded sidebar and every pin.
  /// A rename is atomic, so the file is either what it was or what it now should be.
  Future<void> _write() async {
    final File? file = await _file();
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      final File pending = File('${file.path}$_pendingSuffix');
      await pending.writeAsString(_encode(), flush: true);
      await pending.rename(file.path);
    } on FileSystemException {
      // Nothing to be done about it here, and nothing worth interrupting the user for.
    }
  }

  /// What the half-written file is called while it is being written.
  static const String _pendingSuffix = '.writing';

  String _encode() {
    final StringBuffer buffer = StringBuffer(_value.encode());
    for (final String name in _dismissedConflicts) {
      buffer.writeln('$_dismissedKey=$name');
    }
    for (final String title in _pinnedNotes) {
      buffer.writeln('$_pinnedKey=$title');
    }
    return buffer.toString();
  }

  /// The values written under [key] in [text], in the order they appear, without duplicates.
  ///
  /// `NotesSettings.decode` ignores keys it does not know, so the three readers can share one
  /// file without any of them having to know the others' keys.
  static List<String> _decodeList(String text, String key) {
    final List<String> values = <String>[];
    for (final String line in text.split('\n')) {
      final int split = line.indexOf('=');
      if (split <= 0) continue;
      if (line.substring(0, split).trim() != key) continue;
      final String value = line.substring(split + 1).trim();
      if (value.isNotEmpty && !values.contains(value)) values.add(value);
    }
    return values;
  }

  static List<String> _decodeDismissed(String text) =>
      _decodeList(text, _dismissedKey);

  File? _cached;

  Future<File?> _file() async {
    if (_cached != null) return _cached;
    final String? directory = await _configDirectory();
    if (directory == null) return null;
    return _cached = File('$directory${Platform.pathSeparator}$_fileName');
  }

  /// Where the settings file lives, per platform.
  ///
  /// Android hands over its private files directory through the channel that already exists for
  /// storage permissions. Windows has `%LOCALAPPDATA%`, which `dart:io` can read with no plugin
  /// at all - the same directory every other Windows app keeps its own state in. Local rather
  /// than roaming: this is one machine's window layout, not something to carry to another.
  static Future<String?> _platformConfigDirectory() async {
    if (Platform.isAndroid) {
      try {
        return await _channel.invokeMethod<String>('getConfigDirectory');
      } on PlatformException {
        return null;
      } on MissingPluginException {
        return null;
      }
    }
    if (Platform.isWindows) {
      final String? base = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'];
      if (base == null || base.isEmpty) return null;
      return '$base${Platform.pathSeparator}Notes';
    }
    return null;
  }
}
