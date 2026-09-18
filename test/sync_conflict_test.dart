import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/sync_conflict.dart';

/// Syncthing's conflict-copy names.
///
/// The app decides "this file is not a note" from the file name alone, so the name handling
/// is pinned down here rather than through a folder: the failure that matters is a copy that
/// is *not* recognised, because that is the one that turns up in the list looking like a note
/// with a nonsense title.
void main() {
  const String realCopy =
      '新建笔记.sync-conflict-20260918-053116-EPZ7ICC.md';

  group('isConflictCopy', () {
    test('recognises the name Syncthing actually wrote on this device', () {
      // Taken from .stversions on the phone, so this is the real shape, not a guess.
      expect(SyncConflict.isConflictCopy(realCopy), isTrue);
    });

    test('accepts a name with or without the extension', () {
      expect(
        SyncConflict.isConflictCopy(
          '新建笔记.sync-conflict-20260918-053116-EPZ7ICC',
        ),
        isTrue,
      );
    });

    test('ignores case', () {
      expect(
        SyncConflict.isConflictCopy(
          '笔记.Sync-Conflict-20260918-053116-EPZ7ICC.md',
        ),
        isTrue,
      );
    });

    test('leaves ordinary notes alone', () {
      expect(SyncConflict.isConflictCopy('新建笔记.md'), isFalse);
      expect(SyncConflict.isConflictCopy('欢迎 2.md'), isFalse);
      expect(SyncConflict.isConflictCopy('笔记.txt'), isFalse);
      // Without the leading dot this is not Syncthing's marker.
      expect(SyncConflict.isConflictCopy('sync-conflict.md'), isFalse);
    });
  });

  group('originalTitle', () {
    test('names the note the copy belongs to', () {
      expect(SyncConflict.originalTitle(realCopy), '新建笔记');
    });

    test('keeps dots and spaces that were in the original name', () {
      expect(
        SyncConflict.originalTitle(
          'v1.2 计划.sync-conflict-20260918-053116-EPZ7ICC.md',
        ),
        'v1.2 计划',
      );
    });

    test('works on a name without the extension', () {
      expect(
        SyncConflict.originalTitle('欢迎.sync-conflict-20260918-053116-EPZ7ICC'),
        '欢迎',
      );
    });

    test('returns nothing for an ordinary note', () {
      expect(SyncConflict.originalTitle('新建笔记.md'), isEmpty);
    });

    test('returns nothing when the marker is the whole name', () {
      // A file called `.sync-conflict-….md` belongs to no named note; the caller falls back
      // to the file's own name rather than showing an empty row.
      expect(
        SyncConflict.originalTitle('.sync-conflict-20260918-053116-EPZ7ICC.md'),
        isEmpty,
      );
    });
  });
}
