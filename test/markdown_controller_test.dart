import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/markdown_controller.dart';

/// The contract for the Windows editor's "源码" switch.
///
/// The markers are always in the file - the renderer only changes what is *drawn*, hiding them
/// behind zero-width characters. These tests pin that down from both sides: nothing the switch
/// does may reach the note's own characters, and the rendered side must keep hiding them.
void main() {
  /// Builds a span for [text] with a real `BuildContext`, which `buildTextSpan` asks for.
  Future<TextSpan> spanFor(
    WidgetTester tester,
    MarkdownEditingController controller,
    String text, {
    bool withComposing = false,
  }) async {
    controller.text = text;
    late TextSpan span;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            span = controller.buildTextSpan(
              context: context,
              style: const TextStyle(fontSize: 16),
              withComposing: withComposing,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return span;
  }

  testWidgets('rendered: the heading marker is not in the drawn text',
      (WidgetTester tester) async {
    final MarkdownEditingController controller = MarkdownEditingController();
    final TextSpan span = await spanFor(tester, controller, '# 购物清单');

    expect(span.toPlainText(), isNot(contains('#')),
        reason: 'the marker is drawn as a zero-width character, not as a hash');
    expect(span.toPlainText(), contains('购物清单'));
    controller.dispose();
  });

  testWidgets('source: the drawn text is the file, character for character',
      (WidgetTester tester) async {
    const String note = '# 购物清单\n\n- [ ] 牛奶\n- [x] 面包\n\n> 引用\n\n**粗体** `代码`';
    final MarkdownEditingController controller = MarkdownEditingController();
    controller.sourceMode = true;

    final TextSpan span = await spanFor(tester, controller, note);

    expect(span.toPlainText(), note,
        reason: 'the whole point of the switch is to see exactly what is in the file');
    controller.dispose();
  });

  testWidgets('source: switching back hides the markers again',
      (WidgetTester tester) async {
    final MarkdownEditingController controller = MarkdownEditingController();
    controller.sourceMode = true;
    expect((await spanFor(tester, controller, '# 标题')).toPlainText(), '# 标题');

    controller.sourceMode = false;
    expect(
      (await spanFor(tester, controller, '# 标题')).toPlainText(),
      isNot(contains('#')),
    );
    controller.dispose();
  });

  testWidgets('source: text is never rewritten, only drawn',
      (WidgetTester tester) async {
    const String note = '## 二\n**粗**';
    final MarkdownEditingController controller = MarkdownEditingController();
    controller.sourceMode = true;
    await spanFor(tester, controller, note);

    expect(controller.text, note,
        reason: 'a switch over what is drawn must not be able to change the note');
    controller.dispose();
  });

  testWidgets('source: an IME mid-word region is still underlined',
      (WidgetTester tester) async {
    final MarkdownEditingController controller = MarkdownEditingController();
    controller.sourceMode = true;
    // What a Chinese IME leaves in the field before a character is committed.
    controller.value = const TextEditingValue(
      text: 'nihao你好',
      composing: TextRange(start: 0, end: 5),
      selection: TextSelection.collapsed(offset: 5),
    );

    late TextSpan span;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            span = controller.buildTextSpan(
              context: context,
              style: const TextStyle(fontSize: 16),
              withComposing: true,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(span.toPlainText(), 'nihao你好');
    final List<InlineSpan> parts = span.children!;
    final String underlined = parts
        .where((InlineSpan s) => s.style?.decoration == TextDecoration.underline)
        .map((InlineSpan s) => (s as TextSpan).text ?? '')
        .join();
    expect(underlined, 'nihao',
        reason: 'without this, typing Chinese looks like it stopped working');
    controller.dispose();
  });

  testWidgets('default is rendered, so nothing changes unless it is asked for',
      (WidgetTester tester) async {
    final MarkdownEditingController controller = MarkdownEditingController();
    expect(controller.sourceMode, isFalse);
    expect(
      (await spanFor(tester, controller, '# 标题')).toPlainText(),
      isNot(contains('#')),
    );
    controller.dispose();
  });
}
