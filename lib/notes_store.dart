import 'dart:io';

import 'package:flutter/services.dart';

/// One note is one `.md` file on disk.
///
/// The file name (without the `.md` extension) is the note's title. Keeping the title in the
/// file name means the app never has to rename files behind the user's back, and the note stays
/// a perfectly ordinary text file that any editor - or Syncthing - can handle.
class Note {
  Note({required this.file, required this.modified, required this.preview});

  final File file;
  final DateTime modified;

  /// First non-empty line of the note, used as a one-line preview in the list.
  final String preview;

  String get title => fileNameWithoutExtension(file);

  static String fileNameWithoutExtension(File file) {
    final name = file.uri.pathSegments.last;
    return name.toLowerCase().endsWith('.md')
        ? name.substring(0, name.length - '.md'.length)
        : name;
  }
}

/// Reads and writes notes in a plain folder.
///
/// The app deliberately knows nothing about synchronisation: it just reads and writes files in
/// [directory]. Syncthing syncs that same folder between the PC and the phone, outside the app.
class NotesStore {
  NotesStore(this.directory);

  final Directory directory;

  static const MethodChannel _channel = MethodChannel('notes_app/storage');

  /// The folder the notes live in.
  ///
  /// This must be a real, visible folder (not an app-private one) so that Syncthing can sync it.
  static String get defaultDirectoryPath {
    if (Platform.isAndroid) return '/storage/emulated/0/Notes';
    if (Platform.isWindows) return r'D:\Notes';
    final String? home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    return home == null ? 'Notes' : '$home/Notes';
  }

  /// Android 11+ requires the "All files access" permission to read a shared folder.
  /// Every other platform returns `true` unconditionally.
  static Future<bool> hasStorageAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('hasStorageAccess') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Sends the user to the system screen where "All files access" can be granted.
  static Future<void> requestStorageAccess() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('requestStorageAccess');
    } on PlatformException {
      // The user simply stays on the permission screen; nothing to recover from here.
    } on MissingPluginException {
      // Nothing to do.
    }
  }

  Future<void> ensureDirectoryExists() async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  /// All notes in the folder, most recently modified first.
  ///
  /// Unreadable or disappearing files are skipped rather than failing the whole listing, because
  /// Syncthing may be replacing files while the list is being built.
  Future<List<Note>> listNotes() async {
    if (!await directory.exists()) return <Note>[];
    final List<Note> notes = <Note>[];
    await for (final FileSystemEntity entity in directory.list()) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.md')) continue;
      try {
        final FileStat stat = await entity.stat();
        notes.add(
          Note(
            file: entity,
            modified: stat.modified,
            preview: await _previewOf(entity),
          ),
        );
      } on FileSystemException {
        continue;
      }
    }
    notes.sort((Note a, Note b) => b.modified.compareTo(a.modified));
    return notes;
  }

  Future<String> read(File file) => file.readAsString();

  Future<void> write(File file, String contents) async {
    await ensureDirectoryExists();
    await file.writeAsString(contents, flush: true);
  }

  Future<void> delete(Note note) async {
    if (await note.file.exists()) {
      await note.file.delete();
    }
  }

  /// Creates a new, empty note whose name does not collide with an existing file.
  Future<File> createNote() async {
    await ensureDirectoryExists();
    const String base = '新建笔记';
    File candidate = _fileInDirectory('$base.md');
    int index = 2;
    while (await candidate.exists()) {
      candidate = _fileInDirectory('$base $index.md');
      index++;
    }
    await candidate.writeAsString('', flush: true);
    return candidate;
  }

  File _fileInDirectory(String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  Future<String> _previewOf(File file) async {
    try {
      final String contents = await file.readAsString();
      for (final String line in contents.split('\n')) {
        final String trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          return trimmed.replaceFirst(RegExp(r'^#+\s*'), '');
        }
      }
    } on FileSystemException {
      // Fall through to the empty preview below.
    }
    return '';
  }
}
