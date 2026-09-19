import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/note_search.dart';

/// The contract for the Windows search box.
///
/// The headline rule is the first one: a plain word is looked for **anywhere in the note**, not
/// only in the first line, which is all the list itself can see. Everything else is the small
/// amount of syntax written on top of that.
void main() {
  const String title = '欢迎';
  const String body = '# 欢迎使用 Notes\n'
      '\n'
      '这篇笔记本身，就是电脑 `D:\\Notes` 文件夹里的一个普通文本文件。\n'
      '以后 Syncthing 会把这两个文件夹同步起来。';

  NoteMatch? run(String query, {String? atTitle, String? atBody, DateTime? at}) {
    return NoteQuery.parse(query).match(
      title: atTitle ?? title,
      body: atBody ?? body,
      modified: at ?? DateTime(2026, 9, 19),
    );
  }

  group('a plain word', () {
    test('is found anywhere in the body, not just the first line', () {
      expect(run('Syncthing'), isNotNull,
          reason: 'this is the whole point: the word is on the last line');
      expect(run('普通文本文件'), isNotNull);
      expect(run('文件夹'), isNotNull);
    });

    test('is found in the title too', () {
      expect(run('欢迎'), isNotNull);
    });

    test('ignores case, both ways round', () {
      expect(run('syncthing'), isNotNull);
      expect(run('NOTES'), isNotNull);
    });

    test('a word that is nowhere does not match', () {
      expect(run('购物清单'), isNull);
    });

    test('several words all have to be there', () {
      expect(run('Syncthing 文件夹'), isNotNull);
      expect(run('Syncthing 购物'), isNull,
          reason: 'a second word narrows; it does not widen');
    });
  });

  group('phrases and exclusions', () {
    test('quotes hold a run of characters together', () {
      expect(run('"普通文本文件"'), isNotNull);
      expect(run('"文本普通"'), isNull, reason: 'the words in the file are in this order');
    });

    test('a quoted phrase can contain spaces', () {
      expect(run('"会把这两个文件夹同步起来"'), isNotNull);
      expect(run('"欢迎使用 Notes"'), isNotNull);
    });

    test('a leading minus excludes', () {
      expect(run('文件夹 -Syncthing'), isNull);
      expect(run('文件夹 -购物'), isNotNull);
    });

    test('an excluded word counts the title as well', () {
      expect(run('文件 -欢迎'), isNull);
    });

    test('a lone minus is just a character', () {
      expect(run('-'), isNull, reason: 'there is no bare minus in the note');
      expect(run('a - b', atBody: 'a - b'), isNotNull);
    });
  });

  group('标题:', () {
    test('searches the title only', () {
      expect(run('标题:欢迎'), isNotNull);
      expect(run('标题:Syncthing'), isNull,
          reason: 'that word is in the body, and this asks about the title');
    });

    test('title: is the same thing in English', () {
      expect(run('title:欢迎'), isNotNull);
      expect(run('title:Syncthing'), isNull);
    });

    test('mixes with ordinary words', () {
      expect(run('标题:欢迎 Syncthing'), isNotNull);
      expect(run('标题:购物 Syncthing'), isNull);
    });

    test('a bare 标题: with nothing after it asks for nothing', () {
      final NoteQuery query = NoteQuery.parse('标题:');
      expect(query.titleTerms, isEmpty);
      expect(query.terms, isEmpty,
          reason: 'searching for the literal characters would empty the list mid-typing');
    });

    test('a bare 之后: with nothing after it asks for nothing', () {
      final NoteQuery query = NoteQuery.parse('之后:');
      expect(query.after, isNull);
      expect(query.terms, isEmpty);
    });
  });

  group('dates', () {
    final DateTime note = DateTime(2026, 9, 19, 10, 30);

    test('之后: keeps notes changed on or after that day', () {
      expect(run('之后:2026/9/19', at: note), isNotNull);
      expect(run('之后:2026/9/20', at: note), isNull);
      expect(run('after:2026/9/1', at: note), isNotNull);
    });

    test('之前: drops notes changed on that day', () {
      expect(run('之前:2026/9/19', at: note), isNull,
          reason: 'changed at 10:30, so not *before* the 19th');
      expect(run('之前:2026/9/20', at: note), isNotNull);
      expect(run('before:2026/9/1', at: note), isNull);
    });

    test('a year or a year and month means the start of that period', () {
      expect(run('之后:2026', at: note), isNotNull);
      expect(run('之前:2026', at: note), isNull);
      expect(run('之后:2026/9', at: note), isNotNull);
      expect(run('之前:2026/8', at: note), isNull);
    });

    test('a date combines with words', () {
      expect(run('Syncthing 之后:2026/9/1', at: note), isNotNull);
      expect(run('购物 之后:2026/9/1', at: note), isNull);
    });

    test('dashes and dots work as well as slashes', () {
      expect(run('之后:2026-09-19', at: note), isNotNull);
      expect(run('之后:2026.9.19', at: note), isNotNull);
    });
  });

  group('something that looks like an operator but is not', () {
    test('a bad date is searched for as ordinary text', () {
      final NoteQuery query = NoteQuery.parse('之后:明年');
      expect(query.after, isNull);
      expect(query.terms, <String>['之后:明年'],
          reason: 'a filter that silently vanished would answer a different question');
    });

    test('and that text is really looked for', () {
      expect(run('之后:明年'), isNull);
      expect(run('之后:明年', atBody: '计划：之后:明年再说'), isNotNull);
    });
  });

  group('the snippet', () {
    test('is the line the word is on, not the first line', () {
      final NoteMatch? found = run('Syncthing');
      expect(found!.snippet, '以后 Syncthing 会把这两个文件夹同步起来。');
    });

    test('has any leading hashes taken off', () {
      expect(run('欢迎使用')!.snippet, '欢迎使用 Notes');
    });

    test('is null when the title is what matched', () {
      expect(run('标题:欢迎')!.snippet, isNull,
          reason: 'the row shows the note\'s own first line; the title is already above it');
    });

    test('is null when only a date was asked for', () {
      expect(run('之后:2026/9/1', at: DateTime(2026, 9, 19))!.snippet, isNull);
    });

    test('skips blank lines', () {
      expect(run('普通文本文件')!.snippet, contains('D:\\Notes'));
    });
  });

  group('the empty query', () {
    test('asks for nothing, and matches everything', () {
      final NoteQuery query = NoteQuery.parse('   ');
      expect(query.isEmpty, isTrue);
      expect(query.looksAtText, isFalse);
      expect(run('   '), isNotNull);
    });

    test('a date-only query does not claim to look at text', () {
      final NoteQuery query = NoteQuery.parse('之后:2026/1/1');
      expect(query.isEmpty, isFalse);
      expect(query.looksAtText, isFalse,
          reason: 'the page uses this to decide whether it has to read the notes at all');
    });
  });

  group('half-typed input', () {
    test('an unterminated quote runs to the end', () {
      expect(run('"普通文本文件'), isNotNull);
    });

    test('extra spaces do not make empty words', () {
      final NoteQuery query = NoteQuery.parse('  Syncthing   文件  ');
      expect(query.terms, <String>['syncthing', '文件']);
    });
  });
}
