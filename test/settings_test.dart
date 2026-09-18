import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/settings.dart';

void main() {
  group('encode/decode', () {
    test('round-trips every value', () {
      const NotesSettings settings = NotesSettings(
        fontSize: 18,
        lineHeight: 1.6,
        monoFont: true,
      );
      expect(NotesSettings.decode(settings.encode()), settings);
    });

    test('an empty file gives the defaults', () {
      expect(NotesSettings.decode(''), NotesSettings.defaults);
    });

    test('a damaged line is skipped and the rest still read', () {
      final NotesSettings settings =
          NotesSettings.decode('fontSize=20\ngarbage\nlineHeight=oops\n');
      expect(settings.fontSize, 20);
      expect(settings.lineHeight, NotesSettings.defaults.lineHeight);
      expect(settings.monoFont, NotesSettings.defaults.monoFont);
    });

    test('the default line height is the one the user chose', () {
      expect(NotesSettings.defaults.lineHeight, 1.5);
      expect(NotesSettings.defaults.fontSize, 14);
    });
  });

  group('store', () {
    late Directory tempDir;
    late File file;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('notes_settings_test');
      file = File('${tempDir.path}${Platform.pathSeparator}settings.txt');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    NotesSettingsStore storeFor(Directory directory) =>
        NotesSettingsStore(configDirectory: () async => directory.path);

    test('saves and reads back', () async {
      final NotesSettingsStore store = storeFor(tempDir);
      await store.save(
        const NotesSettings(fontSize: 20, lineHeight: 1.2, monoFont: true),
      );

      final NotesSettingsStore reopened = storeFor(tempDir);
      expect(
        await reopened.load(),
        const NotesSettings(fontSize: 20, lineHeight: 1.2, monoFont: true),
      );
    });

    test('a missing file just means the defaults', () async {
      final NotesSettingsStore store = storeFor(tempDir);
      expect(await store.load(), NotesSettings.defaults);
    });

    // 设置读不出来也绝不能妨碍打开笔记。
    test('a damaged file falls back to the defaults instead of throwing', () async {
      await file.writeAsString('fontSize=not-a-number\nlineHeight=\n');
      final NotesSettingsStore store = storeFor(tempDir);
      expect(await store.load(), NotesSettings.defaults);
    });

    test('creates the directory if it is not there yet', () async {
      final Directory nested =
          Directory('${tempDir.path}${Platform.pathSeparator}a'
              '${Platform.pathSeparator}b');
      final NotesSettingsStore store = storeFor(nested);
      await store.save(const NotesSettings(
        fontSize: 24,
        lineHeight: 2.0,
        monoFont: false,
      ));
      expect(
        await File('${nested.path}${Platform.pathSeparator}settings.txt').exists(),
        isTrue,
      );
    });

    test('loads once and then keeps the value', () async {
      final NotesSettingsStore store = storeFor(tempDir);
      await store.save(
        const NotesSettings(fontSize: 16, lineHeight: 1.5, monoFont: false),
      );
      // 模拟磁盘上被别的东西改掉：已经读过就不该再读一次。
      await file.writeAsString(
        const NotesSettings(fontSize: 12, lineHeight: 1.5, monoFont: false)
            .encode(),
      );
      expect(await store.load(), const NotesSettings(
        fontSize: 16,
        lineHeight: 1.5,
        monoFont: false,
      ));
    });

    test('no directory means no crash and no persistence', () async {
      final NotesSettingsStore store =
          NotesSettingsStore(configDirectory: () async => null);
      await store.save(
        const NotesSettings(fontSize: 22, lineHeight: 1.4, monoFont: false),
      );
      expect(store.value.fontSize, 22);
      expect(await store.load(), store.value);
    });
  });
}
