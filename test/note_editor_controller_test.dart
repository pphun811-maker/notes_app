import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/note_editor_controller.dart';
import 'package:notes_app/notes_store.dart';

/// A store whose reads and writes can be made to fail on demand.
///
/// Every test here is about what happens when the disk says no, so being able to
/// say no on purpose is the whole point.
class _FaultyStore extends NotesStore {
  _FaultyStore(super.directory);

  int readsToFail = 0;
  int writesToFail = 0;
  Object writeError = const FileSystemException('磁盘写入失败');
  Duration writeDelay = Duration.zero;

  @override
  Future<String> read(File file) async {
    if (readsToFail > 0) {
      readsToFail--;
      throw const FileSystemException('磁盘读取失败');
    }
    return super.read(file);
  }

  @override
  Future<void> write(File file, String contents) async {
    if (writeDelay > Duration.zero) {
      await Future<void>.delayed(writeDelay);
    }
    if (writesToFail > 0) {
      writesToFail--;
      throw writeError;
    }
    await super.write(file, contents);
  }
}

/// Waits for [condition] to come true.
///
/// The tests never assume how long the debounce or the retry takes: they wait for
/// the state they care about and fail with a readable message if it never comes.
Future<void> _waitFor(bool Function() condition) async {
  for (int i = 0; i < 400; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('等待的条件在 2 秒内没有成立');
}

void main() {
  late Directory tempDir;
  late _FaultyStore store;
  late File note;
  late NoteEditorController editor;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('notes_editor_test');
    store = _FaultyStore(tempDir);
    note = File('${tempDir.path}${Platform.pathSeparator}笔记.md');
    await note.writeAsString('原始内容');
    editor = NoteEditorController(
      store: store,
      file: note,
      debounce: const Duration(milliseconds: 20),
      retryDelay: const Duration(milliseconds: 20),
    );
  });

  tearDown(() async {
    await editor.close();
    editor.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('load puts the file contents into the editor', () async {
    await editor.load();

    expect(editor.text, '原始内容');
    expect(editor.loading, isFalse);
    expect(editor.loadFailed, isFalse);
    expect(editor.canEdit, isTrue);
    expect(editor.error, isNull);
  });

  test('typing is written to the file once typing stops', () async {
    await editor.load();

    editor.onChanged('新的内容');
    expect(editor.hasUnsavedChanges, isTrue);

    await _waitFor(() => !editor.hasUnsavedChanges);

    expect(await note.readAsString(), '新的内容');
    expect(editor.error, isNull);
  });

  test('text typed while a write is running is not lost', () async {
    await editor.load();
    store.writeDelay = const Duration(milliseconds: 50);

    editor.onChanged('第一版');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    editor.onChanged('第二版');

    await _waitFor(() => !editor.hasUnsavedChanges);

    expect(await note.readAsString(), '第二版');
  });

  // Regression: the phase-2 editor cleared its dirty flag before awaiting the
  // write, so one failure meant the edit was never written at all.
  test('a failed write stays pending and is retried', () async {
    await editor.load();
    store.writesToFail = 1;

    editor.onChanged('第一次写入会失败');
    await _waitFor(() => editor.error != null);

    // Still only in memory, and still known to be unsaved.
    expect(editor.hasUnsavedChanges, isTrue);
    expect(await note.readAsString(), '原始内容');

    // The retry timer puts it on disk on its own.
    await _waitFor(() => !editor.hasUnsavedChanges);
    expect(await note.readAsString(), '第一次写入会失败');
  });

  test('a write failure that is not a FileSystemException is caught too', () async {
    await editor.load();
    store
      ..writesToFail = 1
      ..writeError = StateError('意外错误');

    editor.onChanged('内容');

    await _waitFor(() => !editor.hasUnsavedChanges);

    expect(await note.readAsString(), '内容');
    expect(editor.error, isNull);
  });

  // Regression: the phase-2 final save was neither awaited nor guarded, so it
  // could escape as an unhandled error or never reach the disk.
  test('close writes the pending edit without waiting for the debounce', () async {
    await editor.load();

    editor.onChanged('关页面前的最后几个字');
    await editor.close();

    expect(editor.hasUnsavedChanges, isFalse);
    expect(await note.readAsString(), '关页面前的最后几个字');
  });

  test('a write that keeps failing never escapes as an unhandled error', () async {
    await editor.load();
    store.writesToFail = 1000;

    editor.onChanged('存不下去的内容');
    await editor.close();

    expect(editor.hasUnsavedChanges, isTrue);
    expect(editor.error, isNotNull);
    expect(await note.readAsString(), '原始内容');
  });

  // Regression: the phase-2 editor showed an empty buffer after a failed read,
  // so the first keystroke replaced a note it had never managed to read.
  test('a note that could not be read cannot be overwritten by typing', () async {
    store.readsToFail = 1;

    await editor.load();

    expect(editor.loadFailed, isTrue);
    expect(editor.canEdit, isFalse);
    expect(editor.text, isEmpty);
    expect(editor.error, isNotNull);

    // The field is disabled while this is true, and the controller refuses the
    // text as well, so neither path can empty the file.
    editor.onChanged('乱打的内容');
    await editor.close();

    expect(await note.readAsString(), '原始内容');
  });

  test('retryLoad recovers once the file can be read again', () async {
    store.readsToFail = 1;
    await editor.load();
    expect(editor.canEdit, isFalse);

    await editor.retryLoad();

    expect(editor.loadFailed, isFalse);
    expect(editor.canEdit, isTrue);
    expect(editor.text, '原始内容');
  });
}
