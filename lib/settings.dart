/// The handful of settings the app remembers between visits.
///
/// Only the editor's text settings so far: the font size, the line height, and whether the
/// body is drawn in the monospace face. They are stored in the app's **private** directory,
/// not in the notes folder - the notes folder is shared with the PC through Syncthing, and
/// a settings file appearing there would sync to the other machine and show up as a stray
/// file in the folder the user browses.
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

  final Future<String?> Function() _configDirectory;

  NotesSettings _value = NotesSettings.defaults;
  bool _loaded = false;

  /// The current settings, whether or not they have been read from disk yet.
  NotesSettings get value => _value;

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
        _value = NotesSettings.decode(await file.readAsString());
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
    final File? file = await _file();
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(settings.encode(), flush: true);
    } on FileSystemException {
      // Nothing to be done about it here, and nothing worth interrupting the user for.
    }
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
