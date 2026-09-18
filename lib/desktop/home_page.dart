import 'dart:async';
import 'dart:io';
// `AppExitResponse` is declared in dart:ui and is not re-exported by material.
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../notes_store.dart';
import '../strings.dart';
import 'desktop_design.dart';
import 'editor_pane.dart';
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

  /// The open pane, so the shell can ask it to write before it is replaced or the window
  /// closes. A new key is minted per note, which is also what gives each note a fresh editor.
  GlobalKey<EditorPaneState> _editorKey = GlobalKey<EditorPaneState>();
  final TextEditingController _search = TextEditingController();  SystemAccent _accent = SystemAccent.fallback;
  List<Note> _notes = <Note>[];

  /// The note in the editor, if any.
  Note? _open;
  bool _loading = true;
  bool _dirty = false;
  String _query = '';
  String? _error;
  double _sidebarWidth = NotesDesktopMetrics.sidebarDefault;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadAccent());
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  /// The window is going away: put the last keystrokes on disk before it does.
  ///
  /// `dispose()` cannot await, and on Windows the window close arrives as a request the app can
  /// still answer, so this is the moment to write.
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await _editorKey.currentState?.flush();
    return AppExitResponse.exit;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Losing the foreground is the last moment before the process could be killed.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_editorKey.currentState?.flush());
    }
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
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loading = false;
        _error = null;
        // The open note can have gone: deleted here, renamed by Syncthing, or moved away.
        final Note? open = _open;
        if (open != null &&
            !notes.any((Note n) => n.file.path == open.file.path)) {
          _open = null;
        }
      });
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

  Future<void> _newNote() async {
    try {
      final File file = await _store.createNote();
      await _refresh();
      if (!mounted) return;
      final Note created = _notes.firstWhere(
        (Note n) => n.file.path == file.path,
        orElse: () => Note(file: file, modified: DateTime.now(), preview: ''),
      );
      await _openNote(created);
    } on FileSystemException catch (error) {
      _toast(NotesStrings.createFailed(
        error.osError?.message ?? error.message,
      ));
    }
  }

  Future<void> _openNote(Note note) async {
    if (_open?.file.path == note.file.path) return;
    // Whatever is in the pane now goes to disk before it is replaced, and the await matters:
    // the pane is disposed as soon as `_open` changes, and `dispose()` cannot wait.
    await _editorKey.currentState?.flush();
    if (!mounted) return;
    setState(() {
      // A fresh key, so the next note gets a fresh controller rather than an old one pointed
      // at a different file.
      _editorKey = GlobalKey<EditorPaneState>();
      _open = note;
      _dirty = false;
    });
  }

  Future<void> _closeNote() async {
    await _editorKey.currentState?.flush();
    if (!mounted) return;
    setState(() {
      _open = null;
      _dirty = false;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  List<Note> get _visibleNotes {
    if (_query.isEmpty) return _notes;
    final String needle = _query.toLowerCase();
    return _notes
        .where((Note n) =>
            n.title.toLowerCase().contains(needle) ||
            n.preview.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final NotesDesktopPalette p = brightness == Brightness.dark
        ? NotesDesktopPalette.dark(_accent)
        : NotesDesktopPalette.light(_accent);

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: p.accent,
          brightness: brightness,
        ).copyWith(surface: p.surface, primary: p.accent),
      ),
      child: Scaffold(
        backgroundColor: p.page,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _band(p),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(width: _sidebarWidth, child: _sidebar(p)),
                  _resizeHandle(p),
                  Expanded(child: _editorArea(p)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- the top band --------------------------------------------------------

  Widget _band(NotesDesktopPalette p) {
    return SizedBox(
      height: NotesDesktopMetrics.band,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(width: _sidebarWidth, child: _sidebarHead(p)),
          Expanded(child: _tabStrip(p)),
          _windowButtons(p),
        ],
      ),
    );
  }

  Widget _sidebarHead(NotesDesktopPalette p) {
    return ColoredBox(
      color: p.page,
      child: Padding(
        padding: const EdgeInsets.only(left: 22, right: 18),
        child: Row(
          children: <Widget>[
            Text(
              NotesStrings.listTitle,
              style: TextStyle(
                fontSize: 17,
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
    );
  }

  /// The strip the tabs sit on, and the app's drag handle.
  ///
  /// The empty part of the strip is what moves the window: pressing it hands the window to the
  /// OS for a caption drag, which is also what keeps Aero snap and double-click-to-maximise
  /// working without reimplementing either.
  Widget _tabStrip(NotesDesktopPalette p) {
    return ColoredBox(
      color: p.frame,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (DragDownDetails _) => unawaited(NotesWindow.startDrag()),
              onDoubleTap: () => unawaited(NotesWindow.toggleMaximize()),
            ),
          ),
          if (_open != null)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: _Tab(
                title: Note.fileNameWithoutExtension(_open!.file),
                palette: p,
                selected: true,
                dirty: _dirty,
                onSelect: () {},
                onClose: () => unawaited(_closeNote()),
              ),
            ),
        ],
      ),
    );
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
    final List<Note> notes = _visibleNotes;
    return ColoredBox(
      color: p.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: _SearchField(
              palette: p,
              controller: _search,
              onChanged: (String value) => setState(() => _query = value),
            ),
          ),
          const SizedBox(height: 14),
          _sectionLabel(p, NotesStrings.desktopNoteCountSection),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: notes.length,
              itemBuilder: (BuildContext context, int index) {
                final Note note = notes[index];
                return _NoteRow(
                  note: note,
                  palette: p,
                  selected: _open?.file.path == note.file.path,
                  onTap: () => unawaited(_openNote(note)),
                );
              },
            ),
          ),
          if (notes.isEmpty && !_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
              child: Text(
                _query.isEmpty ? NotesStrings.emptyTitle : NotesStrings.searchEmptyTitle,
                style: TextStyle(fontSize: 13, color: p.faint),
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

  Widget _sectionLabel(NotesDesktopPalette p, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: p.faint),
      ),
    );
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
    final Note? open = _open;
    if (open == null) {
      return _CenteredMessage(
        palette: p,
        icon: Icons.article_outlined,
        title: NotesStrings.nothingOpenTitle,
        detail: NotesStrings.nothingOpenDetail,
      );
    }
    return EditorPane(
      // A new key per note, so switching builds a new controller rather than pointing an old
      // one at a different file.
      key: _editorKey,
      store: _store,
      file: open.file,
      modified: open.modified,
      palette: p,
      onRenamed: (File renamed) async {
        // The file moved, so the note the shell is holding has to move with it - otherwise the
        // next refresh would decide the open note had been deleted and close it.
        await _refresh();
        if (!mounted) return;
        setState(() {
          _open = _notes.firstWhere(
            (Note n) => n.file.path == renamed.path,
            orElse: () => Note(
              file: renamed,
              modified: DateTime.now(),
              preview: open.preview,
            ),
          );
        });
      },
      onDirtyChanged: (bool dirty) {
        if (dirty != _dirty) setState(() => _dirty = dirty);
      },
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
    required this.onChanged,
  });

  final NotesDesktopPalette palette;
  final TextEditingController controller;
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

/// One note in the sidebar: icon, title, preview, and the date on the right.
class _NoteRow extends StatefulWidget {
  const _NoteRow({
    required this.note,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final Note note;
  final NotesDesktopPalette palette;
  final bool selected;
  final VoidCallback onTap;

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
                  right: 52,
                  top: 30,
                  child: Text(
                    formatNoteSubtitle(note.modified, note.preview),
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
              ],
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
    required this.title,
    required this.palette,
    required this.selected,
    required this.dirty,
    required this.onSelect,
    required this.onClose,
  });

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
      width: NotesDesktopMetrics.tabWidth,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (PointerEnterEvent _) => setState(() => _hovered = true),
        onExit: (PointerExitEvent _) => setState(() => _hovered = false),
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

enum _WindowButtonKind { minimize, maximize, restore, close }

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
