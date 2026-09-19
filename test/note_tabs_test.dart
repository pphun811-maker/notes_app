import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/desktop/note_tabs.dart';

/// The tab set is where "never lose a note" meets "several notes at once": two tabs over one
/// file would each autosave over the other, and a tab left pointing at a path that has been
/// renamed away makes the next refresh close the editor the user is typing in. None of that is
/// visible in the interface until it has already gone wrong, so all of it is pinned here.
void main() {
  File note(String name) => File('C:\\Notes\\$name.md');

  /// `File` compares by identity, not by path, so comparing two lists of them would fail even
  /// when every path matches. The model itself compares `.path` throughout - that is the whole
  /// reason `_key` exists - and these are the assertions that check it.
  List<String> paths(List<File> files) =>
      files.map((File f) => f.path).toList(growable: false);

  final File a = note('甲');
  final File b = note('乙');
  final File c = note('丙');

  group('opening', () {
    test('an empty set has nothing current', () {
      const NoteTabs tabs = NoteTabs.empty();
      expect(tabs.isEmpty, isTrue);
      expect(tabs.current, isNull);
      expect(tabs.length, 0);
    });

    test('opening adds the note at the right and makes it current', () {
      final NoteTabs tabs = const NoteTabs.empty().open(a).open(b);
      expect(paths(tabs.files), paths(<File>[a, b]));
      expect(tabs.current!.path, b.path);
    });

    test('opening a note that is already open selects it instead of adding it twice', () {
      final NoteTabs tabs = const NoteTabs.empty().open(a).open(b).open(a);
      expect(tabs.length, 2, reason: '同一篇笔记绝不能有两个标签');
      expect(tabs.current!.path, a.path);
      expect(tabs.currentIndex, 0);
    });
  });

  group('closing', () {
    test('closing the current tab selects the one to its right', () {
      final NoteTabs tabs = const NoteTabs.empty().open(a).open(b).open(c).select(1);
      expect(tabs.close(1).current, c);
    });

    test('closing the last tab selects the one to its left', () {
      final NoteTabs tabs = const NoteTabs.empty().open(a).open(b).open(c);
      expect(tabs.close(2).current, b);
    });

    test('closing a tab to the left of the current one keeps the same note current', () {
      final NoteTabs tabs = const NoteTabs.empty().open(a).open(b).open(c);
      expect(tabs.current!.path, c.path);
      final NoteTabs after = tabs.close(0);
      expect(after.current, c, reason: '关掉左边的标签不该把正在看的那篇换掉');
      expect(after.currentIndex, 1);
    });

    test('closing the only tab leaves nothing open', () {
      final NoteTabs tabs = const NoteTabs.empty().open(a).close(0);
      expect(tabs.isEmpty, isTrue);
      expect(tabs.current, isNull);
    });

    test('closeFile finds the note wherever it is', () {
      final NoteTabs tabs = const NoteTabs.empty().open(a).open(b).open(c);
      expect(paths(tabs.closeFile(a).files), paths(<File>[b, c]));
    });
  });

  group('renaming', () {
    test('a renamed note keeps its tab, its position and its place in the order', () {
      final NoteTabs tabs = const NoteTabs.empty().open(a).open(b).open(c).select(1);
      final NoteTabs after = tabs.replace(b, note('乙改名'));
      expect(paths(after.files), paths(<File>[a, note('乙改名'), c]));
      expect(after.current!.path, note('乙改名').path);
    });

    test('renaming a note onto one that is already open does not leave two tabs', () {
      final NoteTabs tabs = const NoteTabs.empty().open(a).open(b);
      final NoteTabs after = tabs.replace(a, b);
      expect(after.length, 1, reason: '两个标签指向同一个文件就是两次自动保存互相覆盖');
      expect(paths(after.files), paths(<File>[b]));
      expect(after.current!.path, b.path);
    });

    test('renaming a note that is not open changes nothing', () {
      final NoteTabs tabs = const NoteTabs.empty().open(a);
      expect(tabs.replace(b, c), tabs);
    });
  });

  group('notes that go away', () {
    test('forget drops the tab, and the neighbour becomes current', () {
      final NoteTabs tabs = const NoteTabs.empty().open(a).open(b).open(c).select(1);
      final NoteTabs after = tabs.forget(b);
      expect(paths(after.files), paths(<File>[a, c]));
      expect(after.current!.path, c.path);
    });

    test('retainOnly keeps the notes that are still there and keeps the current one', () {
      final NoteTabs tabs = const NoteTabs.empty().open(a).open(b).open(c).select(1);
      final NoteTabs after = tabs.retainOnly(<File>[a, b]);
      expect(paths(after.files), paths(<File>[a, b]));
      expect(after.current!.path, b.path);
    });

    test('retainOnly moves the selection when the current note is the one that went', () {
      final NoteTabs tabs = const NoteTabs.empty().open(a).open(b).open(c).select(2);
      final NoteTabs after = tabs.retainOnly(<File>[a, b]);
      expect(after.current, b, reason: '当前那篇没了，落到还开着的最后一篇上');
    });

    test('retainOnly with nothing left closes everything', () {
      final NoteTabs tabs = const NoteTabs.empty().open(a).open(b);
      expect(tabs.retainOnly(<File>[]).isEmpty, isTrue);
    });

    test('retainOnly that changes nothing returns the same value', () {
      final NoteTabs tabs = const NoteTabs.empty().open(a).open(b);
      expect(tabs.retainOnly(<File>[a, b, c]), same(tabs));
    });
  });

  test('equality is by path, so a rebuilt list does not look like a change', () {
    const NoteTabs tabs = NoteTabs.empty();
    expect(tabs.open(a).open(b), tabs.open(a).open(b));
    expect(tabs.open(a).open(b).hashCode, tabs.open(a).open(b).hashCode);
    expect(tabs.open(a).open(b), isNot(tabs.open(a).open(b).select(0)));
  });
}
