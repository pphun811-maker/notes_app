import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/design.dart';
import 'package:notes_app/markdown_span.dart';

/// Checks one line's flags.
///
/// `hidden` is the set of character positions that must not be seen, and `heading` the
/// heading level of the whole line.
void expectLine(
  String text, {
  Set<int> hidden = const <int>{},
  int heading = 0,
  Set<int> bold = const <int>{},
  Set<int> italic = const <int>{},
  Set<int> strike = const <int>{},
  Set<int> code = const <int>{},
  Set<int> quote = const <int>{},
  Set<int> bar = const <int>{},
  Set<int> checkBox = const <int>{},
}) {
  final List<MarkdownFlags> flags = analyseMarkdown(text);
  expect(flags.length, text.length, reason: '每个字符都要有一个结果');
  for (int i = 0; i < flags.length; i++) {
    final String at = '位置 $i (${text[i]})';
    expect(flags[i].hidden, hidden.contains(i), reason: '$at hidden');
    expect(flags[i].bold, bold.contains(i), reason: '$at bold');
    expect(flags[i].italic, italic.contains(i), reason: '$at italic');
    expect(flags[i].strike, strike.contains(i), reason: '$at strike');
    expect(flags[i].code, code.contains(i), reason: '$at code');
    expect(flags[i].quote, quote.contains(i), reason: '$at quote');
    expect(flags[i].bar, bar.contains(i), reason: '$at bar');
    expect(flags[i].checkBox, checkBox.contains(i), reason: '$at checkBox');
    // 隐藏的标记本身不属于标题的一部分，所以它不该带标题级别。
    expect(flags[i].heading, hidden.contains(i) ? 0 : heading,
        reason: '$at heading');
  }
}

void main() {
  group('headings', () {
    test('# 的井号和空格被隐藏，其余是标题', () {
      expectLine('# 标题', hidden: <int>{0, 1}, heading: 1);
    });

    test('## 是二级标题', () {
      expectLine('## 要买的', hidden: <int>{0, 1, 2}, heading: 2);
    });

    test('六个井号也认', () {
      expectLine('###### 六级', hidden: <int>{0, 1, 2, 3, 4, 5, 6}, heading: 6);
    });

    test('井号后面没有空格就不是标题', () {
      expectLine('#话题');
    });

    test('井号在行中间不算标题', () {
      expectLine('我买了 #牛奶');
    });
  });

  group('列表', () {
    test('短横线和后面的空格都被隐藏', () {
      expectLine('- 牛奶', hidden: <int>{0, 1});
    });

    test('星号和加号也认', () {
      expectLine('* 鸡蛋', hidden: <int>{0, 1});
      expectLine('+ 面包', hidden: <int>{0, 1});
    });

    test('数字编号原样保留', () {
      expectLine('1. 第一步');
      expectLine('12. 第十二步');
    });
  });

  group('待办复选框', () {
    test('- [ ] 的短横线变成方框，其余四个字符隐藏', () {
      expectLine('- [ ] 牛奶', hidden: <int>{1, 2, 3, 4}, checkBox: <int>{0});
    });

    test('- [x] 是已勾选', () {
      final List<MarkdownFlags> flags = analyseMarkdown('- [x] 面包');
      expect(flags[0].checkBox, isTrue);
      expect(flags[0].checked, isTrue);
    });

    test('单独的方括号不做任何处理', () {
      expectLine('[ ] 抬手');
      expectLine('小明 [ ] 抬手');
    });

    test('星号和加号的待办也认（Markdown 里三者等价）', () {
      expectLine('* [ ] 鸡蛋', hidden: <int>{1, 2, 3, 4}, checkBox: <int>{0});
      expectLine('+ [x] 面包', hidden: <int>{1, 2, 3, 4}, checkBox: <int>{0});
    });

    test('方括号不在行首时不处理', () {
      expectLine('文字 [ ] 后面');
      expectLine('a[ ]b');
    });
  });

  group('引用', () {
    test('> 变成竖线，后面整行是引用', () {
      expectLine('> 记得带环保袋', bar: <int>{0}, quote: <int>{2, 3, 4, 5, 6, 7});
    });
  });

  group('行内标记', () {
    test('粗体', () {
      expectLine('**粗体**', hidden: <int>{0, 1, 4, 5}, bold: <int>{2, 3});
    });

    test('斜体', () {
      expectLine('*斜体*', hidden: <int>{0, 3}, italic: <int>{1, 2});
    });

    test('又粗又斜', () {
      expectLine('***全都要***',
          hidden: <int>{0, 1, 2, 6, 7, 8},
          bold: <int>{3, 4, 5},
          italic: <int>{3, 4, 5});
    });

    test('删除线', () {
      expectLine('~~删除~~', hidden: <int>{0, 1, 4, 5}, strike: <int>{2, 3});
    });

    test('行内代码', () {
      expectLine('`行内代码`', hidden: <int>{0, 5}, code: <int>{1, 2, 3, 4});
    });

    // 这条是防回归：如果用单独的正则去匹配斜体，它会在 **粗体** 里面找到一个 *粗体* 
    test('粗体里面的字不会被误判成斜体', () {
      expectLine('**粗体**', hidden: <int>{0, 1, 4, 5}, bold: <int>{2, 3});
    });

    test('一句话里的多个标记', () {
      //            0123456789012345
      // 买 **牛奶** 和 *鸡蛋*
      expectLine('买 **牛奶** 和 *鸡蛋*',
          hidden: <int>{2, 3, 6, 7, 11, 14},
          bold: <int>{4, 5},
          italic: <int>{12, 13});
    });
  });

  group('链接不做处理', () {
    test('[文字](网址) 原样保留', () {
      expectLine('见 [说明](https://example.com)');
    });
  });

  group('多行', () {
    test('每一行各自判断', () {
      //              0123456789...
      // 第一行: # 标题   （#、空格隐藏，标、题是标题）
      // 第二行: 正文
      // 第三行: - [ ] 任务
      const String note = '# 标题\n正文\n- [ ] 任务';
      final List<MarkdownFlags> flags = analyseMarkdown(note);
      expect(flags.length, note.length);
      expect(flags[0].hidden, isTrue);
      expect(flags[2].heading, 1);
      // 第二行的「正文」
      expect(flags[5].heading, 0);
      expect(flags[5].isPlain, isTrue);
      // 第三行的方框
      expect(flags[8].checkBox, isTrue);
    });
  });

  group('画出来的文本必须和原文一样长', () {
    const List<String> notes = <String>[
      '# 购物清单\n\n周末采购。\n\n## 要买的\n- [ ] 牛奶 2 盒\n- [x] 面包\n\n> 记得带环保袋\n',
      '**粗体** 和 *斜体* 和 `代码`',
      '- 普通列表\n1. 数字列表\n\n[ ] 单独的方括号',
      '',
      '\n\n',
    ];

    test('隐藏的标记换成零宽字符，长度一个不差', () {
      for (final String note in notes) {
        final TextSpan span = buildMarkdownSpan(
          text: note,
          base: const TextStyle(fontSize: 14, height: 1.8),
          palette: NotesPalette.light,
        );
        expect(
          span.toPlainText().length,
          note.length,
          reason: '字符数变了，光标就会错位：${note.replaceAll('\n', r'\n')}',
        );
      }
    });

    test('隐藏的字符画成零宽空格', () {
      final TextSpan span = buildMarkdownSpan(
        text: '# 标题',
        base: const TextStyle(fontSize: 14, height: 1.8),
        palette: NotesPalette.light,
      );
      expect(span.toPlainText(), '\u200B\u200B标题');
    });

    test('复选框画成方框，位置就是原来短横线的位置', () {
      final TextSpan span = buildMarkdownSpan(
        text: '- [ ] 牛奶',
        base: const TextStyle(fontSize: 14, height: 1.8),
        palette: NotesPalette.light,
      );
      expect(span.toPlainText(), '\u2610\u200B\u200B\u200B\u200B 牛奶');

      final TextSpan ticked = buildMarkdownSpan(
        text: '- [x] 面包',
        base: const TextStyle(fontSize: 14, height: 1.8),
        palette: NotesPalette.light,
      );
      expect(ticked.toPlainText(), '\u2611\u200B\u200B\u200B\u200B 面包');
    });

    test('引用画成竖线', () {
      final TextSpan span = buildMarkdownSpan(
        text: '> 引用',
        base: const TextStyle(fontSize: 14, height: 1.8),
        palette: NotesPalette.light,
      );
      expect(span.toPlainText(), '\u258D 引用');
    });
  });

  group('点击复选框', () {
    test('点中方框附近会返回要切换的字符位置', () {
      const String note = '- [ ] 牛奶';
      expect(taskBoxIndexAt(note, 0), 3);
      expect(taskBoxIndexAt(note, 1), 3);
      expect(taskBoxIndexAt(note, 4), 3);
    });

    test('点在正文上不算', () {
      expect(taskBoxIndexAt('- [ ] 牛奶', 6), isNull);
      expect(taskBoxIndexAt('- [ ] 牛奶', 8), isNull);
    });

    test('不是待办的行不算', () {
      expect(taskBoxIndexAt('- 牛奶', 0), isNull);
      expect(taskBoxIndexAt('普通正文', 0), isNull);
      expect(taskBoxIndexAt('[ ] 单独方括号', 0), isNull);
    });

    test('多行时只看光标所在的那一行', () {
      const String note = '第一行\n- [ ] 第二行';
      expect(taskBoxIndexAt(note, 0), isNull);
      expect(taskBoxIndexAt(note, 4), 7);
    });

    test('切换会改动方括号里的那个字符', () {
      expect(toggleTaskAt('- [ ] 牛奶', 3), '- [x] 牛奶');
      expect(toggleTaskAt('- [x] 牛奶', 3), '- [ ] 牛奶');
      // 长度不变，所以光标位置仍然有效
      expect(toggleTaskAt('- [ ] 牛奶', 3).length, '- [ ] 牛奶'.length);
    });

    test('已勾选的大写 X 也能取消', () {
      expect(toggleTaskAt('- [X] 牛奶', 3), '- [ ] 牛奶');
    });
  });
}
