import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
// `RenderEditable` (for revealing a find hit) and the key types Escape needs are re-exported by
// neither material nor gestures.
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../load_failed_view.dart';
import '../format.dart';
import '../markdown_controller.dart';
import '../markdown_span.dart';
import '../note_editor_controller.dart';
import '../note_finder.dart';
import '../note_title.dart';
import '../notes_store.dart';
import '../strings.dart';
import 'desktop_design.dart';

/// The note being edited, filling the right-hand side of the window.
///
/// There is no card and no border: the pane *is* the note's surface, and it is the same colour
/// as the selected tab above it, so the two read as one shape. That is the whole reason the
/// editor is not a card floating on a background any more.
///
/// Everything that decides *what happens* lives in [NoteEditorController], which the Android
/// editor drives as well, so the two interfaces cannot disagree about when a note is written.
class EditorPane extends StatefulWidget {
  const EditorPane({
    super.key,
    required this.store,
    required this.file,
    required this.modified,
    required this.palette,
    required this.onRenamed,
    required this.onDirtyChanged,
  });

  final NotesStore store;
  final File file;

  /// When the note was last written, shown under the title. The title *is* the file name, so
  /// repeating the name here would say the same thing twice.
  final DateTime modified;

  final NotesDesktopPalette palette;

  /// Called after a rename, so the sidebar (and the tab, later) can follow the new name.
  final ValueChanged<File> onRenamed;

  /// Called whenever there is something unsaved, so the title bar can say so.
  final ValueChanged<bool> onDirtyChanged;

  @override
  State<EditorPane> createState() => EditorPaneState();
}

class EditorPaneState extends State<EditorPane> {
  late final NoteEditorController _editor = NoteEditorController(
    store: widget.store,
    file: widget.file,
  );

  late final MarkdownEditingController _body = MarkdownEditingController(
    palette: widget.palette.rendererPalette,
    emphasis: NotesDesktopType.emphasis,
    monoFamily: NotesDesktopType.monoFamily,
  );

  final TextEditingController _title = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _bodyFocus = FocusNode();

  /// Whether the body is showing the file's own characters rather than the rendered note.
  ///
  /// Per note rather than one setting for the window: it is a way of looking at *this* note
  /// (usually to see why a line is rendering oddly), and it starts off for every note that is
  /// opened. Deliberately not remembered between visits either - a note that opened as source
  /// because of something done to a different note last week would be baffling.
  bool _sourceMode = false;

  /// The find bar: whether it is up, what is typed in it, and where the search has got to.
  final TextEditingController _find = TextEditingController();
  final FocusNode _findFocus = FocusNode();
  bool _findOpen = false;
  List<int> _findHits = const <int>[];

  /// Which hit is being looked at, or -1 when there are none.
  int _findIndex = -1;

  @override
  void initState() {
    super.initState();
    _editor.addListener(_onEditorChanged);
    _titleFocus.addListener(_onTitleFocusChanged);
    unawaited(_reload());
  }

  /// The palette is rebuilt whenever the theme changes, and the body has to repaint with it.
  ///
  /// Without this the note keeps the colours its controller was created with until the note is
  /// closed and opened again - which is exactly what switching to the light theme while reading
  /// would run into.
  ///
  /// Compared by value, not by identity: [NotesDesktopPalette] is constructed fresh on every
  /// build of the page, so `old != widget` is always true, and repainting on that would loop
  /// forever.
  ///
  /// Assigning the palette is the whole of it - the rebuild that follows this call takes the
  /// text field through `buildTextSpan` again. Asking the controller to notify instead would
  /// mean reaching for a member `ChangeNotifier` keeps to its subclasses.
  @override
  void didUpdateWidget(EditorPane old) {
    super.didUpdateWidget(old);
    if (old.palette.isDark == widget.palette.isDark &&
        old.palette.accent == widget.palette.accent) {
      return;
    }
    _body.palette = widget.palette.rendererPalette;
  }

  @override
  void dispose() {
    _editor.removeListener(_onEditorChanged);
    _titleFocus.removeListener(_onTitleFocusChanged);
    _titleFocus.dispose();
    _bodyFocus.dispose();
    _title.dispose();
    _body.dispose();
    _find.dispose();
    _findFocus.dispose();
    _editor.dispose();
    super.dispose();
  }

  /// Writes whatever is pending. Called before the pane is replaced, and before the window
  /// closes, so a switch of notes can never lose the last keystrokes.
  Future<void> flush() => _editor.flush();

  /// Puts the caret in the title field with the whole name selected.
  ///
  /// This is what the note list's "重命名" does. The title *is* the file name, so renaming is
  /// editing this field - a second dialog asking for a name would be a second place that decides
  /// what the file is called, and the two could disagree.
  void startRename() {
    _titleFocus.requestFocus();
    _title.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _title.text.length,
    );
  }

  /// Whether this note has text that is not on disk yet.
  ///
  /// The shell reads this to draw the dot on the tab. The pane owns the controller, so the pane
  /// is the only thing that knows - and with every open note keeping its editor mounted, there
  /// is one of these per tab.
  bool get isDirty => _editor.hasUnsavedChanges;

  /// Saves and waits for the file. Leaving is not allowed to race the write.
  Future<void> close() => _editor.close();

  /// Looks at the file and reports whether somebody else has changed it.
  ///
  /// Called by the page when the folder watcher fires. What to do about an answer of
  /// [ExternalChange.conflict] is the user's call, and the banner this pane draws is how they
  /// are asked.
  ///
  /// A reload has to be copied into the text field by hand: the field only ever holds what
  /// [_syncFields] put there, and nothing else calls it on this path. Without that the note
  /// would be reloaded in the controller and left on screen exactly as it was.
  Future<ExternalChange> applyExternalChange() async {
    final ExternalChange change = await _editor.applyExternalChange();
    if (change == ExternalChange.reloaded && mounted) _syncFields();
    return change;
  }

  /// Takes the file's version, throwing the text in the editor away.
  ///
  /// Same hand-off as [applyExternalChange]: the controller reloads, the field has to be told.
  Future<void> _takeDiskVersion() async {
    await _editor.takeDiskVersion();
    if (!mounted) return;
    _syncFields();
  }

  Future<void> _reload() async {
    await _editor.load();
    if (!mounted) return;
    _syncFields();
  }

  Future<void> _retryLoad() async {
    await _editor.retryLoad();
    if (!mounted) return;
    _syncFields();
  }

  /// Copies the controller's text into the fields.
  ///
  /// Assigning text programmatically does not fire `onChanged`, so this can never loop back.
  void _syncFields() {
    if (_body.text != _editor.text) {
      _body.value = TextEditingValue(
        text: _editor.text,
        selection: TextSelection.collapsed(offset: _editor.text.length),
      );
    }
    final String name = Note.fileNameWithoutExtension(_editor.file);
    if (_title.text != name) _title.text = name;
  }

  void _onEditorChanged() {
    if (!mounted) return;
    setState(() {});
    widget.onDirtyChanged(_editor.hasUnsavedChanges);
  }

  /// Renames the file when the title field is left, not on every keystroke: each rename is a
  /// file operation, and typing a name would otherwise rename the file a dozen times.
  void _onTitleFocusChanged() {
    if (!_titleFocus.hasFocus) unawaited(_commitTitle());
  }

  Future<void> _commitTitle() async {
    final String typed = _title.text;
    if (typed.isEmpty) {
      _syncFields();
      return;
    }
    if (sanitiseNoteTitle(typed) == Note.fileNameWithoutExtension(_editor.file)) {
      _syncFields();
      return;
    }
    await _editor.renameTo(typed);
    if (!mounted) return;
    _syncFields();
    widget.onRenamed(_editor.file);
  }

  /// Ticks or unticks a task box when the click landed on one.
  ///
  /// The box is painted text rather than a widget, so there is nothing to attach a gesture to:
  /// instead the click places the caret, and a caret that lands on a box means the box is what
  /// was clicked. The caret is only correct once the click has been fully handled, hence the
  /// frame callback.
  void _onBodyClicked() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_body.selection.isValid) return;
      final int offset = _body.selection.baseOffset;
      final int? mark = taskBoxIndexAt(_body.text, offset);
      if (mark == null) return;
      final String flipped = toggleTaskAt(_body.text, mark);
      _body.value = TextEditingValue(
        text: flipped,
        selection: TextSelection.collapsed(offset: offset),
      );
      _editor.onChanged(flipped);
    });
  }

  @override
  Widget build(BuildContext context) {
    final NotesDesktopPalette p = widget.palette;
    // Before the field below is built, so the span it draws this frame already carries the
    // highlights.
    _syncHighlights(p);
    return ColoredBox(
      color: p.surface,
      child: _body_(p),
    );
  }

  /// The strip that appears when the file on disk and the text in here are two different
  /// pieces of work.
  ///
  /// It is a strip and not a dialog on purpose: nothing is blocked - the user can keep typing,
  /// scrolling and copying - right up to the moment they decide which version survives. The
  /// accent colour rather than a red one because this is not an error: two machines edited the
  /// same note, which is exactly what the note is being synced for.
  Widget _externalChangeBanner(NotesDesktopPalette p) {
    return Container(
      color: p.hover,
      padding: const EdgeInsets.fromLTRB(26, 10, 18, 10),
      child: Row(
        children: <Widget>[
          Icon(Icons.sync_problem, size: 17, color: p.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  NotesStrings.externalChangeTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: NotesDesktopType.emphasis,
                    color: p.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  NotesStrings.externalChangeDetail,
                  style: TextStyle(fontSize: 12, color: p.sub),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _BannerButton(
            palette: p,
            label: NotesStrings.externalChangeTakeDisk,
            onPressed: () => unawaited(_takeDiskVersion()),
          ),
          const SizedBox(width: 8),
          _BannerButton(
            palette: p,
            label: NotesStrings.externalChangeKeepMine,
            onPressed: () => unawaited(_editor.keepMine()),
          ),
        ],
      ),
    );
  }

  Widget _body_(NotesDesktopPalette p) {
    if (_editor.loading) {
      return Center(child: CircularProgressIndicator(color: p.accent));
    }
    if (_editor.loadFailed) {
      return LoadFailedView(message: _editor.error ?? '', onRetry: _retryLoad);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Above the conflict banner: it is the thing the user just asked for, and its place
        // should not move depending on what else the pane happens to be showing.
        if (_findOpen) _findBar(p),
        if (_editor.hasExternalChange) _externalChangeBanner(p),
        Expanded(
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: NotesDesktopMetrics.bodyMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 40, 0, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _titleField(p),
                      const SizedBox(height: 6),
                      Text(
                        formatNoteHeading(widget.modified, widget.file.path),
                        style: TextStyle(
                          fontSize: 12,
                          color: p.faint,
                          fontWeight: NotesDesktopType.body,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _bodyField(p),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        _statusLine(p),
      ],
    );
  }

  Widget _titleField(NotesDesktopPalette p) {
    return TextField(
      controller: _title,
      focusNode: _titleFocus,
      onSubmitted: (String _) => _bodyFocus.requestFocus(),
      textInputAction: TextInputAction.next,
      style: TextStyle(
        fontSize: NotesDesktopMetrics.titleFontSize,
        fontWeight: NotesDesktopType.strong,
        color: p.ink,
      ),
      cursorColor: p.accent,
      decoration: const InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
        hintText: NotesStrings.editorTitleHint,
      ),
    );
  }

  Widget _bodyField(NotesDesktopPalette p) {
    return TextField(
      controller: _body,
      focusNode: _bodyFocus,
      onChanged: _editor.onChanged,
      onTap: _onBodyClicked,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      // Each line is as tall as its own text. Without this a text field forces every line to
      // the height of the *field's* style, which shaves the top off a large heading - the bug
      // that took a phase to find on the phone (HANDOFF_PHASE5 section 16.8).
      strutStyle: const StrutStyle(forceStrutHeight: false),
      style: TextStyle(
        fontSize: NotesDesktopMetrics.bodyFontSize,
        height: NotesDesktopMetrics.bodyLineHeight,
        fontWeight: NotesDesktopType.body,
        color: p.ink,
      ),
      cursorColor: p.accent,
      cursorWidth: 1.5,
      decoration: const InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _statusLine(NotesDesktopPalette p) {
    // A conflict outranks everything else the status line could say: while it is up, the note
    // is not being saved, and "已保存" would be a lie.
    final String state = _editor.hasExternalChange
        ? NotesStrings.externalChangeTitle
        : _editor.error != null
            ? _editor.error!
            : (_editor.hasUnsavedChanges
                ? NotesStrings.savingStatus
                : NotesStrings.savedStatus(_body.text.characters.length));
    return SizedBox(
      height: NotesDesktopMetrics.statusHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Row(
          children: <Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _editor.error != null ? Colors.redAccent : p.accent,
              ),
            ),
            const SizedBox(width: 8),
            // Everything on this line is allowed to shrink, because the path is not: it can be
            // any length at all (a deep folder, a long title) and the row used to run off the
            // edge of the window once it was. Equal shares, because the two need about the same
            // room - a narrower share for the state cuts it to "已…", which says nothing, before
            // the path has given up anything at all. The path is right-aligned inside its share,
            // so it stays against the buttons rather than floating in the middle.
            Expanded(
              child: Text(
                state,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: p.faint),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.file.path,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: p.faint),
              ),
            ),
            const SizedBox(width: 12),
            // Ctrl+F is the fast way in, but nothing on screen announces it; this is how the
            // feature is found at all.
            _StatusToggle(
              palette: p,
              label: NotesStrings.desktopFindOpen,
              tooltip: NotesStrings.desktopFindTip,
              onPressed: openFind,
            ),
            const SizedBox(width: 6),
            _StatusToggle(
              palette: p,
              // What pressing it does, like the band's theme button.
              label: _sourceMode
                  ? NotesStrings.desktopViewRendered
                  : NotesStrings.desktopViewSource,
              tooltip: _sourceMode
                  ? NotesStrings.desktopViewRenderedTip
                  : NotesStrings.desktopViewSourceTip,
              onPressed: _toggleSource,
            ),
          ],
        ),
      ),
    );
  }

  /// Flips the body between the rendered note and the file's own characters.
  ///
  /// All that has to happen is the flag and a rebuild: the field calls `buildTextSpan` again
  /// during the rebuild, and the controller decides what to draw. The note itself, the caret
  /// and the undo history are untouched - nothing is reloaded.
  void _toggleSource() {
    setState(() {
      _sourceMode = !_sourceMode;
      _body.sourceMode = _sourceMode;
    });
  }

  // --- finding inside this note (Ctrl+F) ------------------------------------

  /// Opens the find bar and puts the caret in it. What Ctrl+F does.
  void openFind() {
    if (!_findOpen) setState(() => _findOpen = true);
    // The field does not exist until the build that opening it triggers.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _findFocus.requestFocus();
    });
  }

  void _closeFind() {
    setState(() {
      _findOpen = false;
      _find.clear();
      _findHits = const <int>[];
      _findIndex = -1;
    });
    // Back to the note, so Esc leaves the user where they were rather than nowhere.
    _bodyFocus.requestFocus();
  }

  /// A new word to look for.
  ///
  /// The search starts from the caret, so pressing Ctrl+F halfway down a note finds the next
  /// one below rather than sending the user back to the top of the file.
  void _onFindChanged(String term) {
    final List<int> hits = findMatchOffsets(_body.text, term);
    final int caret = _body.selection.isValid ? _body.selection.baseOffset : 0;
    final int index = hits.isEmpty ? -1 : firstMatchFrom(hits, caret);
    setState(() {
      _findHits = hits;
      _findIndex = index;
    });
    if (index >= 0) _revealHit(index);
  }

  /// Enter, or one of the two arrows. Wraps round at either end.
  void _stepFind(int delta) {
    if (_findHits.isEmpty) return;
    setState(() {
      _findIndex = delta > 0
          ? nextMatch(_findIndex, _findHits.length)
          : previousMatch(_findIndex, _findHits.length);
    });
    _revealHit(_findIndex);
  }

  /// Selects the hit and brings it into view.
  void _revealHit(int index) {
    final int start = _findHits[index];
    _body.selection = TextSelection(
      baseOffset: start,
      extentOffset: start + _find.text.length,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollTo(start);
    });
  }

  /// Scrolls so the hit is on screen.
  ///
  /// A `TextField` will not do this by itself: its own caret-revealing path needs the field to
  /// own a scroll controller, and this one grows to its full height inside the page's scroll
  /// view instead - so that path returns without doing anything. The caret's rectangle is asked
  /// for directly and handed to `showOnScreen`, which walks up to whichever scrollable encloses
  /// it: the same mechanism, entered from the side that works here.
  void _scrollTo(int offset) {
    final RenderObject? render = _bodyFocus.context?.findRenderObject();
    if (render is! RenderEditable) return;
    render.showOnScreen(
      rect: render.getLocalRectForCaret(TextPosition(offset: offset)),
    );
  }

  /// Hands what has been found to the controller, which is what paints it.
  ///
  /// Called from `build` rather than from each of the places the state changes: it depends on
  /// the palette as well, and the palette changes with the theme without any of those running.
  void _syncHighlights(NotesDesktopPalette p) {
    final String term = _find.text;
    final List<(int, int, Color)> marks = <(int, int, Color)>[];
    if (_findOpen && term.isNotEmpty) {
      for (int i = 0; i < _findHits.length; i++) {
        final int start = _findHits[i];
        marks.add((
          start,
          start + term.length,
          i == _findIndex ? p.currentMatchHighlight : p.matchHighlight,
        ));
      }
    }
    _body.highlights = marks;
  }

  /// The bar across the top of the pane while a search is on.
  Widget _findBar(NotesDesktopPalette p) {
    final int total = _findHits.length;
    final String count = _find.text.isEmpty
        ? ''
        : (total == 0
            ? NotesStrings.findNoMatch
            : NotesStrings.findCount(_findIndex + 1, total));
    return Container(
      color: p.hover,
      padding: const EdgeInsets.fromLTRB(26, 8, 18, 8),
      child: Focus(
        // Escape closes it. Wrapped around the row rather than given to the field so that it
        // still works once the caret has wandered to one of the arrows.
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _closeFind();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Row(
          children: <Widget>[
            Icon(Icons.search, size: 15, color: p.faint),
            const SizedBox(width: 8),
            SizedBox(
              width: 220,
              child: TextField(
                key: const ValueKey<String>('note-find-field'),
                controller: _find,
                focusNode: _findFocus,
                onChanged: _onFindChanged,
                onSubmitted: (String _) => _stepFind(1),
                style: TextStyle(fontSize: 13, color: p.ink),
                cursorColor: p.accent,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: NotesStrings.findHint,
                  hintStyle: TextStyle(fontSize: 13, color: p.faint),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(count, style: TextStyle(fontSize: 12, color: p.faint)),
            const SizedBox(width: 12),
            _FindButton(
              palette: p,
              icon: Icons.keyboard_arrow_up,
              tooltip: NotesStrings.findPrevious,
              onPressed: () => _stepFind(-1),
            ),
            _FindButton(
              palette: p,
              icon: Icons.keyboard_arrow_down,
              tooltip: NotesStrings.findNext,
              onPressed: () => _stepFind(1),
            ),
            const Spacer(),
            _FindButton(
              palette: p,
              icon: Icons.close,
              tooltip: NotesStrings.findClose,
              onPressed: _closeFind,
            ),
          ],
        ),
      ),
    );
  }
}

/// A small icon button for the find bar.
class _FindButton extends StatefulWidget {
  const _FindButton({
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
  State<_FindButton> createState() => _FindButtonState();
}

class _FindButtonState extends State<_FindButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final NotesDesktopPalette p = widget.palette;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (PointerEnterEvent _) => setState(() => _hovered = true),
        onExit: (PointerExitEvent _) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: _hovered ? p.line : Colors.transparent,
              borderRadius:
                  BorderRadius.circular(NotesDesktopMetrics.radiusControl),
            ),
            child: Icon(widget.icon, size: 15, color: _hovered ? p.ink : p.sub),
          ),
        ),
      ),
    );
  }
}

/// The small switch at the right of the status line: source or rendered.
class _StatusToggle extends StatefulWidget {
  const _StatusToggle({
    required this.palette,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final NotesDesktopPalette palette;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_StatusToggle> createState() => _StatusToggleState();
}

class _StatusToggleState extends State<_StatusToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final NotesDesktopPalette p = widget.palette;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (PointerEnterEvent _) => setState(() => _hovered = true),
        onExit: (PointerExitEvent _) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: _hovered ? p.line : Colors.transparent,
              borderRadius:
                  BorderRadius.circular(NotesDesktopMetrics.radiusControl),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: NotesDesktopType.medium,
                color: _hovered ? p.ink : p.faint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A button for the external-change banner.
///
/// Local to this file rather than shared with the band's buttons: it sits on a filled strip
/// instead of on the page colour, so its hover has to be a step away from that strip rather
/// than the usual one.
class _BannerButton extends StatefulWidget {
  const _BannerButton({
    required this.palette,
    required this.label,
    required this.onPressed,
  });

  final NotesDesktopPalette palette;
  final String label;
  final VoidCallback onPressed;

  @override
  State<_BannerButton> createState() => _BannerButtonState();
}

class _BannerButtonState extends State<_BannerButton> {
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
