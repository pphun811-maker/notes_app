import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design.dart';
import '../load_failed_view.dart';
import '../markdown_span.dart';
import '../markdown_text.dart';
import '../note_editor_controller.dart';
import '../note_title.dart';
import '../notes_store.dart';
import '../strings.dart';
import 'markdown_controller.dart';
import 'widgets.dart';

/// The Android editor.
///
/// The look is specified by `design/final/ed4_expand.png`, `ed4_collapse.png` and
/// `ed4_format.png`; the saving rules are [NoteEditorController]'s, shared with the
/// desktop editor so the two cannot drift apart.
///
/// Two things are deliberately **not** here yet, and the buttons for them say so
/// rather than pretending to work:
///
/// * the format panel (font size, and the rest of the rows in `ed4_format.png`).
class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.store, required this.file});

  final NotesStore store;
  final File file;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with WidgetsBindingObserver {
  late final NoteEditorController _editor = NoteEditorController(
    store: widget.store,
    file: widget.file,
  );

  final MarkdownEditingController _field = MarkdownEditingController();
  final UndoHistoryController _history = UndoHistoryController();

  /// The title field. Its text is the file's name, not the note's first line.
  final TextEditingController _titleField = TextEditingController();
  final FocusNode _titleFocus = FocusNode();

  /// Held so the tick in the top bar can take focus away. Dismissing the keyboard is not
  /// enough: the field stays focused and the caret keeps blinking.
  final FocusNode _focus = FocusNode();

  /// The body's own scroll position, watched so the title can fold itself away.
  final ScrollController _bodyScroll = ScrollController();

  bool _toolbarExpanded = true;

  /// Whether the title is folded away, and whether the note has been scrolled far enough
  /// for the scroll position to be the thing deciding it.
  ///
  /// The two are tracked separately so the chevron and the scroll cannot fight: the scroll
  /// only acts when it *crosses* the threshold, so a title the user folded away by hand
  /// stays folded while they are still at the top of the note.
  bool _titleCollapsed = false;
  bool _scrolledPastTitle = false;

  bool _committingTitle = false;
  String? _shownError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _editor.addListener(_onEditorChanged);
    // The undo/redo buttons are enabled or greyed out from this controller's value.
    _history.addListener(_onHistoryChanged);
    // The tick comes and goes with the keyboard; the title is renamed when its field is
    // left. Both are driven by focus.
    _focus.addListener(_onFocusChanged);
    _titleFocus.addListener(_onTitleFocusChanged);
    _bodyScroll.addListener(_onBodyScroll);
    _titleField.text = Note.fileNameWithoutExtension(_editor.file);
    unawaited(_reload());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _editor.removeListener(_onEditorChanged);
    _history.removeListener(_onHistoryChanged);
    _focus.removeListener(_onFocusChanged);
    _titleFocus.removeListener(_onTitleFocusChanged);
    _history.dispose();
    _focus.dispose();
    _titleFocus.dispose();
    _bodyScroll.dispose();
    _titleField.dispose();
    _field.dispose();
    _editor.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onTitleFocusChanged() {
    if (!mounted) return;
    setState(() {});
    // Leaving the title field is the moment the user means "that is the name now". Renaming
    // on every keystroke would rename the file dozens of times per edit.
    if (!_titleFocus.hasFocus) unawaited(_commitTitle());
  }

  /// Folds the title away once the note has been scrolled past it, and brings it back when
  /// the note is scrolled back to the top.
  ///
  /// Only a *crossing* of the threshold counts. Reacting to every scroll event would undo a
  /// title the user had just folded away by hand the moment they nudged the note.
  void _onBodyScroll() {
    if (!mounted || !_bodyScroll.hasClients) return;
    // Never take the field away while it is being typed in.
    if (_titleFocus.hasFocus) return;
    final bool past = _bodyScroll.offset > NotesEditorMetrics.titleCollapseAt;
    if (past == _scrolledPastTitle) return;
    _scrolledPastTitle = past;
    setState(() => _titleCollapsed = past);
  }

  void _toggleTitle() {
    setState(() => _titleCollapsed = !_titleCollapsed);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The last moment Android is guaranteed to give us before it may kill the
    // process; the autosave debounce alone would lose the last few keystrokes.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_editor.flush());
    }
  }

  Future<void> _reload() async {
    await _editor.load();
    _syncField();
    _syncTitleField();
  }

  Future<void> _retryLoad() async {
    await _editor.retryLoad();
    _syncField();
    _syncTitleField();
  }

  void _syncField() {
    if (!mounted || _field.text == _editor.text) return;
    // The caret starts at the very beginning, which is also what keeps a note that is
    // longer than the screen showing its *start*. Opening a note is reading it first;
    // the keyboard only appears once the user taps where they want to write.
    _field.value = TextEditingValue(
      text: _editor.text,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  /// Puts the file's real name back in the title field.
  ///
  /// Called after a rename, and after a rename that was refused - what is on screen must
  /// always be what the file is actually called.
  void _syncTitleField() {
    if (!mounted) return;
    final String name = Note.fileNameWithoutExtension(_editor.file);
    if (_titleField.text == name) return;
    _titleField.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
  }

  /// Renames the note if the title field no longer matches the file's name.
  ///
  /// Guarded against re-entry: leaving the title field and leaving the page can both fire
  /// within the same moment, and a second rename would be working from a file path the
  /// first one has already moved.
  Future<void> _commitTitle() async {
    if (_committingTitle) return;
    _committingTitle = true;
    try {
      final String typed = _titleField.text;
      if (sanitiseNoteTitle(typed) == Note.fileNameWithoutExtension(_editor.file)) {
        // Nothing to rename - but the field may hold something cleaning would change (stray
        // spaces, a character no file system accepts), so show the name as it really is.
        _syncTitleField();
        return;
      }
      await _editor.renameTo(typed);
      _syncTitleField();
    } finally {
      _committingTitle = false;
    }
  }

  void _onEditorChanged() {
    if (!mounted) return;
    setState(() {});
    final String? error = _editor.error;
    if (error == null) {
      _shownError = null;
      return;
    }
    if (error != _shownError) {
      _shownError = error;
      _toast(error);
    }
  }

  void _onHistoryChanged() {
    if (mounted) setState(() {});
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Saves, then closes. The page never pops itself without going through here.
  Future<void> _handlePop(bool didPop) async {
    if (didPop) return;
    await _commitTitle();
    await _editor.close();
    if (mounted) Navigator.of(context).pop();
  }

  // --- the status line ------------------------------------------------------

  /// "已保存 · 128 字", or an honest description of why it is not.
  String get _saveLabel {
    if (_editor.error != null || _editor.loadFailed) {
      return NotesStrings.saveFailedStatus;
    }
    if (_editor.saving) return NotesStrings.savingStatus;
    if (_editor.hasUnsavedChanges) return NotesStrings.unsavedStatus;
    return NotesStrings.savedStatus(_editor.text.runes.length);
  }

  // --- toolbar actions ------------------------------------------------------

  /// Wraps the selection in a marker, e.g. `**` for bold.
  ///
  /// With nothing selected this leaves the cursor between the two markers, which is
  /// what you want for "start typing in bold".
  void _wrapSelection(String marker) {
    final TextEditingValue value = _field.value;
    final TextSelection selection = value.selection;
    if (!selection.isValid) return;
    final String text = value.text;
    final String selected = selection.textInside(text);
    final String updated = selection.textBefore(text) +
        marker +
        selected +
        marker +
        selection.textAfter(text);
    _applyEdit(
      updated,
      selection.start + marker.length,
      selection.start + marker.length + selected.length,
    );
  }

  /// Puts a marker at the start of the line the cursor is on.
  void _prefixLine(String prefix) {
    final TextEditingValue value = _field.value;
    final TextSelection selection = value.selection;
    if (!selection.isValid) return;
    final String text = value.text;
    final int lineStart = selection.start == 0
        ? 0
        : text.lastIndexOf('\n', selection.start - 1) + 1;
    final String updated =
        text.substring(0, lineStart) + prefix + text.substring(lineStart);
    _applyEdit(updated, selection.start + prefix.length,
        selection.end + prefix.length);
  }

  /// Applies a change that came from a toolbar button rather than the keyboard.
  ///
  /// Assigning to the controller does **not** fire `onChanged`, so without the
  /// explicit call to the autosave the button would change the text on screen and
  /// never write it to disk.
  void _applyEdit(String text, int selectionStart, int selectionEnd) {
    _field.value = TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: selectionStart,
        extentOffset: selectionEnd,
      ),
    );
    _editor.onChanged(text);
  }

  /// Ticks or unticks a task box when the tap landed on one.
  ///
  /// The box is painted text rather than a widget, so there is nothing to attach a
  /// gesture to: instead the tap places the caret, and a caret that lands on a box means
  /// the box is what was tapped. The caret is only correct once the tap has been fully
  /// handled, hence the frame callback.
  void _onFieldTapped() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_field.selection.isValid) return;
      final int offset = _field.selection.baseOffset;
      final int? mark = taskBoxIndexAt(_field.text, offset);
      if (mark == null) return;
      _applyEdit(toggleTaskAt(_field.text, mark), offset, offset);
    });
  }

  /// Leaves editing: the keyboard goes, the caret goes, and the note is written.
  ///
  /// Called by the tick in the top bar. Unfocusing is the only thing that actually removes
  /// the caret - putting the keyboard away with its own button leaves the field focused, so
  /// the caret carried on blinking over the text while reading.
  void _finishEditing() {
    unawaited(_commitTitle());
    _focus.unfocus();
    _titleFocus.unfocus();
    unawaited(_editor.flush());
  }

  Future<void> _showMoreMenu(BuildContext anchorContext) async {
    final RenderBox overlay =
        Navigator.of(anchorContext).overlay!.context.findRenderObject()!
            as RenderBox;
    final RenderBox anchor = anchorContext.findRenderObject()! as RenderBox;
    final Offset topLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
    final String? choice = await showMenu<String>(
      context: anchorContext,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy + anchor.size.height,
        overlay.size.width - topLeft.dx - anchor.size.width,
        0,
      ),
      items: const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'plain',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.content_copy),
            title: Text(NotesStrings.copyAsPlainText),
          ),
        ),
        PopupMenuItem<String>(
          value: 'markdown',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.code),
            title: Text(NotesStrings.copyAsMarkdown),
          ),
        ),
      ],
    );
    if (choice == 'plain') {
      await Clipboard.setData(
        ClipboardData(text: markdownToPlainText(_field.text)),
      );
      _toast(NotesStrings.copiedPlain);
    }
    if (choice == 'markdown') {
      await Clipboard.setData(ClipboardData(text: _field.text));
      _toast(NotesStrings.copiedMarkdown);
    }
  }

  // --- the page -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final NotesPalette palette = NotesPalette.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) =>
          _handlePop(didPop),
      child: Scaffold(
        backgroundColor: palette.page,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              _header(palette),
              Expanded(child: _body()),
              _toolbar(palette),
            ],
          ),
        ),
      ),
    );
  }

  /// The icon row, the status line, the title and the hairline under it.
  Widget _header(NotesPalette palette) {
    return Column(
      children: <Widget>[
        SizedBox(
          height: NotesEditorMetrics.barRowHeight,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double middle = constraints.maxWidth / 2;
              return Stack(
                children: <Widget>[
                  _EditorBarIcon(
                    icon: Icons.arrow_back,
                    centerX: NotesEditorMetrics.backCenterX,
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: NotesStrings.back,
                  ),
                  _EditorBarIcon(
                    icon: Icons.undo,
                    centerX: middle + NotesEditorMetrics.undoOffset,
                    onPressed: _history.value.canUndo ? _history.undo : null,
                    tooltip: NotesStrings.undo,
                  ),
                  _EditorBarIcon(
                    icon: Icons.redo,
                    centerX: middle + NotesEditorMetrics.redoOffset,
                    onPressed: _history.value.canRedo ? _history.redo : null,
                    tooltip: NotesStrings.redo,
                  ),
                  // The tick is only on screen while the keyboard is: its whole job is to
                  // put the caret away, so it disappears along with the caret and comes
                  // back the next time the note is being written in.
                  if (_focus.hasFocus)
                    _EditorBarIcon(
                      icon: Icons.check,
                      rightInset: NotesEditorMetrics.doneInset,
                      onPressed: _finishEditing,
                      tooltip: NotesStrings.finishEditing,
                    ),
                  Builder(
                    builder: (BuildContext iconContext) => _EditorBarIcon(
                      icon: Icons.more_vert,
                      rightInset: NotesEditorMetrics.moreInset,
                      onPressed: () => _showMoreMenu(iconContext),
                      tooltip: NotesStrings.moreActions,
                    ),
                  ),
                  Positioned(
                    left: NotesEditorMetrics.sideInset,
                    right: NotesEditorMetrics.sideInset,
                    top: NotesEditorMetrics.statusCenterY - 9,
                    height: 18,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        _saveLabel,
                        style: TextStyle(
                          fontSize: NotesEditorMetrics.statusFontSize,
                          height: 1.2,
                          color: palette.sub,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // The title *is* the file name (HANDOFF_PHASE4 section 13.4), so this field renames
        // the note rather than editing its text. It folds away as the note is read, leaving
        // behind only the little chevron that brings it back.
        _titleArea(palette),
      ],
    );
  }

  Widget _titleArea(NotesPalette palette) {
    final Widget toggle = _TitleToggle(
      collapsed: _titleCollapsed,
      onPressed: _toggleTitle,
    );
    return AnimatedSize(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: _titleCollapsed
          ? SizedBox(
              height: NotesEditorMetrics.titleCollapsedHeight,
              child: Padding(
                padding: const EdgeInsets.only(
                  right: NotesEditorMetrics.sideInset - 18,
                ),
                child: Align(alignment: Alignment.centerRight, child: toggle),
              ),
            )
          : Column(
              children: <Widget>[
                SizedBox(
                  height: NotesEditorMetrics.titleHeight,
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: NotesEditorMetrics.sideInset,
                          ),
                          child: TextField(
                            controller: _titleField,
                            focusNode: _titleFocus,
                            maxLines: 1,
                            textAlignVertical: TextAlignVertical.center,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (String _) => _titleFocus.unfocus(),
                            style: TextStyle(
                              fontSize: NotesEditorMetrics.titleFontSize,
                              fontWeight: NotesType.emphasis,
                              color: palette.ink,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(
                          right: NotesEditorMetrics.sideInset - 18,
                        ),
                        child: toggle,
                      ),
                    ],
                  ),
                ),
                // No hairline under the title: the user asked for it to be removed, so the
                // size and weight of the title are the only thing setting it apart.
                const SizedBox(height: NotesEditorMetrics.bodyGap),
              ],
            ),
    );
  }

  Widget _body() {
    final NotesPalette palette = NotesPalette.of(context);
    if (_editor.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_editor.loadFailed) {
      return LoadFailedView(message: _editor.error ?? '', onRetry: _retryLoad);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NotesEditorMetrics.bodyLeft,
      ),
      child: TextField(
        controller: _field,
        focusNode: _focus,
        scrollController: _bodyScroll,
        undoController: _history,
        onChanged: _editor.onChanged,
        onTap: _onFieldTapped,
        // No `autofocus`: the user asked for the note to open showing its beginning, with
        // the keyboard waiting until they tap where they want to write (option C).
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        cursorColor: palette.amber,
        cursorWidth: NotesEditorMetrics.cursorWidth,
        // No `inputFormatters` and no smart lists on purpose: the user was explicit
        // that nothing may rewrite what they type (HANDOFF_PHASE3 section 5.5).
        style: TextStyle(
          fontSize: NotesEditorMetrics.bodyFontSize,
          height: NotesEditorMetrics.bodyLineHeight,
          fontWeight: NotesType.body,
          color: palette.ink,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          // Deliberately no hint text: an empty note should be empty, not covered in grey
          // instructions the user did not type and has to delete.
        ),
      ),
    );
  }

  Widget _toolbar(NotesPalette palette) {
    final bool expanded = _toolbarExpanded;
    return Container(
      height: expanded
          ? NotesEditorMetrics.toolbarExpanded
          : NotesEditorMetrics.toolbarCollapsed,
      color: palette.toolbar,
      child: Column(
        children: <Widget>[
          const FadingDivider(
            left: NotesEditorMetrics.hairlineInset,
            right: NotesEditorMetrics.hairlineInset,
          ),
          Expanded(
            child: expanded
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: <Widget>[
                      _ToolButton(
                        label: 'Aa',
                        tooltip: NotesStrings.toolTextStyle,
                        onPressed: _openFormatPanel,
                      ),
                      _ToolButton(
                        label: 'B',
                        bold: true,
                        tooltip: NotesStrings.toolBold,
                        onPressed: () => _wrapSelection('**'),
                      ),
                      _ToolButton(
                        label: 'I',
                        italic: true,
                        tooltip: NotesStrings.toolItalic,
                        onPressed: () => _wrapSelection('*'),
                      ),
                      _ToolButton(
                        label: '#',
                        tooltip: NotesStrings.toolHeading,
                        onPressed: () => _prefixLine('# '),
                      ),
                      _ToolButton(
                        icon: Icons.check_circle_outline,
                        tooltip: NotesStrings.toolCheckbox,
                        onPressed: () => _prefixLine('- [ ] '),
                      ),
                      _ToolButton(
                        icon: Icons.tune,
                        tooltip: NotesStrings.toolTextStyle,
                        onPressed: _openFormatPanel,
                      ),
                      _ToolButton(
                        icon: Icons.keyboard_arrow_down,
                        tooltip: NotesStrings.toolbarCollapse,
                        onPressed: _toggleToolbar,
                      ),
                    ],
                  )
                // Collapsed leaves only the handle, and the mock-up centres it.
                : Center(
                    child: _ToolButton(
                      icon: Icons.keyboard_arrow_up,
                      tooltip: NotesStrings.toolbarExpand,
                      onPressed: _toggleToolbar,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _toggleToolbar() {
    setState(() => _toolbarExpanded = !_toolbarExpanded);
  }

  void _openFormatPanel() {
    _toast(NotesStrings.formatPanelPending);
  }
}

/// The small chevron that folds the title away and brings it back.
class _TitleToggle extends StatelessWidget {
  const _TitleToggle({required this.collapsed, required this.onPressed});

  static const double size = 36;

  final bool collapsed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final NotesPalette palette = NotesPalette.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        onPressed: onPressed,
        tooltip: collapsed
            ? NotesStrings.titleExpand
            : NotesStrings.titleCollapse,
        iconSize: 18,
        padding: EdgeInsets.zero,
        // Points the way the title will move: up to fold it away, down to bring it back.
        icon: Icon(
          collapsed ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
          color: palette.sub,
        ),
      ),
    );
  }
}

/// An icon in the editor's top bar, placed by its centre point.
class _EditorBarIcon extends StatelessWidget {
  const _EditorBarIcon({
    required this.icon,
    this.centerX,
    this.rightInset,
    required this.onPressed,
    required this.tooltip,
  }) : assert(centerX != null || rightInset != null,
            'give either a centre or a right inset');

  static const double size = 44;

  final IconData icon;

  /// Centre, measured from the left edge. Null when [rightInset] is used.
  final double? centerX;

  /// Centre, measured from the right edge.
  final double? rightInset;

  /// Null greys the icon out - which is how undo and redo show they have nothing
  /// left to do.
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final NotesPalette palette = NotesPalette.of(context);
    return Positioned(
      left: centerX == null ? null : centerX! - size / 2,
      right: rightInset == null ? null : rightInset! - size / 2,
      top: NotesEditorMetrics.iconCenterY - size / 2,
      child: SizedBox(
        width: size,
        height: size,
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          iconSize: 24,
          padding: EdgeInsets.zero,
          icon: Icon(
            icon,
            color: onPressed == null ? NotesColors.disabled : palette.ink,
          ),
        ),
      ),
    );
  }
}

/// One button in the editor's bottom toolbar: either a letter (`Aa`, `B`, `I`, `#`)
/// or an icon.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    this.label,
    this.icon,
    this.bold = false,
    this.italic = false,
    required this.tooltip,
    required this.onPressed,
  }) : assert(label != null || icon != null, 'give a label or an icon');

  final String? label;
  final IconData? icon;
  final bool bold;
  final bool italic;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final NotesPalette palette = NotesPalette.of(context);
    return SizedBox(
      width: NotesEditorMetrics.toolbarButtonSize,
      height: NotesEditorMetrics.toolbarButtonSize,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        icon: icon != null
            ? Icon(
                icon,
                size: NotesEditorMetrics.toolbarIconSize,
                color: palette.ink,
              )
            : Text(
                label!,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                  color: palette.ink,
                ),
              ),
      ),
    );
  }
}
