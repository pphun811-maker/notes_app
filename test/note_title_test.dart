import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/note_title.dart';

/// The title is the file name, so every one of these cases is a file the app would
/// otherwise try to create. The folder is shared with Windows through Syncthing, so a name
/// only has to be illegal on one of the two systems to matter.
void main() {
  test('普通标题原样保留', () {
    expect(sanitiseNoteTitle('购物清单'), '购物清单');
    expect(sanitiseNoteTitle('Notes 2026'), 'Notes 2026');
  });

  test('首尾空白去掉', () {
    expect(sanitiseNoteTitle('  购物清单  '), '购物清单');
    expect(sanitiseNoteTitle('\t购物清单\n'), '购物清单');
  });

  test('Windows 不允许的字符换成空格', () {
    expect(sanitiseNoteTitle('a/b'), 'a b');
    expect(sanitiseNoteTitle('a\\b'), 'a b');
    expect(sanitiseNoteTitle('12:30 开会'), '12 30 开会');
    expect(sanitiseNoteTitle('重要?'), '重要');
    expect(sanitiseNoteTitle('他说"好"'), '他说 好');
    expect(sanitiseNoteTitle('a<b>c'), 'a b c');
    expect(sanitiseNoteTitle('a|b'), 'a b');
    expect(sanitiseNoteTitle('a*b'), 'a b');
  });

  test('连续的分隔符只留一个空格', () {
    expect(sanitiseNoteTitle('a///b'), 'a b');
    expect(sanitiseNoteTitle('a  //  b'), 'a b');
  });

  test('控制字符直接丢掉', () {
    expect(sanitiseNoteTitle('a\u0001b'), 'ab');
    expect(sanitiseNoteTitle('a\u007Fb'), 'ab');
  });

  test('结尾的点去掉（Windows 不接受）', () {
    expect(sanitiseNoteTitle('购物清单.'), '购物清单');
    expect(sanitiseNoteTitle('等等...'), '等等');
    expect(sanitiseNoteTitle('a. . '), 'a');
  });

  test('中间的点保留', () {
    expect(sanitiseNoteTitle('v1.2 说明'), 'v1.2 说明');
  });

  // 返回空串表示「没有可用的名字」，调用方必须理解为「保持原名」，绝不能拿去建文件。
  test('只剩下非法字符时返回空串', () {
    expect(sanitiseNoteTitle(''), '');
    expect(sanitiseNoteTitle('   '), '');
    expect(sanitiseNoteTitle('///'), '');
    expect(sanitiseNoteTitle('...'), '');
  });

  test('Windows 的保留设备名前面加下划线', () {
    expect(sanitiseNoteTitle('CON'), '_CON');
    expect(sanitiseNoteTitle('nul'), '_nul');
    expect(sanitiseNoteTitle('COM1'), '_COM1');
    expect(sanitiseNoteTitle('LPT9'), '_LPT9');
    // 只是碰巧开头一样的不算
    expect(sanitiseNoteTitle('CONSOLE'), 'CONSOLE');
  });

  test('过长的名字按字节截断到 255 字节以内（含 .md）', () {
    final String long = '标' * 200; // 600 字节
    final String cleaned = sanitiseNoteTitle(long);
    expect(utf8.encode('$cleaned.md').length, lessThanOrEqualTo(255));
    expect(cleaned.isNotEmpty, isTrue);
  });

  test('截断后不会留下结尾的空格或点', () {
    final String cleaned = sanitiseNoteTitle('${'a' * 300} .');
    expect(cleaned.endsWith(' '), isFalse);
    expect(cleaned.endsWith('.'), isFalse);
  });

  test('emoji 也按字节算', () {
    final String cleaned = sanitiseNoteTitle('😀' * 100); // 每个 4 字节
    expect(utf8.encode('$cleaned.md').length, lessThanOrEqualTo(255));
  });
}
