import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/markdown_text.dart';

/// These tests are the contract for "复制为纯文本": what the user sees on screen is
/// what lands on the clipboard. Every rule here was asked for by name - change one
/// and this file should fail.
void main() {
  test('heading hashes are dropped', () {
    expect(markdownToPlainText('# 购物清单'), '购物清单');
    expect(markdownToPlainText('## 要买的'), '要买的');
    expect(markdownToPlainText('###### 六级标题'), '六级标题');
  });

  test('a heading without a space after the hashes is left alone', () {
    // Standard Markdown needs the space, and the user writes ordinary text too.
    expect(markdownToPlainText('#话题'), '#话题');
  });

  test('the bullet dash is dropped', () {
    expect(markdownToPlainText('- 牛奶'), '牛奶');
    expect(markdownToPlainText('* 鸡蛋'), '鸡蛋');
    expect(markdownToPlainText('+ 面包'), '面包');
  });

  test('a task item keeps its brackets but loses the bullet', () {
    expect(markdownToPlainText('- [ ] 牛奶 2 盒'), '[ ] 牛奶 2 盒');
    expect(markdownToPlainText('- [x] 面包'), '[x] 面包');
  });

  // The user asked for these two by name: numbered lists are typed on purpose, and a
  // bare `[ ]` is used to mark up things like stage directions.
  test('numbered lists are never touched', () {
    expect(markdownToPlainText('1. 第一步'), '1. 第一步');
    expect(markdownToPlainText('2. 第二步'), '2. 第二步');
  });

  test('a bare checkbox is never touched', () {
    expect(markdownToPlainText('[ ] 抬手'), '[ ] 抬手');
    expect(markdownToPlainText('小明 [ ] 抬手'), '小明 [ ] 抬手');
  });

  test('links are not implemented, so their characters stay', () {
    expect(
      markdownToPlainText('见 [说明](https://example.com)'),
      '见 [说明](https://example.com)',
    );
  });

  test('quotes lose their marker', () {
    expect(markdownToPlainText('> 记得带环保袋'), '记得带环保袋');
  });

  test('emphasis markers are removed', () {
    expect(markdownToPlainText('**粗体**'), '粗体');
    expect(markdownToPlainText('*斜体*'), '斜体');
    expect(markdownToPlainText('***又粗又斜***'), '又粗又斜');
    expect(markdownToPlainText('~~删除线~~'), '删除线');
    expect(markdownToPlainText('`行内代码`'), '行内代码');
  });

  test('emphasis inside a sentence is removed in place', () {
    expect(
      markdownToPlainText('今天买 **牛奶** 和 *鸡蛋*，别忘了 `咖啡`。'),
      '今天买 牛奶 和 鸡蛋，别忘了 咖啡。',
    );
  });

  test('a horizontal rule is not mistaken for a bullet', () {
    expect(markdownToPlainText('---'), '---');
  });

  test('blank lines and the line count are preserved', () {
    const String source = '# 标题\n\n- [ ] 一\n- [ ] 二\n\n> 引用';
    expect(
      markdownToPlainText(source),
      '标题\n\n[ ] 一\n[ ] 二\n\n引用',
    );
  });

  test('a whole note reads the way it looks on screen', () {
    const String source = '# 购物清单\n'
        '\n'
        '周末采购，顺便把冰箱清一下。\n'
        '\n'
        '## 要买的\n'
        '- [ ] 牛奶 2 盒\n'
        '- [x] 面包\n'
        '\n'
        '> 记得带环保袋\n';
    expect(
      markdownToPlainText(source),
      '购物清单\n'
      '\n'
      '周末采购，顺便把冰箱清一下。\n'
      '\n'
      '要买的\n'
      '[ ] 牛奶 2 盒\n'
      '[x] 面包\n'
      '\n'
      '记得带环保袋\n',
    );
  });
}
