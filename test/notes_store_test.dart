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

  test('rename moves the note to the new name and keeps its contents', () async {
    final File file = await store.createNote();
    await store.write(file, '内容');

    final File renamed = await store.rename(file, '购物清单');

    expect(renamed.path, endsWith('购物清单.md'));
    expect(await renamed.readAsString(), '内容');
    expect(await file.exists(), isFalse);
  });

  test('rename never writes over another note; it numbers the name instead', () async {
    final File first = await store.createNote();
    await store.write(first, '第一篇');
    final File second = await store.createNote();
    await store.write(second, '第二篇');

    final File renamed = await store.rename(second, '新建笔记');

    expect(renamed.path, isNot(first.path));
    expect(renamed.path, endsWith('新建笔记 2.md'));
    // 两篇都还在，内容都没被覆盖。
    expect(await first.readAsString(), '第一篇');
    expect(await renamed.readAsString(), '第二篇');
  });

  test('rename to the same name changes nothing', () async {
    final File file = await store.createNote();
    final File same = await store.rename(file, '新建笔记');
    expect(same.path, file.path);
    expect(await file.exists(), isTrue);
  });

  // --- Syncthing conflict copies -------------------------------------------

  test('listNotes leaves conflict copies out but does not delete them', () async {
    final File note = await store.createNote();
    await store.write(note, '正文');
    final File copy = File('${tempDir.path}${Platform.pathSeparator}'
        '新建笔记.sync-conflict-20260918-053116-EPZ7ICC.md');
    await copy.writeAsString('来自另一台设备的内容');

    final List<Note> notes = await store.listNotes();

    expect(notes.length, 1, reason: 'the copy is not a note');
    expect(notes.single.file.path, note.path);
    expect(await copy.exists(), isTrue,
        reason: 'hiding a copy must never remove it: it may hold the only content');
    expect(await copy.readAsString(), '来自另一台设备的内容');
  });

  test('listConflictCopies returns exactly the copies', () async {
    final File note = await store.createNote();
    await store.write(note, '正文');
    final File copy = File('${tempDir.path}${Platform.pathSeparator}'
        '新建笔记.sync-conflict-20260918-053116-EPZ7ICC.md');
    await copy.writeAsString('另一份内容');

    final List<Note> copies = await store.listConflictCopies();

    expect(copies.length, 1);
    expect(copies.single.file.path, copy.path);
    expect(copies.single.title,
        '新建笔记.sync-conflict-20260918-053116-EPZ7ICC',
        reason: 'the raw title is what the conflict page parses');
    expect(copies.single.preview, isEmpty,
        reason: 'listing a copy must not read it; the page reads it when opened');
  });

  test('listConflictCopies is empty when there are no copies', () async {
    await store.createNote();
    expect(await store.listConflictCopies(), isEmpty);
  });

  test('the two listings never overlap', () async {
    await store.write(await store.createNote(), '甲');
    await store.write(await store.createNote(), '乙');
    await File('${tempDir.path}${Platform.pathSeparator}甲.sync-conflict-20260918-053116-EPZ7ICC.md')
        .writeAsString('甲的另一份');

    final Set<String> notes =
        (await store.listNotes()).map((Note n) => n.file.path).toSet();
    final Set<String> copies = (await store.listConflictCopies())
        .map((Note n) => n.file.path)
        .toSet();

    expect(notes.length, 2);
    expect(copies.length, 1);
    expect(notes.intersection(copies), isEmpty);
  });
}
