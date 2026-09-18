/// The editing state of a single note, and the autosave rules behind it.
///
/// Both editors drive this: the Android one that is about to be written, and the
/// phase-2 desktop one. Keeping the rules here rather than inside a page is what
/// stops the two from drifting apart.
///
/// It is a plain object and not a widget on purpose. "Never lose a note" is the
/// most important rule in this app, so it has to be testable with plain `test()`;
/// a `testWidgets()` test would drag in the fake clock, and awaiting real file IO
/// under that clock hangs forever with no output at all (`HANDOFF_PHASE4.md`
/// section 2.6).
///
/// All three of the following were live data-loss bugs in the phase-2 editor:
///
/// 1. It cleared its "needs saving" flag *before* awaiting the write, so one
///    failed write meant the edit was never written, however much the user typed
///    afterwards. Here the flag is cleared only after a successful write, and
///    only if nothing was typed while that write was running.
/// 2. Its final write, made while the page was closing, was neither awaited nor
///    guarded: a failure escaped as an unhandled async error and the bytes might
///    never reach the disk. Here every write is awaited and every failure caught,
///    including on the paths that nobody is waiting for.
/// 3. When the file could not be read it still showed an empty editor, so the
///    first keystroke replaced the contents of a note it had never read. Here a
///    failed read leaves the note read-only until the user asks to try again.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'notes_store.dart';
import 'strings.dart';

class NoteEditorController extends ChangeNotifier {
  NoteEditorController({
    required this.store,
    required this.file,
    this.debounce = defaultDebounce,
    this.retryDelay = defaultRetryDelay,
    this.maxRetries = defaultMaxRetries,
  });

  final NotesStore store;
  final File file;

  /// How long typing must stop before the note is written.
  ///
  /// 500 ms is part of the synchronisation contract and is not a preference -
  /// see `HANDOFF_PHASE4.md` section 13.4 item 7. Do not change the default.
  static const Duration defaultDebounce = Duration(milliseconds: 500);

  /// How long to wait before trying a write that failed again.
  static const Duration defaultRetryDelay = Duration(seconds: 2);

  /// How many times in a row a failing write is retried before the controller
  /// waits for the next keystroke instead. Without a cap, a folder that can never
  /// be written to would keep the app writing forever.
  static const int defaultMaxRetries = 5;

  /// Overridable so tests do not have to sleep for real seconds.
  final Duration debounce;
  final Duration retryDelay;
  final int maxRetries;

  String _text = '';
  bool _loading = true;
  bool _loadFailed = false;
  bool _dirty = false;
  bool _saving = false;
  bool _closed = false;
  int _edits = 0;
  int _failedWrites = 0;
  String? _error;
  Timer? _timer;
  Future<void> _queue = Future<void>.value();

  /// The text as it is being edited, which may be newer than the file on disk.
  String get text => _text;

  /// True until the first read of the file has finished.
  bool get loading => _loading;

  /// True when the file could not be read.
  ///
  /// [canEdit] is false while this is set, which is what makes it impossible to
  /// overwrite a note with an empty editor.
  bool get loadFailed => _loadFailed;

  /// True while the text on screen is not the text on disk.
  bool get hasUnsavedChanges => _dirty;

  /// True while a write is actually in flight.
  bool get saving => _saving;

  /// The message for the most recent failure, or null when all is well.
  String? get error => _error;

  /// Whether the user may type.
  ///
  /// False while loading, and false after a failed read: an empty editor sitting
  /// on top of an unread note is exactly how a note gets destroyed.
  bool get canEdit => !_loading && !_loadFailed;

  /// Reads the note. Call once, from `initState`.
  Future<void> load() async {
    try {
      final String contents = await store.read(file);
      _text = contents;
      _loadFailed = false;
      _error = null;
    } on FileSystemException catch (error) {
      _loadFailed = true;
      _error = NotesStrings.readFailed(_reasonOf(error));
    } catch (error) {
      // Any other failure to read is treated exactly the same way, so an
      // unexpected error can never turn into a silently emptied note.
      _loadFailed = true;
      _error = NotesStrings.readFailed('$error');
    }
    _loading = false;
    _notify();
  }

  /// Tries the read again after a failure.
  ///
  /// A note can fail to read for reasons that go away by themselves - Syncthing
  /// replacing the file mid-scan, a permission the user has just granted - so the
  /// dead end is made reopenable instead of permanent.
  Future<void> retryLoad() async {
    _loading = true;
    _loadFailed = false;
    _error = null;
    _notify();
    await load();
  }

  /// Called on every keystroke.
  void onChanged(String value) {
    // Unreachable while the field is disabled, and kept as a second line of
    // defence so that a future widget cannot reintroduce the overwrite bug.
    if (!canEdit) return;
    _text = value;
    _edits++;
    _dirty = true;
    _error = null;
    _failedWrites = 0;
    _scheduleFlush(debounce);
    _notify();
  }

  /// Writes the note if there is anything to write, and waits for any write that
  /// is already running.
  ///
  /// Deliberately never completes with an error: a failed write is reported
  /// through [error] and leaves [hasUnsavedChanges] true so that it can be tried
  /// again. That is what lets the debounce timer and the app-lifecycle callback
  /// call this without awaiting it - turning a failed save into an unhandled
  /// async error is precisely how the phase-2 editor lost its last write.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    final Future<void> started = _queue
        .then<void>((void _) => _writeUntilClean())
        // A failure anywhere earlier in the queue must not be allowed to stop
        // this write: saving is the one thing that always has to be attempted.
        .catchError((Object _) => _writeUntilClean());
    _queue = started;
    return started;
  }

  /// Writes anything still pending and stops the timers.
  ///
  /// Call this before the page goes away, and from a `PopScope` handler rather
  /// than from `dispose()`: `dispose()` cannot await, and on Android a process
  /// can be killed without `dispose()` running at all. After this the controller
  /// stops notifying listeners, so it is safe to dispose straight away.
  ///
  /// Never throws.
  Future<void> close() async {
    _timer?.cancel();
    _timer = null;
    _closed = true;
    try {
      await flush();
    } catch (_) {
      // The page is on its way out; a failure here has already been reported
      // through [error] and there is nowhere left to show it.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    // Notifications are switched off first: listeners are being torn down with
    // the page, and touching them here would throw.
    _closed = true;
    // Last-resort backstop. A page is expected to have called [close] already
    // (from `PopScope`, and from the lifecycle callback when the app is
    // backgrounded); if it has not, this at least starts the write instead of
    // dropping it on the floor.
    if (_dirty && canEdit) {
      unawaited(flush());
    }
    super.dispose();
  }

  /// Writes until there is nothing left to write.
  ///
  /// A loop rather than a single write, because the user can keep typing while a
  /// write is in flight; in that case the note is still dirty when the write
  /// returns and it goes round again with the newer text.
  Future<void> _writeUntilClean() async {
    while (_dirty) {
      final int edit = _edits;
      final String contents = _text;
      _saving = true;
      _notify();
      try {
        await store.write(file, contents);
      } catch (error) {
        // Stay dirty. The edit exists only in memory, so the next keystroke and
        // the retry timer both get another chance to put it on disk.
        _saving = false;
        _dirty = true;
        _error = NotesStrings.saveFailed(_reasonOf(error));
        _failedWrites++;
        _notify();
        if (_failedWrites <= maxRetries) {
          _scheduleFlush(retryDelay);
        }
        return;
      }
      _saving = false;
      _failedWrites = 0;
      _error = null;
      // Cleared only now, and only when nothing was typed during the write.
      if (_edits == edit) {
        _dirty = false;
      }
      _notify();
    }
  }

  void _scheduleFlush(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      // Nobody is waiting for this one; [flush] does not complete with an error.
      unawaited(flush());
    });
  }

  /// The readable half of an exception, for a message the user can act on.
  String _reasonOf(Object error) {
    if (error is FileSystemException) {
      return error.osError?.message ?? error.message;
    }
    return '$error';
  }

  void _notify() {
    if (_closed) return;
    notifyListeners();
  }
}
