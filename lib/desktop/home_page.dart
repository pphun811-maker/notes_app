import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
// `AppExitResponse` is declared in dart:ui and is not re-exported by material.
import 'dart:ui' show AppExitResponse;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design.dart';
import '../format.dart';
import '../note_editor_controller.dart';
import '../note_search.dart';
import '../notes_store.dart';
import '../settings.dart';
import '../strings.dart';
import '../sync_conflict.dart';
import 'desktop_design.dart';
import 'editor_pane.dart';
import 'note_tabs.dart';
import 'recycle_bin.dart';
import 'window_channel.dart';

/// The Windows interface.
///
/// Three bands, and the reason for each:
///
///  * **the tab strip, at the very top.** There is no title bar above it - the OS one is
///    removed in `win32_window.cpp` and the window buttons are drawn here instead. The strip is
///    a shade darker than the sidebar, which is what lets the selected tab be the *editor's*
///    colour and read as one shape with it rather than as a button lying near it;
///  * **the sidebar.** The page tone, no outline: the two columns are told apart by colour, not
///    by a line drawn between them;
///  * **the editor.** The note's surface, full bleed, with the paragraph column centred inside
///    it.
///
/// This is a rewrite, not the phase-2 page moved: that one was a list of full-width rows with a
/// floating button and a pushed full-screen editor, which is a phone layout in a wide window.
/// What it shares with the Android interface is everything that is not drawing - the same
/// [NotesStore], the same [NoteEditorController] save rules, the same Markdown renderer.
class NotesHomePage extends StatefulWidget {
  const NotesHomePage({super.key, this.store, this.accent});

  /// The data layer to read notes from. Tests inject a temporary folder.
  final NotesStore? store;

  /// Overrides the accent read out of the Windows registry, so a test does not depend on the
  /// machine it happens to run on.
  final SystemAccent? accent;

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage>
    with WidgetsBindingObserver {
  late final NotesStore _store =
      widget.store ?? NotesStore(Directory(NotesStore.defaultDirectoryPath));

  /// One editor per open note, kept alive whether or not it is the one on screen.
  ///
  /// Keyed by path so the shell can ask a particular tab to write - before it is closed, and
  /// before the window goes away. The editors stay mounted inside an [IndexedStack], which is
  /// what makes switching tabs free: nothing is rebuilt, so the text, the selection and the
  /// undo history are all still there.
  final Map<String, GlobalKey<EditorPaneState>> _paneKeys =
      <String, GlobalKey<EditorPaneState>>{};

  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  SystemAccent _accent = SystemAccent.fallback;
  List<Note> _notes = <Note>[];

  /// Syncthing's conflict copies, which [NotesStore.listNotes] deliberately leaves out.
  ///
  /// Kept apart from [_notes] the whole way through: nothing in the sidebar, the tabs or the
  /// editor ever renders one of these as a note, because its "title" is a long generated name
  /// and it may hold the only copy of what was typed on the phone.
  List<Note> _conflicts = <Note>[];

  /// The notes that are open, and which of them is on screen.
  NoteTabs _tabs = const NoteTabs.empty();
  bool _loading = true;
  /// What is in the search box, parsed.
  ///
  /// The parsed form and not the raw string: every read of it is a question about what it asks
  /// for, and re-parsing on each of those would be re-doing the same work several times a
  /// build. The raw text is not kept - the field's own controller has it.
  NoteQuery _parsed = NoteQuery.empty;

  /// The full text of each note, keyed by path - what the search looks through.
  ///
  /// Read lazily, only once something is actually being searched for, and stamped with
  /// [_bodiesStamp] so a note that changed on disk is read again.
  Map<String, String> _bodies = <String, String>{};
  String _bodiesStamp = '';
  bool _bodiesLoading = false;
  String? _error;
  double _sidebarWidth = NotesDesktopMetrics.sidebarDefault;

  /// How far the tab strip has been scrolled, in logical pixels.
  ///
  /// Scrolled by hand rather than with a `ScrollView`: the strip is also the window's drag
  /// handle, and a scroll view sitting on top of it would swallow the drags that move the
  /// window before they ever reached it.
  double _tabScroll = 0;

  /// The width the strip was last laid out with, for the scrolling decisions.
  double _tabStripWidth = 0;

  /// The space between two tabs.
  static const double _tabGap = 2;

  /// The notes folder's watcher, and the delay that turns its bursts into one refresh.
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _folderDebounce;

  /// Whether the note list is folded away.
  ///
  /// Remembered between visits in the app's own settings file (see `settings.dart`), not in the
  /// notes folder.
  bool _sidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The page draws the button that changes this, so it has to hear about the change even
    // when the pixels do not: light → dark while Windows is already dark looks like nothing
    // happened until the icon says otherwise.
    appThemeMode.addListener(_onThemeModeChanged);
    // The syntax line under the search box comes and goes with the focus, so the page has to
    // hear about it.
    _searchFocus.addListener(_onSearchFocusChanged);
    unawaited(_loadAccent());
    unawaited(_loadSettings());
    unawaited(_refresh());
  }

  @override
  void dispose() {
    appThemeMode.removeListener(_onThemeModeChanged);
    _searchFocus.removeListener(_onSearchFocusChanged);
    _folderDebounce?.cancel();
    unawaited(_watch?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onThemeModeChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  /// Picks up what the last visit left behind.
  ///
  /// The page is built with the list open and folds a moment later if that is how it was left:
  /// reading a file is asynchronous, and blocking the first frame on it would show the user a
  /// blank window for no good reason.
  Future<void> _loadSettings() async {
    final NotesSettings settings = await appSettings.load();
    if (!mounted) return;
    // The theme lives in a notifier the root MaterialApp listens to, so it is set before the
    // page's own state: the window should not repaint twice for one setting.
    final ThemeMode mode = themeModeFromName(settings.themeMode);
    if (appThemeMode.value != mode) appThemeMode.value = mode;
    if (settings.sidebarCollapsed == _sidebarCollapsed) return;
    setState(() => _sidebarCollapsed = settings.sidebarCollapsed);
  }

  /// Folds the note list away, or brings it back, and remembers which.
  ///
  /// The write is best-effort - see `NotesSettingsStore` - so a failure to remember this never
  /// stands between the user and the list.
  void _toggleSidebar() {
    setState(() => _sidebarCollapsed = !_sidebarCollapsed);
    unawaited(
      appSettings.save(
        appSettings.value.copyWith(sidebarCollapsed: _sidebarCollapsed),
      ),
    );
  }

  /// Steps through follow-the-system, light, dark, and round again.
  ///
  /// A cycle rather than a two-way switch because "follow Windows" is where the app starts and
  /// there would otherwise be no way back to it: Windows' own theme setting is the one most
  /// people change, and an app that has silently stopped listening to it is a bug report
  /// waiting to happen. The tooltip names what the next press does.
  void _cycleTheme() {
    final ThemeMode next = switch (appThemeMode.value) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    appThemeMode.value = next;
    unawaited(
      appSettings.save(
        appSettings.value.copyWith(themeMode: themeModeName(next)),
      ),
    );
  }

  /// The window is going away: put the last keystrokes on disk before it does.
  ///
  /// `dispose()` cannot await, and on Windows the window close arrives as a request the app can
  /// still answer, so this is the moment to write. Every open note, not just the one on screen:
  /// the others are hidden, not closed, and their last keystrokes are just as real.
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await _flushAllTabs();
    return AppExitResponse.exit;
  }

  /// Writes every open note that has something pending.
  Future<void> _flushAllTabs() async {
    for (final GlobalKey<EditorPaneState> key in _paneKeys.values) {
      await key.currentState?.flush();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Losing the foreground is the last moment before the process could be killed.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_flushAllTabs());
      return;
    }
    // Coming back to the window is the moment to re-read the folder. A watch can have ended
    // while the app was in the background, and this is the cheap way to find out and to catch
    // up on anything that happened meanwhile.
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshAndRecheck());
    }
  }

  /// Re-reads the folder and re-arms the watch, then looks at the open note.
  Future<void> _refreshAndRecheck() async {
    await _refresh();
    await _checkOpenNote();
  }

  Future<void> _loadAccent() async {
    if (widget.accent != null) return;
    final SystemAccent accent = await SystemAccent.read();
    if (!mounted) return;
    setState(() => _accent = accent);
  }

  Future<void> _refresh() async {
    try {
      await _store.ensureDirectoryExists();
      final List<Note> notes = await _store.listNotes();
      final List<Note> conflicts = await _store.listConflictCopies();
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _conflicts = conflicts;
        _loading = false;
        _error = null;
        // A note that is open can have gone: deleted here, renamed by Syncthing, or moved away.
        // Its tab goes with it - an editor left open over a file that is no longer there is an
        // editor that would write it back.
        _tabs = _tabs.retainOnly(notes.map((Note n) => n.file));
        _prunePaneKeys();
      });
      // Watched from here rather than from `initState` because the folder has to exist before
      // it can be watched, and this is the one place that guarantees it does.
      if (_watch == null) _watchFolder();
      // A note Syncthing just changed has to be re-read before the search can be trusted again.
      unawaited(_loadBodies());
    } on FileSystemException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notes = <Note>[];
        _error = NotesStrings.errorOpeningFolder(
          error.osError?.message ?? error.message,
        );
      });
    }
  }

  /// Starts watching the notes folder, once.
  ///
  /// The folder is shared with the phone through Syncthing, which writes into it with no
  /// involvement from this app at all. Without a watch, a note the phone has just written stays
  /// invisible here until the app is restarted - and a note the phone has just *changed* stays
  /// invisible while it is open, which is how one machine's work gets overwritten by the
  /// other's.
  ///
  /// `Directory.watch` is `dart:io`, so this costs no dependency: on Windows it is
  /// `ReadDirectoryChangesW` underneath.
  void _watchFolder() {
    try {
      _watch = _store.directory.watch().listen(
        (FileSystemEvent _) => _folderChanged(),
        onError: (Object _) {
          // A watch can end on its own - a drive unmounting, Syncthing replacing the folder
          // while it scans. Dropping the subscription puts the app back where it was before
          // there was one; the next refresh (opening a note, renaming one, coming back to the
          // window) arms it again.
          _watch?.cancel();
          _watch = null;
        },
        cancelOnError: true,
      );
    } on FileSystemException {
      // No watch. Everything else still works.
      _watch = null;
    }
  }

  /// One filesystem event, or a burst of them.
  ///
  /// Syncthing writes a temporary file, renames it, and touches the folder more than once per
  /// note; a scan over ten notes can produce a hundred events inside a second. The delay is
  /// what turns that into a single refresh, and it is also long enough for a file that is still
  /// being written to have finished being written.
  void _folderChanged() {
    _folderDebounce?.cancel();
    _folderDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_refresh());
      unawaited(_checkOpenNote());
    });
  }

  /// Asks every open note whether the file underneath it has changed.
  ///
  /// All of them, not just the one on screen: a hidden tab is still an editor holding text that
  /// a save could put over somebody else's. Each editor decides what to do about the answer -
  /// nothing, quietly take the file's version because nothing there was unsaved, or stop saving
  /// and put the question to the user.
  Future<void> _checkOpenNote() async {
    bool reloaded = false;
    for (final GlobalKey<EditorPaneState> key in _paneKeys.values) {
      final EditorPaneState? pane = key.currentState;
      if (pane == null) continue;
      if (await pane.applyExternalChange() == ExternalChange.reloaded) {
        reloaded = true;
      }
    }
    if (!mounted || !reloaded) return;
    _toast(NotesStrings.externalChangeReloaded);
  }

  Future<void> _newNote() async {
    try {
      final File file = await _store.createNote();
      await _refresh();
      if (!mounted) return;
      final Note created = _notes.firstWhere(
        (Note n) => n.file.path == file.path,
        orElse: () => Note(file: file, modified: DateTime.now(), preview: ''),
      );
      _openNote(created);
    } on FileSystemException catch (error) {
      _toast(NotesStrings.createFailed(
        error.osError?.message ?? error.message,
      ));
    }
  }

  /// Opens a note, or brings its tab forward when it is already open.
  ///
  /// Nothing is flushed on the way: the note being left behind keeps its editor mounted, so
  /// there is no moment where its text exists only in a widget that is about to be destroyed.
  /// Its own autosave is what puts it on disk, exactly as if it were still on screen.
  void _openNote(Note note) {
    _setTabs(_tabs.open(note.file));
    _scrollTabIntoView();
  }

  /// Closes the tab at [index], writing it first.
  ///
  /// The await matters here in a way it does not when switching: closing really does destroy
  /// the editor, and `dispose()` cannot wait for a write.
  Future<void> _closeTab(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    await _paneKeys[_tabs.files[index].path]?.currentState?.flush();
    if (!mounted) return;
    _setTabs(_tabs.close(index));
  }

  /// Closes whichever tab is on screen.
  ///
  /// The shortcut binding needs a plain `void` callback, which this is; [_closeTab] is the one
  /// that awaits, and the write it waits for cannot be awaited from a key handler.
  void _closeCurrentTabNow() => unawaited(_closeCurrentTab());

  /// Closes whichever tab is on screen.
  Future<void> _closeCurrentTab() => _closeTab(_tabs.currentIndex);

  /// Replaces the tab set, and drops the editors of any tab that has gone.
  void _setTabs(NoteTabs next) {
    if (next == _tabs) return;
    setState(() {
      _tabs = next;
      _prunePaneKeys();
    });
  }

  void _prunePaneKeys() {
    final Set<String> live = _tabs.files.map((File f) => f.path).toSet();
    _paneKeys.removeWhere(
      (String path, GlobalKey<EditorPaneState> _) => !live.contains(path),
    );
  }

  GlobalKey<EditorPaneState> _paneKeyFor(File file) => _paneKeys.putIfAbsent(
        file.path,
        () => GlobalKey<EditorPaneState>(),
      );

  /// The note behind a tab, for the date shown under its title.
  Note _noteFor(File file) => _notes.firstWhere(
        (Note n) => n.file.path == file.path,
        orElse: () => Note(file: file, modified: DateTime.now(), preview: ''),
      );

  void _toast(String message) {
    if (!mounted) return;
    final NotesDesktopPalette p = _paletteFor(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        // Styled from the desktop palette rather than left to Material's defaults: those draw a
        // full-width light bar across the bottom of a dark window, which was the one thing on
        // screen that belonged to neither theme.
        SnackBar(
          content: Text(
            message,
            style: TextStyle(fontSize: 13, color: p.ink),
          ),
          behavior: SnackBarBehavior.floating,
          width: 340,
          elevation: 0,
          backgroundColor: p.hover,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(NotesDesktopMetrics.radiusControl),
          ),
        ),
      );
  }

  /// The notes the search found, with the line each one was found on.
  ///
  /// A bare word is looked for in the title *and* in every line of the body, which is the whole
  /// difference from what this used to do: it could only see the note's first line, so a word
  /// further down was invisible. See `note_search.dart` for the little bit of syntax on top.
  ///
  /// Recomputed on every build rather than cached. It is a substring scan over the notes in
  /// memory, and the alternative - a cache with its own invalidation rules - is more places for
  /// the list to disagree with what is on disk.
  List<_Hit> get _hits {
    if (_parsed.isEmpty) {
      return _notes
          .map((Note n) => _Hit(n, null))
          .toList(growable: false);
    }
    // Before the bodies have been read - and for a query that only asks about dates - the
    // note's first line is all there is to go on. It is a moment, not a state: the read is
    // started the instant a query arrives.
    final bool canSearchBody = _parsed.looksAtText;
    final List<_Hit> found = <_Hit>[];
    for (final Note note in _notes) {
      final String body = canSearchBody
          ? (_bodies[note.file.path] ?? note.preview)
          : '';
      final NoteMatch? match = _parsed.match(
        title: note.title,
        body: body,
        modified: note.modified,
      );
      if (match != null) found.add(_Hit(note, match.snippet));
    }
    return found;
  }

  /// Reads the notes' bodies, when the search is going to need them.
  ///
  /// Only then: the list itself never needs a note's text - a row shows its first line, and the
  /// editor reads the file for itself. The stamp is the notes' own paths and times, so a note
  /// that changed on disk - this app, another editor, Syncthing - is read again.
  Future<void> _loadBodies() async {
    if (_bodiesLoading || !_parsed.looksAtText) return;
    final String stamp = _stampOf(_notes);
    if (stamp == _bodiesStamp && _bodies.length == _notes.length) return;

    _bodiesLoading = true;
    final Map<String, String> read = <String, String>{};
    for (final Note note in _notes) {
      try {
        read[note.file.path] = await _store.read(note.file);
      } on FileSystemException {
        // Gone, or not readable. It simply will not be found by a body search.
        read[note.file.path] = '';
      }
    }
    if (!mounted) return;
    setState(() {
      _bodies = read;
      _bodiesStamp = stamp;
      _bodiesLoading = false;
    });
  }

  static String _stampOf(List<Note> notes) => notes
      .map((Note n) => '${n.file.path}|${n.modified.microsecondsSinceEpoch}')
      .join('\n');

  /// The search box changed: parse it, and make sure the bodies are there to search.
  void _onQueryChanged(String value) {
    setState(() => _parsed = NoteQuery.parse(value));
    unawaited(_loadBodies());
  }

  @override
  Widget build(BuildContext context) {
    final NotesDesktopPalette p = _paletteFor(context);
    final Brightness brightness = Theme.of(context).brightness;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        // The shortcut the panel toggle has everywhere else. It fires from anywhere on the
        // page, including while a note is being typed into: the key events bubble up from
        // whatever holds the focus.
        const SingleActivator(LogicalKeyboardKey.keyB, control: true):
            _toggleSidebar,
        // Closing the note being read, exactly as a browser closes its tab. Nothing is deleted:
        // the file is written and the tab goes away.
        const SingleActivator(LogicalKeyboardKey.keyW, control: true):
            _closeCurrentTabNow,
      },
      child: Focus(
        // Without something holding the focus the page never sees a key at all.
        autofocus: true,
        child: Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: p.accent,
          brightness: brightness,
        ).copyWith(surface: p.surface, primary: p.accent),
        // The Latin face is what the app already used; naming it and the Chinese faces keeps
        // the first as it was and takes the second out of the engine's hands. See
        // [NotesDesktopType].
        textTheme: Theme.of(context).textTheme.apply(
              fontFamily: NotesDesktopType.fontFamily,
              fontFamilyFallback: NotesDesktopType.fontFamilyFallback,
            ),
        // The band behind selected text has to be said here, and said again rather than left to
        // Material. `TextField` has no `selectionColor` of its own, and Material resolves the
        // colour from the *app's* scheme - the phone's amber - into `textSelectionTheme` when
        // the `ThemeData` is built, which `copyWith(colorScheme: …)` above cannot undo. The
        // result was a gold band under a blue caret. Measured before the fix: `#785C1C`, which
        // is `#FFB814` at 40% over this surface.
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: p.accent,
          selectionColor: p.selection,
          selectionHandleColor: p.accent,
        ),
      ),
      child: Scaffold(
        backgroundColor: p.page,
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            // One width for both the band's head and the sidebar itself: they are two rows of
            // the same column, and the seam between them has to fall in the same place.
            final double sidebar = _sidebarCollapsed
                ? 0
                : _sidebarWidthFor(constraints.maxWidth);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _band(p, sidebar),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _collapsibleSidebar(p, sidebar),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            // About the folder, not about the note on screen, so it goes above
                            // whichever of the two the editor area is showing.
                            if (_showsConflictNotice) _conflictStrip(p),
                            Expanded(child: _editorArea(p)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        ),
      ),
      ),
    );
  }

  /// The palette for whatever brightness is in force.
  ///
  /// Built fresh on every call rather than cached: the theme can change under it at any moment,
  /// and the dialogs and menus raised from callbacks outside `build` need the same one the page
  /// is drawn with.
  NotesDesktopPalette _paletteFor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? NotesDesktopPalette.dark(_accent)
        : NotesDesktopPalette.light(_accent);
  }

  /// The sidebar's width in a window this wide.
  ///
  /// Normally the width the user dragged it to. In a narrow window the sidebar gives way
  /// before the note pane does, because a pane narrower than
  /// [NotesDesktopMetrics.paneMin] cannot hold the status line's own file path.
  double _sidebarWidthFor(double total) {
    final double wanted = _sidebarWidth.clamp(
      NotesDesktopMetrics.sidebarMin,
      NotesDesktopMetrics.sidebarMax,
    );
    final double room =
        total - NotesDesktopMetrics.sidebarHandle - NotesDesktopMetrics.paneMin;
    if (room >= wanted) return wanted;
    return room < NotesDesktopMetrics.sidebarMin
        ? NotesDesktopMetrics.sidebarMin
        : room;
  }

  // --- the top band --------------------------------------------------------

  Widget _band(NotesDesktopPalette p, double sidebar) {
    return SizedBox(
      height: NotesDesktopMetrics.band,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            // Folded away, the band keeps a rail: a button that hides itself cannot be pressed
            // again.
            width: _sidebarCollapsed ? NotesDesktopMetrics.sidebarRail : sidebar,
            child: _sidebarHead(p),
          ),
          Expanded(child: _tabStrip(p)),
          _windowButtons(p),
        ],
      ),
    );
  }

  /// The band's left-hand part: the one button that folds the note list away, and back.
  ///
  /// The title and the new-note button used to live up here. They now start the list instead,
  /// under the line the band ends at.
  Widget _sidebarHead(NotesDesktopPalette p) {
    return ColoredBox(
      color: p.page,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 6),
          _BandButton(
            palette: p,
            icon: _sidebarCollapsed ? Icons.menu : Icons.menu_open,
            tooltip: _sidebarCollapsed
                ? NotesStrings.desktopSidebarExpand
                : NotesStrings.desktopSidebarCollapse,
            onPressed: _toggleSidebar,
          ),
          _BandButton(
            palette: p,
            icon: switch (appThemeMode.value) {
              ThemeMode.light => Icons.light_mode,
              ThemeMode.dark => Icons.dark_mode,
              ThemeMode.system => Icons.brightness_auto,
            },
            tooltip: switch (appThemeMode.value) {
              ThemeMode.light => NotesStrings.desktopThemeToDark,
              ThemeMode.dark => NotesStrings.desktopThemeToSystem,
              ThemeMode.system => NotesStrings.desktopThemeToLight,
            },
            // The icon has to follow the notifier, not the page's own state. The page does
            // rebuild whenever the *effective* theme changes, but picking "dark" while Windows
            // is already dark changes nothing on screen, and the button would keep saying
            // "follow the system".
            onPressed: _cycleTheme,
          ),
        ],
      ),
    );
  }

  /// The note list and the handle that widens it, folded away as one piece.
  ///
  /// The width is animated but the contents are not: the list keeps the width it was laid out
  /// at and is clipped on the way in and out. Squeezing it instead would rebuild every row at
  /// every frame of the animation, and overflow while it did.
  Widget _collapsibleSidebar(NotesDesktopPalette p, double sidebar) {
    const double handle = NotesDesktopMetrics.sidebarHandle;
    final double natural = sidebar + handle;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      width: _sidebarCollapsed ? 0 : natural,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: natural,
          maxWidth: natural,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(width: sidebar, child: _sidebar(p)),
              _resizeHandle(p),
            ],
          ),
        ),
      ),
    );
  }

  /// The strip the tabs sit on, and the app's drag handle.
  ///
  /// The empty part of the strip is what moves the window: pressing it hands the window to the
  /// OS for a caption drag, which is also what keeps Aero snap and double-click-to-maximise
  /// working without reimplementing either.
  ///
  /// Tabs narrow as more of them are opened, and past [NotesDesktopMetrics.tabMinWidth] the
  /// strip scrolls instead. Scrolling is driven by the wheel rather than by dragging, and the
  /// tabs are a plain [Row] rather than a `ScrollView` on purpose: a scroll view laid over the
  /// strip would claim the drags that belong to the window, and the strip is the only place the
  /// window can be dragged from.
  Widget _tabStrip(NotesDesktopPalette p) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Kept for the scrolling decisions, which are made outside a layout pass.
        _tabStripWidth = constraints.maxWidth;
        final double tabWidth = _tabWidthFor(constraints.maxWidth);
        const double gap = _tabGap;
        final double content = _tabs.isEmpty
            ? 0
            : _tabs.length * tabWidth + (_tabs.length - 1) * gap;
        final double furthest =
            math.max(0, content + NotesDesktopMetrics.newTabWidth - constraints.maxWidth);
        final double scroll = _tabScroll.clamp(0, furthest);

        return Listener(
          onPointerSignal: (PointerSignalEvent event) {
            if (event is! PointerScrollEvent || furthest <= 0) return;
            setState(() {
              _tabScroll = (scroll + event.scrollDelta.dy).clamp(0, furthest);
            });
          },
          child: ClipRect(
            child: ColoredBox(
              color: p.frame,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanDown: (DragDownDetails _) =>
                          unawaited(NotesWindow.startDrag()),
                      onDoubleTap: () =>
                          unawaited(NotesWindow.toggleMaximize()),
                    ),
                  ),
                  Positioned(
                    left: -scroll,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      children: <Widget>[
                        for (int i = 0; i < _tabs.length; i++) ...<Widget>[
                          if (i > 0) const SizedBox(width: gap),
                          _Tab(
                            width: tabWidth,
                            title: Note.fileNameWithoutExtension(_tabs.files[i]),
                            palette: p,
                            selected: i == _tabs.currentIndex,
                            dirty: _paneKeys[_tabs.files[i].path]
                                    ?.currentState
                                    ?.isDirty ??
                                false,
                            onSelect: () => _setTabs(_tabs.select(i)),
                            onClose: () => unawaited(_closeTab(i)),
                          ),
                        ],
                        // Follows the last tab, and scrolls with them: the strip is one row, and
                        // a "+" pinned to the far edge would look like it belonged to the window
                        // buttons rather than to the tabs.
                        _NewTabButton(
                          palette: p,
                          onPressed: () => unawaited(_newNote()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// How wide each tab is drawn.
  ///
  /// The design's [NotesDesktopMetrics.tabWidth] while they all fit, then narrower as more
  /// notes are opened, and never below [NotesDesktopMetrics.tabMinWidth]: a tab too narrow to
  /// show any of its own title is not a tab, it is a coloured sliver. Past that point the strip
  /// scrolls.
  double _tabWidthFor(double available) {
    if (_tabs.isEmpty || available <= 0) return NotesDesktopMetrics.tabWidth;
    // The "+" keeps its room even when the tabs no longer fit: it is how a note gets written in
    // a strip that has run out of space, so it must never be the thing that gets squeezed out.
    final double room = available - NotesDesktopMetrics.newTabWidth;
    if (room <= 0) return NotesDesktopMetrics.tabMinWidth;
    final double fit = (room - _tabGap * (_tabs.length - 1)) / _tabs.length;
    return fit.clamp(NotesDesktopMetrics.tabMinWidth, NotesDesktopMetrics.tabWidth);
  }

  /// Scrolls the strip so the current tab is on screen.
  ///
  /// Needed whenever the current tab changes without a click on the strip itself - opening a
  /// note from the list, closing one, Ctrl+W - because those can select a tab that is scrolled
  /// out of sight, and a current tab nobody can see is a tab nobody can close.
  void _scrollTabIntoView() {
    if (_tabStripWidth <= 0) return;
    final double tabWidth = _tabWidthFor(_tabStripWidth);
    final double left = _tabs.currentIndex * (tabWidth + _tabGap);
    double scroll = _tabScroll;
    if (left < scroll) {
      scroll = left;
    } else if (left + tabWidth > scroll + _tabStripWidth) {
      scroll = left + tabWidth - _tabStripWidth;
    }
    if (scroll == _tabScroll) return;
    // Called from the middle of a tap handler or a key handler, both of which can be inside a
    // build already.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _tabScroll = math.max(0, scroll));
    });
  }

  Widget _windowButtons(NotesDesktopPalette p) {
    return ValueListenableBuilder<bool>(
      valueListenable: NotesWindow.maximized,
      builder: (BuildContext context, bool maximized, Widget? _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _WindowButton(
              palette: p,
              kind: _WindowButtonKind.minimize,
              tooltip: NotesStrings.windowMinimize,
              onPressed: () => unawaited(NotesWindow.minimize()),
            ),
            _WindowButton(
              palette: p,
              kind: maximized
                  ? _WindowButtonKind.restore
                  : _WindowButtonKind.maximize,
              tooltip: maximized
                  ? NotesStrings.windowRestore
                  : NotesStrings.windowMaximize,
              onPressed: () => unawaited(NotesWindow.toggleMaximize()),
            ),
            _WindowButton(
              palette: p,
              kind: _WindowButtonKind.close,
              tooltip: NotesStrings.windowClose,
              onPressed: () => unawaited(NotesWindow.close()),
            ),
          ],
        );
      },
    );
  }

  // --- the sidebar ---------------------------------------------------------

  Widget _sidebar(NotesDesktopPalette p) {
    final List<_Hit> hits = _hits;
    final List<Object> rows = _sidebarRows(hits);
    return ColoredBox(
      color: p.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The title and its button head the list. They sit below the line the band ends at,
          // so neither of them is part of the window's chrome any more.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              22,
              NotesDesktopMetrics.sidebarTitleTop,
              18,
              0,
            ),
            child: Row(
              children: <Widget>[
                Text(
                  NotesStrings.listTitle,
                  style: TextStyle(
                    fontSize: NotesDesktopMetrics.sidebarTitleSize,
                    // Exactly the font size tall, so the row's height is the button's.
                    height: 1.0,
                    fontWeight: NotesDesktopType.strong,
                    color: p.ink,
                  ),
                ),
                const Spacer(),
                _FlatButton(
                  palette: p,
                  onPressed: () => unawaited(_newNote()),
                  icon: Icons.add,
                  label: NotesStrings.desktopNewNote,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
            child: _SearchField(
              palette: p,
              controller: _search,
              focusNode: _searchFocus,
              onChanged: _onQueryChanged,
            ),
          ),
          // The syntax only while the box has the caret. It is what makes the operators
          // findable at all, and it stays out of the way the rest of the time.
          if (_searchFocus.hasFocus)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
              child: Text(
                NotesStrings.desktopSearchSyntax,
                style: TextStyle(fontSize: 11, color: p.faint),
              ),
            ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: rows.length,
              itemBuilder: (BuildContext context, int index) {
                final Object entry = rows[index];
                if (entry is _SectionHeading) {
                  return _sectionLabel(p, entry.text, top: entry.topGap);
                }
                final _Hit hit = entry as _Hit;
                final Note note = hit.note;
                return _NoteRow(
                  note: note,
                  // What the search found, when it found it somewhere other than the title.
                  snippet: hit.snippet,
                  palette: p,
                  pinned: appSettings.isPinned(note.title),
                  // The row marks the note being edited, not every note that happens to be
                  // open: the open ones are what the tab strip is for.
                  selected: _tabs.current?.path == note.file.path,
                  onTap: () => _openNote(note),
                  onContextMenu: (Offset at) =>
                      unawaited(_showNoteMenu(note, at)),
                  onTogglePin: () => unawaited(_togglePin(note)),
                );
              },
            ),
          ),
          if (hits.isEmpty && !_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _parsed.isEmpty
                        ? NotesStrings.emptyTitle
                        : NotesStrings.searchEmptyTitle,
                    style: TextStyle(fontSize: 13, color: p.faint),
                  ),
                  if (!_parsed.isEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      NotesStrings.searchEmptyDetail,
                      style: TextStyle(fontSize: 12, color: p.faint),
                    ),
                  ],
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 12),
            child: Text(
              NotesStrings.desktopNoteTotal(_notes.length),
              style: TextStyle(fontSize: 12, color: p.faint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(NotesDesktopPalette p, String label, {double top = 0}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(22, top, 22, 8),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: p.faint),
      ),
    );
  }

  /// The sidebar's rows in order: a heading, then the notes under it.
  ///
  /// Two sections as soon as anything is pinned - the pinned notes, then the rest - and the
  /// design's single "全部笔记" when nothing is. A pinned note is listed **only** under
  /// "已置顶": showing it twice would make the list longer without telling the user anything
  /// they did not already know, and the note they were reading would appear to have moved.
  ///
  /// The search narrows both sections rather than flattening them, so pinning keeps meaning the
  /// same thing while a search is on.
  List<Object> _sidebarRows(List<_Hit> hits) {
    final List<_Hit> pinned = <_Hit>[];
    final List<_Hit> rest = <_Hit>[];
    for (final _Hit hit in hits) {
      (appSettings.isPinned(hit.note.title) ? pinned : rest).add(hit);
    }
    return <Object>[
      if (pinned.isNotEmpty) ...<Object>[
        const _SectionHeading(NotesStrings.desktopPinnedSection),
        ...pinned,
      ],
      // The gap only shows when a section was drawn above it; the first heading is already
      // spaced by the search field's own margin.
      _SectionHeading(
        NotesStrings.desktopNoteCountSection,
        topGap: pinned.isEmpty ? 0 : 16,
      ),
      ...rest,
    ];
  }

  /// Drag to make the sidebar wider or narrower.
  Widget _resizeHandle(NotesDesktopPalette p) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (DragUpdateDetails details) {
          setState(() {
            _sidebarWidth = (_sidebarWidth + details.delta.dx).clamp(
              NotesDesktopMetrics.sidebarMin,
              NotesDesktopMetrics.sidebarMax,
            );
          });
        },
        child: SizedBox(width: NotesDesktopMetrics.sidebarHandle),
      ),
    );
  }

  // --- the editor ----------------------------------------------------------

  Widget _editorArea(NotesDesktopPalette p) {
    if (_error != null) {
      return _CenteredMessage(
        palette: p,
        icon: Icons.folder_off_outlined,
        title: NotesStrings.errorTitle,
        detail: NotesStrings.errorFolder(_error!, _store.directory.path),
      );
    }
    if (_tabs.isEmpty) {
      return _CenteredMessage(
        palette: p,
        icon: Icons.article_outlined,
        title: NotesStrings.nothingOpenTitle,
        detail: NotesStrings.nothingOpenDetail,
      );
    }
    // Every open note keeps its editor mounted; the stack decides which one is painted. That is
    // what makes switching tabs free - the text, the caret, the scroll position and the undo
    // history of the note being left are all still there when it is switched back to, which is
    // the whole point of having tabs rather than reopening the note.
    return IndexedStack(
      index: _tabs.currentIndex,
      sizing: StackFit.expand,
      children: <Widget>[
        for (final File file in _tabs.files)
          EditorPane(
            key: _paneKeyFor(file),
            store: _store,
            file: file,
            modified: _noteFor(file).modified,
            palette: p,
            onRenamed: (File renamed) => _afterRename(file, renamed),
            // Any change to what is unsaved redraws the strip: the dot on the tab is the only
            // sign the user gets that this note has something still to write.
            onDirtyChanged: (bool _) => setState(() {}),
          ),
      ],
    );
  }

  /// Follows a rename through the tab set and the note list.
  ///
  /// The tab has to be moved to the new path before anything refreshes, or the refresh would
  /// decide the note it is holding has been deleted and close the editor the user is typing in.
  Future<void> _afterRename(File from, File to) async {
    _setTabs(_tabs.replace(from, to));
    // A pin is kept by title, so a rename would otherwise silently drop it - and the note the
    // user deliberately put at the top would slide back down the list for no visible reason.
    await appSettings.renamePinned(
      Note.fileNameWithoutExtension(from),
      Note.fileNameWithoutExtension(to),
    );
    await _refresh();
  }

  // --- what the note list's right-click menu does --------------------------

  /// Pins [note], or takes the pin off it.
  Future<void> _togglePin(Note note) async {
    final bool wasPinned = appSettings.isPinned(note.title);
    await appSettings.togglePinned(note.title);
    if (!mounted) return;
    setState(() {});
    _toast(wasPinned
        ? NotesStrings.desktopUnpinnedNote(note.title)
        : NotesStrings.desktopPinnedNote(note.title));
  }

  /// Asks, then moves [note] to the Windows Recycle Bin.
  ///
  /// The tab goes first and is awaited. Closing it is what writes any unsaved text, and a
  /// delete that ran ahead of that write would see the file come straight back a moment later.
  Future<void> _confirmDelete(Note note) async {
    final NotesDesktopPalette p = _paletteFor(context);
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: p.surface,
        title: Text(
          NotesStrings.confirmDeleteOne,
          style: TextStyle(fontSize: 16, color: p.ink),
        ),
        content: Text(
          NotesStrings.desktopDeleteDetail(note.title),
          style: TextStyle(fontSize: 13, color: p.sub),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              NotesStrings.cancel,
              style: TextStyle(color: p.sub),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              NotesStrings.delete,
              style: TextStyle(color: p.accent),
            ),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    final int open = _tabs.indexOf(note.file);
    if (open >= 0) await _closeTab(open);
    if (!mounted) return;

    final String? failure = await deleteToRecycleBin(note.file);
    if (!mounted) return;
    if (failure != null) {
      _toast(NotesStrings.desktopDeleteFailed(failure));
      return;
    }
    await _refresh();
    if (!mounted) return;
    _toast(NotesStrings.desktopDeletedOne(note.title));
  }

  /// Opens the folder with [note]'s file already selected.
  ///
  /// `explorer` is started rather than run: it hands the request to the desktop process that is
  /// already there and exits with a non-zero code even when it worked, so there is no exit code
  /// worth waiting for. The comma belongs to the switch - it is one argument, not two.
  Future<void> _revealInExplorer(Note note) async {
    try {
      await Process.start(
        'explorer.exe',
        <String>['/select,${note.file.path}'],
        mode: ProcessStartMode.detached,
      );
    } on ProcessException {
      if (mounted) _toast(NotesStrings.desktopRevealFailed);
    }
  }

  Future<void> _copyPath(Note note) async {
    await Clipboard.setData(ClipboardData(text: note.file.path));
    if (mounted) _toast(NotesStrings.desktopPathCopied);
  }

  /// Opens [note] and puts the caret in its title, ready to be typed over.
  ///
  /// A frame has to go by first: the pane for a note that was not already open does not exist
  /// until the build that opening it triggers.
  void _renameNote(Note note) {
    _openNote(note);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _paneKeys[note.file.path]?.currentState?.startRename();
    });
  }

  /// The note list's context menu.
  ///
  /// "重命名" does not open a dialog: the title *is* the file name and the editor already edits
  /// it, so this only puts the caret there. A second field asking for a name would be a second
  /// answer to the same question.
  Future<void> _showNoteMenu(Note note, Offset at) async {
    final NotesDesktopPalette p = _paletteFor(context);
    final bool pinned = appSettings.isPinned(note.title);
    const String open = 'open';
    const String rename = 'rename';
    const String reveal = 'reveal';
    const String copy = 'copy';
    const String pin = 'pin';
    const String remove = 'remove';

    final String? choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NotesDesktopMetrics.radiusControl),
      ),
      items: <PopupMenuEntry<String>>[
        _menuItem(p, open, Icons.article_outlined, NotesStrings.desktopMenuOpen),
        _menuItem(p, rename, Icons.drive_file_rename_outline,
            NotesStrings.desktopMenuRename),
        const PopupMenuDivider(),
        _menuItem(p, reveal, Icons.folder_open,
            NotesStrings.desktopMenuReveal),
        _menuItem(p, copy, Icons.content_copy, NotesStrings.desktopMenuCopyPath),
        const PopupMenuDivider(),
        _menuItem(
          p,
          pin,
          pinned ? Icons.push_pin : Icons.push_pin_outlined,
          pinned ? NotesStrings.desktopMenuUnpin : NotesStrings.desktopMenuPin,
        ),
        const PopupMenuDivider(),
        _menuItem(p, remove, Icons.delete_outline, NotesStrings.delete),
      ],
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case open:
        _openNote(note);
      case rename:
        _renameNote(note);
      case reveal:
        await _revealInExplorer(note);
      case copy:
        await _copyPath(note);
      case pin:
        await _togglePin(note);
      case remove:
        await _confirmDelete(note);
    }
  }

  PopupMenuItem<String> _menuItem(
    NotesDesktopPalette p,
    String value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<String>(
      value: value,
      height: 34,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 15, color: p.sub),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13, color: p.ink)),
        ],
      ),
    );
  }

  // --- conflict copies ------------------------------------------------------

  /// Whether the strip should still be telling the user about conflict copies.
  ///
  /// A copy whose notice was put away is not announced again, but a *new* copy always is: its
  /// name carries the moment Syncthing made it, so it can never be one that was dismissed
  /// (see `settings.dart`). The copies themselves are never touched by any of this.
  bool get _showsConflictNotice => _conflicts.any(
        (Note copy) =>
            !appSettings.isConflictDismissed(copy.file.uri.pathSegments.last),
      );

  Future<void> _dismissConflictNotice() async {
    for (final Note copy in _conflicts) {
      await appSettings.dismissConflict(copy.file.uri.pathSegments.last);
    }
    if (mounted) setState(() {});
  }

  /// The strip above the editor area.
  ///
  /// It belongs to the folder rather than to the note on screen, so it sits above whichever of
  /// the two the editor area is showing, and it never blocks anything.
  Widget _conflictStrip(NotesDesktopPalette p) {
    return Container(
      color: p.hover,
      padding: const EdgeInsets.fromLTRB(26, 10, 18, 10),
      child: Row(
        children: <Widget>[
          Icon(Icons.call_split, size: 17, color: p.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              NotesStrings.conflictsFound(_conflicts.length),
              style: TextStyle(
                fontSize: 13,
                fontWeight: NotesDesktopType.emphasis,
                color: p.ink,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _StripButton(
            palette: p,
            label: NotesStrings.desktopConflictsView,
            onPressed: () => unawaited(_showConflicts()),
          ),
          const SizedBox(width: 8),
          _StripButton(
            palette: p,
            label: NotesStrings.desktopConflictsDismiss,
            onPressed: () => unawaited(_dismissConflictNotice()),
          ),
        ],
      ),
    );
  }

  /// Lists the copies, and says which note each one came from.
  ///
  /// A dialog rather than a page of its own: a copy can be read in the app, but the point of
  /// the list is to send the user to the file, and the desktop already has somewhere better
  /// than a reader for that - Explorer, and whatever editor they like. There is deliberately no
  /// delete here: a copy may hold the only version of what was typed on the phone, so removing
  /// one stays a decision made with the file in front of them.
  Future<void> _showConflicts() async {
    final NotesDesktopPalette p = _paletteFor(context);
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: p.surface,
        title: Text(
          NotesStrings.conflicts,
          style: TextStyle(fontSize: 16, color: p.ink),
        ),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                NotesStrings.conflictsExplain,
                style: TextStyle(fontSize: 12, color: p.sub, height: 1.5),
              ),
              const SizedBox(height: 14),
              if (_conflicts.isEmpty)
                Text(
                  NotesStrings.conflictNone,
                  style: TextStyle(fontSize: 13, color: p.faint),
                )
              else
                for (final Note copy in _conflicts)
                  _ConflictRow(
                    palette: p,
                    note: copy,
                    onReveal: () => unawaited(_revealInExplorer(copy)),
                  ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              NotesStrings.desktopConflictsClose,
              style: TextStyle(color: p.accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// One conflict copy in the dialog: which note it belongs to, and where the file is.
class _ConflictRow extends StatelessWidget {
  const _ConflictRow({
    required this.palette,
    required this.note,
    required this.onReveal,
  });

  final NotesDesktopPalette palette;
  final Note note;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final NotesDesktopPalette p = palette;
    final String fileName = note.file.uri.pathSegments.last;
    final String owner = SyncConflict.originalTitle(fileName);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  owner.isEmpty
                      ? NotesStrings.desktopConflictNoOwner
                      : NotesStrings.desktopConflictBelongsTo(owner),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: NotesDesktopType.emphasis,
                    color: p.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  fileName,
                  style: TextStyle(fontSize: 11, color: p.faint),
                ),
                const SizedBox(height: 2),
                Text(
                  formatNoteDate(note.modified),
                  style: TextStyle(fontSize: 11, color: p.faint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _StripButton(
            palette: p,
            label: NotesStrings.desktopMenuReveal,
            onPressed: onReveal,
          ),
        ],
      ),
    );
  }
}

/// A small button for the strips and dialogs the page raises.
///
/// Local to this file: it sits on a filled strip or on a dialog's surface rather than on the
/// page colour, so its hover has to be a step away from that rather than the usual one.
class _StripButton extends StatefulWidget {
  const _StripButton({
    required this.palette,
    required this.label,
    required this.onPressed,
  });

  final NotesDesktopPalette palette;
  final String label;
  final VoidCallback onPressed;

  @override
  State<_StripButton> createState() => _StripButtonState();
}

class _StripButtonState extends State<_StripButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final NotesDesktopPalette p = widget.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (PointerEnterEvent _) => setState(() => _hovered = true),
      onExit: (PointerExitEvent _) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? p.line : p.surface,
            borderRadius:
                BorderRadius.circular(NotesDesktopMetrics.radiusControl),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: NotesDesktopType.medium,
              color: p.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// A flat button in the sidebar's head: the "+ 新建" control.
class _FlatButton extends StatefulWidget {
  const _FlatButton({
    required this.palette,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final NotesDesktopPalette palette;
  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  @override
  State<_FlatButton> createState() => _FlatButtonState();
}

class _FlatButtonState extends State<_FlatButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final NotesDesktopPalette p = widget.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (PointerEnterEvent _) => setState(() => _hovered = true),
      onExit: (PointerExitEvent _) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _hovered ? p.line : p.hover,
            borderRadius:
                BorderRadius.circular(NotesDesktopMetrics.radiusControl),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(widget.icon, size: 15, color: p.ink),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  color: p.ink,
                  fontWeight: NotesDesktopType.body,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The search box: flat, with a hairline, no fill of its own.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.palette,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final NotesDesktopPalette palette;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final NotesDesktopPalette p = palette;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(NotesDesktopMetrics.radiusControl),
        border: Border.all(color: p.fieldLine),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.search, size: 15, color: p.faint),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              style: TextStyle(fontSize: 13, color: p.ink),
              cursorColor: p.accent,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: NotesStrings.desktopSearchHint,
                hintStyle: TextStyle(fontSize: 13, color: p.faint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A section heading in the note list: "已置顶" or "全部笔记".
///
/// A type of its own so that the list can hold headings and notes in one ordered `List<Object>`
/// without either being able to be mistaken for the other.
class _SectionHeading {
  const _SectionHeading(this.text, {this.topGap = 0});

  final String text;

  /// The room above it. Zero for the first heading, which the search field already spaces.
  final double topGap;
}

/// One note the list is showing, and the line the search found it on.
///
/// The snippet travels with the note rather than being looked up again by the row: a row that
/// ran the search itself would run it once per note per build, and could disagree with the
/// filtering that let the note into the list at all.
class _Hit {
  const _Hit(this.note, this.snippet);

  final Note note;

  /// The matching line, or null when the title is what matched - or when there is no search on.
  final String? snippet;
}

/// One note in the sidebar: icon, title, preview, and the date on the right.
///
/// A pinned note also carries the pin on the second line, at the right-hand end - measured off
/// the mock-up, where the glyph's centre sits 22 from the sidebar's edge and 38 down from the
/// row's top, which is the line the preview is on.
class _NoteRow extends StatefulWidget {
  const _NoteRow({
    required this.note,
    required this.snippet,
    required this.palette,
    required this.selected,
    required this.pinned,
    required this.onTap,
    required this.onContextMenu,
    required this.onTogglePin,
  });

  final Note note;

  /// The line the search found, shown in place of the note's first line. Null when there is no
  /// search on, or when the title is what matched.
  final String? snippet;
  final NotesDesktopPalette palette;
  final bool selected;
  final bool pinned;
  final VoidCallback onTap;

  /// The right-click menu, with the pointer's position in global coordinates.
  final ValueChanged<Offset> onContextMenu;

  final VoidCallback onTogglePin;

  @override
  State<_NoteRow> createState() => _NoteRowState();
}

class _NoteRowState extends State<_NoteRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final NotesDesktopPalette p = widget.palette;
    final Note note = widget.note;
    final bool selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (PointerEnterEvent _) => setState(() => _hovered = true),
      onExit: (PointerExitEvent _) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: (TapDownDetails details) =>
            widget.onContextMenu(details.globalPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          child: Container(
            height: NotesDesktopMetrics.rowHeight,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: selected
                  ? (_hovered ? p.line : p.hover)
                  : (_hovered ? p.hover : Colors.transparent),
              borderRadius:
                  BorderRadius.circular(NotesDesktopMetrics.radiusRow),
            ),
            child: Stack(
              children: <Widget>[
                Positioned(
                  left: NotesDesktopMetrics.listIconLeft - 12,
                  top: 20,
                  child: Icon(
                    Icons.description_outlined,
                    size: 15,
                    color: selected ? p.accent : p.faint,
                  ),
                ),
                Positioned(
                  left: NotesDesktopMetrics.listTextLeft - 12,
                  right: 52,
                  top: 9,
                  child: Text(
                    note.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected
                          ? NotesDesktopType.emphasis
                          : NotesDesktopType.body,
                      color: p.ink,
                    ),
                  ),
                ),
                Positioned(
                  left: NotesDesktopMetrics.listTextLeft - 12,
                  right: widget.pinned ? 38 : 52,
                  top: 30,
                  child: Text(
                    // What the search found, when it found it somewhere other than the title:
                    // showing the note's first line while the word being looked for sits five
                    // lines further down is how a result looks like a mistake.
                    //
                    // Otherwise the note's own first line. It used to be `formatNoteSubtitle`,
                    // which prefixes the date as well - but this row already carries the date at
                    // its right-hand end, so the two together printed the same date twice.
                    widget.snippet ??
                        (note.preview.isEmpty
                            ? NotesStrings.desktopEmptyNote
                            : note.preview),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.sub),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 10,
                  child: Text(
                    formatNoteDate(note.modified),
                    style: TextStyle(fontSize: 11, color: p.faint),
                  ),
                ),
                if (widget.pinned)
                  Positioned(
                    right: 0,
                    top: 28,
                    width: 20,
                    height: 20,
                    child: _PinButton(
                      palette: p,
                      onPressed: widget.onTogglePin,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The pin on a pinned row. Pressing it takes the pin off, which is the one thing anybody wants
/// to do to a pin they can see.
class _PinButton extends StatefulWidget {
  const _PinButton({required this.palette, required this.onPressed});

  final NotesDesktopPalette palette;
  final VoidCallback onPressed;

  @override
  State<_PinButton> createState() => _PinButtonState();
}

class _PinButtonState extends State<_PinButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final NotesDesktopPalette p = widget.palette;
    return Tooltip(
      message: NotesStrings.desktopMenuUnpin,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (PointerEnterEvent _) => setState(() => _hovered = true),
        onExit: (PointerExitEvent _) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Center(
            child: Icon(
              Icons.push_pin_outlined,
              size: 13,
              color: _hovered ? p.ink : p.faint,
            ),
          ),
        ),
      ),
    );
  }
}

/// One tab.
///
/// The shape is Chrome's, and so is why: the selected tab is filled with the *editor's*
/// colour, rounded at the top, and flares back out at the bottom so that it joins the surface
/// below instead of resting a rectangle on a line.
class _Tab extends StatefulWidget {
  const _Tab({
    required this.width,
    required this.title,
    required this.palette,
    required this.selected,
    required this.dirty,
    required this.onSelect,
    required this.onClose,
  });

  /// How wide this tab is drawn. Decided by the strip, which narrows them as more notes are
  /// opened and scrolls once they reach [NotesDesktopMetrics.tabMinWidth].
  final double width;

  final String title;
  final NotesDesktopPalette palette;
  final bool selected;
  final bool dirty;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final NotesDesktopPalette p = widget.palette;
    final bool selected = widget.selected;
    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (PointerEnterEvent _) => setState(() => _hovered = true),
        onExit: (PointerExitEvent _) => setState(() => _hovered = false),
        // A middle click closes the tab, the way it does in every browser. Wrapped around the
        // gesture detector rather than folded into it: `GestureDetector` has no middle-click
        // callback, and this must not swallow the left-click that selects the tab.
        child: Listener(
          onPointerDown: (PointerDownEvent event) {
            if (event.buttons == kMiddleMouseButton) widget.onClose();
          },
          child: GestureDetector(
            onTap: widget.onSelect,
            child: CustomPaint(
            painter: _TabPainter(
              fill: selected
                  ? p.surface
                  : (_hovered ? p.hover : Colors.transparent),
              radius: NotesDesktopMetrics.tabRadius,
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 15, right: 12, top: 6),
              child: Row(
                children: <Widget>[
                  if (widget.dirty)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.accent,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.description_outlined,
                        size: 13,
                        color: p.faint,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: selected ? p.ink : p.sub,
                        fontWeight: NotesDesktopType.body,
                      ),
                    ),
                  ),
                  if (selected || _hovered)
                    GestureDetector(
                      onTap: widget.onClose,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.close, size: 12, color: p.sub),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}

class _TabPainter extends CustomPainter {
  const _TabPainter({required this.fill, required this.radius});

  final Color fill;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (fill == Colors.transparent) return;
    const double top = 6;
    const double foot = 9;
    final double left = foot;
    final double right = size.width - foot;
    final Path path = Path()
      ..moveTo(left + radius, top)
      ..lineTo(right - radius, top)
      ..arcToPoint(Offset(right, top + radius),
          radius: Radius.circular(radius))
      ..lineTo(right, size.height - radius)
      // The foot: out to the bottom edge, then along it, then back up the other side.
      ..quadraticBezierTo(
          right, size.height, right + foot, size.height)
      ..lineTo(left - foot, size.height)
      ..quadraticBezierTo(left, size.height, left, size.height - radius)
      ..lineTo(left, top + radius)
      ..arcToPoint(Offset(left + radius, top),
          radius: Radius.circular(radius))
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_TabPainter old) =>
      old.fill != fill || old.radius != radius;
}

/// The "+" that ends the tab strip: writes a new note and opens it in a tab.
///
/// It is a plain glyph on the strip's own tone until the pointer is over it, which is what the
/// mock-up draws - the strip is mostly empty space, and a permanent button there would be the
/// loudest thing in the window's chrome.
class _NewTabButton extends StatefulWidget {
  const _NewTabButton({required this.palette, required this.onPressed});

  final NotesDesktopPalette palette;
  final VoidCallback onPressed;

  @override
  State<_NewTabButton> createState() => _NewTabButtonState();
}

class _NewTabButtonState extends State<_NewTabButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final NotesDesktopPalette p = widget.palette;
    return Tooltip(
      message: NotesStrings.desktopNewTab,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (PointerEnterEvent _) => setState(() => _hovered = true),
        onExit: (PointerExitEvent _) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: SizedBox(
            width: NotesDesktopMetrics.newTabWidth,
            child: Center(
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _hovered ? p.hover : Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(NotesDesktopMetrics.radiusControl),
                ),
                child: Icon(Icons.add, size: 15, color: p.sub),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _WindowButtonKind { minimize, maximize, restore, close }

/// A square icon button for the band, at the same weight as the note list's own buttons.
///
/// The window buttons next to it are drawn glyphs because they have to match Windows' hairlines.
/// This one is a Material icon, because there is no OS glyph for folding a panel away.
class _BandButton extends StatefulWidget {
  const _BandButton({
    required this.palette,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final NotesDesktopPalette palette;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_BandButton> createState() => _BandButtonState();
}

class _BandButtonState extends State<_BandButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final NotesDesktopPalette p = widget.palette;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (PointerEnterEvent _) => setState(() => _hovered = true),
        onExit: (PointerExitEvent _) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 34,
            height: 26,
            decoration: BoxDecoration(
              color: _hovered ? p.hover : Colors.transparent,
              borderRadius:
                  BorderRadius.circular(NotesDesktopMetrics.radiusControl),
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: _hovered ? p.ink : p.sub,
            ),
          ),
        ),
      ),
    );
  }
}

/// A window button, drawn rather than typed, so the glyphs are the hairlines Windows uses.
class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.palette,
    required this.kind,
    required this.tooltip,
    required this.onPressed,
  });

  final NotesDesktopPalette palette;
  final _WindowButtonKind kind;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final NotesDesktopPalette p = widget.palette;
    final bool close = widget.kind == _WindowButtonKind.close;
    final Color background = _hovered
        ? (close ? const Color(0xFFC42B1C) : p.hover)
        : Colors.transparent;
    final Color foreground =
        _hovered && close ? Colors.white : p.sub;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (PointerEnterEvent _) => setState(() => _hovered = true),
        onExit: (PointerExitEvent _) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: NotesDesktopMetrics.windowButtonWidth,
            // `double.infinity` rather than nothing: a bare CustomPaint has no size of its own,
            // and a zero-height button is a button that cannot be clicked.
            height: double.infinity,
            color: background,
            child: CustomPaint(
              size: Size.infinite,
              painter: _WindowGlyphPainter(
                kind: widget.kind,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowGlyphPainter extends CustomPainter {
  const _WindowGlyphPainter({required this.kind, required this.color});

  final _WindowButtonKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final Offset c = Offset(size.width / 2, size.height / 2);
    switch (kind) {
      case _WindowButtonKind.minimize:
        canvas.drawLine(c.translate(-5, 0), c.translate(5, 0), paint);
      case _WindowButtonKind.maximize:
        canvas.drawRect(Rect.fromCenter(center: c, width: 10, height: 10), paint);
      case _WindowButtonKind.restore:
        canvas.drawRect(
          Rect.fromLTWH(c.dx - 5, c.dy - 3, 8, 8),
          paint,
        );
        canvas.drawRect(
          Rect.fromLTWH(c.dx - 2, c.dy - 6, 8, 8),
          paint,
        );
      case _WindowButtonKind.close:
        canvas.drawLine(c.translate(-5, -5), c.translate(5, 5), paint);
        canvas.drawLine(c.translate(5, -5), c.translate(-5, 5), paint);
    }
  }

  @override
  bool shouldRepaint(_WindowGlyphPainter old) =>
      old.kind != kind || old.color != color;
}

/// The placeholder shown in the editor area instead of a note.
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.palette,
    required this.icon,
    required this.title,
    required this.detail,
  });

  final NotesDesktopPalette palette;
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final NotesDesktopPalette p = palette;
    return ColoredBox(
      color: p.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 34, color: p.faint),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: NotesDesktopType.emphasis,
                color: p.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(detail, style: TextStyle(fontSize: 13, color: p.sub)),
          ],
        ),
      ),
    );
  }
}
