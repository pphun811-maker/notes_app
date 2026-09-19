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

    // --- dismissed conflict notices ----------------------------------------

    test('a dismissed conflict notice survives a restart', () async {
      const String copy = '欢迎.sync-conflict-20260919-041500-EPZ7ICC.md';
      final NotesSettingsStore store = storeFor(tempDir);
      await store.dismissConflict(copy);

      final NotesSettingsStore reopened = storeFor(tempDir);
      await reopened.load();

      expect(reopened.isConflictDismissed(copy), isTrue);
      expect(reopened.isConflictDismissed('别的东西.md'), isFalse,
          reason: 'a copy that was never dismissed is still announced');
    });

    test('a new copy is announced even though an older one was dismissed',
        () async {
      final NotesSettingsStore store = storeFor(tempDir);
      await store.dismissConflict('欢迎.sync-conflict-20260918-053116-EPZ7ICC.md');

      final NotesSettingsStore reopened = storeFor(tempDir);
      await reopened.load();

      expect(
        reopened.isConflictDismissed('欢迎.sync-conflict-20260919-041500-EPZ7ICC.md'),
        isFalse,
        reason: 'Syncthing puts the moment in the name, so a new conflict is a new name',
      );
    });

    test('saving a font size keeps the dismissals', () async {
      final NotesSettingsStore store = storeFor(tempDir);
      await store.dismissConflict('a.sync-conflict-1.md');
      await store.save(
        const NotesSettings(fontSize: 20, lineHeight: 1.2, monoFont: true),
      );

      final NotesSettingsStore reopened = storeFor(tempDir);
      await reopened.load();

      expect(reopened.value,
          const NotesSettings(fontSize: 20, lineHeight: 1.2, monoFont: true));
      expect(reopened.isConflictDismissed('a.sync-conflict-1.md'), isTrue,
          reason: 'one file holds both, so neither may overwrite the other');
    });

    test('dismissing the same name twice does not duplicate it', () async {
      final NotesSettingsStore store = storeFor(tempDir);
      await store.dismissConflict('a.sync-conflict-1.md');
      await store.dismissConflict('a.sync-conflict-1.md');
      expect(store.dismissedConflicts, <String>['a.sync-conflict-1.md']);
    });

    test('a damaged file leaves nothing dismissed instead of throwing',
        () async {
      await file.writeAsString('dismissedConflicts\nfontSize=oops\n');
      final NotesSettingsStore store = storeFor(tempDir);
      await store.load();
      expect(store.dismissedConflicts, isEmpty);
    });

    test('no directory means a dismissal is forgotten, not fatal', () async {
      final NotesSettingsStore store =
          NotesSettingsStore(configDirectory: () async => null);
      await store.dismissConflict('a.sync-conflict-1.md');
      expect(store.isConflictDismissed('a.sync-conflict-1.md'), isTrue,
          reason: 'the current session still honours it');
    });

    // --- pinned notes -------------------------------------------------------

    test('pinning then pinning again takes the pin off', () async {
      final NotesSettingsStore store = storeFor(tempDir);
      expect(store.isPinned('欢迎'), isFalse);

      await store.togglePinned('欢迎');
      expect(store.isPinned('欢迎'), isTrue);

      await store.togglePinned('欢迎');
      expect(store.isPinned('欢迎'), isFalse,
          reason: 'the pin is a switch, not a one-way door');
    });

    test('pins survive a restart, in the order they were pinned', () async {
      final NotesSettingsStore store = storeFor(tempDir);
      await store.togglePinned('欢迎');
      await store.togglePinned('购物清单');
      await store.togglePinned('想法');

      final NotesSettingsStore reopened = storeFor(tempDir);
      await reopened.load();

      expect(reopened.pinnedNotes, <String>['欢迎', '购物清单', '想法']);
      expect(reopened.isPinned('购物清单'), isTrue);
      expect(reopened.isPinned('别的东西'), isFalse);
    });

    test('a rename carries the pin to the new title', () async {
      final NotesSettingsStore store = storeFor(tempDir);
      await store.togglePinned('旧名字');
      await store.renamePinned('旧名字', '新名字');

      expect(store.isPinned('新名字'), isTrue);
      expect(store.isPinned('旧名字'), isFalse,
          reason: 'a pin kept under the old name would quietly vanish from the list');
    });

    test('renaming an unpinned note changes nothing', () async {
      final NotesSettingsStore store = storeFor(tempDir);
      await store.togglePinned('甲');
      await store.renamePinned('乙', '丙');
      expect(store.pinnedNotes, <String>['甲'],
          reason: 'every rename goes through this, pinned or not');
    });

    test('a rename keeps the pin where it was in the order', () async {
      final NotesSettingsStore store = storeFor(tempDir);
      await store.togglePinned('甲');
      await store.togglePinned('乙');
      await store.togglePinned('丙');
      await store.renamePinned('乙', '乙改');
      expect(store.pinnedNotes, <String>['甲', '乙改', '丙']);
    });

    test('saving a font size keeps the pins, and pinning keeps the font size',
        () async {
      final NotesSettingsStore store = storeFor(tempDir);
      await store.togglePinned('欢迎');
      await store.save(
        const NotesSettings(fontSize: 20, lineHeight: 1.2, monoFont: true),
      );
      await store.dismissConflict('a.sync-conflict-1.md');

      final NotesSettingsStore reopened = storeFor(tempDir);
      await reopened.load();

      expect(reopened.pinnedNotes, <String>['欢迎']);
      expect(reopened.value,
          const NotesSettings(fontSize: 20, lineHeight: 1.2, monoFont: true));
      expect(reopened.isConflictDismissed('a.sync-conflict-1.md'), isTrue,
          reason: 'three readers share one file, so none may drop the others');
    });

    test('a title holding an = or spaces reads back whole', () async {
      final NotesSettingsStore store = storeFor(tempDir);
      const String awkward = '购物 = 清单 2026';
      await store.togglePinned(awkward);

      final NotesSettingsStore reopened = storeFor(tempDir);
      await reopened.load();

      expect(reopened.pinnedNotes, <String>[awkward],
          reason: 'only the first = separates the key from the value');
    });

    test('a damaged file leaves nothing pinned instead of throwing', () async {
      await file.writeAsString('pinnedNote\nfontSize=oops\n');
      final NotesSettingsStore store = storeFor(tempDir);
      await store.load();
      expect(store.pinnedNotes, isEmpty);
    });
  });
}
