import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/notes_store.dart';

void main() {
  late Directory tempDir;
  late NotesStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('notes_app_test');
    store = NotesStore(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('createNote makes an empty .md file and avoids name collisions', () async {
    final File first = await store.createNote();
    final File second = await store.createNote();

    expect(first.path, endsWith('.md'));
    expect(second.path, isNot(first.path));
    expect(await first.readAsString(), isEmpty);
    expect(await second.exists(), isTrue);
  });

  test('write then read round-trips note contents', () async {
    final File file = await store.createNote();
    await store.write(file, '# 标题\n\n正文内容');

    expect(await store.read(file), '# 标题\n\n正文内容');
  });

  test('listNotes returns only .md files, newest first, with a preview', () async {
    final File older = await store.createNote();
    await store.write(older, '# 第一篇\n正文');
    await store.createNote(); // newest

    // A file with another extension must be ignored.
    await File('${tempDir.path}${Platform.pathSeparator}ignore.txt')
        .writeAsString('not a note');

    final List<Note> notes = await store.listNotes();

    expect(notes.length, 2);
    expect(notes.first.modified.isAfter(notes.last.modified) ||
        notes.first.modified.isAtSameMomentAs(notes.last.modified), isTrue);
    final Note firstNote =
        notes.firstWhere((Note n) => n.file.path == older.path);
    expect(firstNote.preview, '第一篇');
    expect(firstNote.title, '新建笔记');
  });

  test('delete removes the note file', () async {
    final File file = await store.createNote();
    final List<Note> notes = await store.listNotes();

    await store.delete(notes.single);

    expect(notes.single.file.path, file.path);
    expect(await file.exists(), isFalse);
  });

  test('listNotes on a missing folder returns an empty list', () async {
    final NotesStore missing =
        NotesStore(Directory('${tempDir.path}${Platform.pathSeparator}nope'));
    expect(await missing.listNotes(), isEmpty);
  });
}
