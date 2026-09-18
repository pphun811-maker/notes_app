import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design.dart';
import '../load_failed_view.dart';
import '../markdown_text.dart';
import '../note_editor_controller.dart';
import '../notes_store.dart';
import '../strings.dart';
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
/// * the format panel (font size, and the rest of the rows in `ed4_format.png`);
/// * rendering the Markdown while typing - the body is still the raw text.
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

  final TextEditingController _field = TextEditingController();
  final UndoHistoryController _history = UndoHistoryController();

  bool _toolbarExpanded = true;
  String? _shownError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _editor.addListener(_onEditorChanged);
    // The undo/redo buttons are enabled or greyed out from this controller's value.
    _history.addListener(_onHistoryChanged);
    unawaited(_reload());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _editor.removeListener(_onEditorChanged);
    _history.removeListener(_onHistoryChanged);
    _history.dispose();
    _field.dispose();
    _editor.dispose();
    super.dispose();
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
  }

  Future<void> _retryLoad() async {
    await _editor.retryLoad();
    _syncField();
  }

  void _syncField() {
    if (!mounted || _field.text == _editor.text) return;
    _field.value = TextEditingValue(
      text: _editor.text,
      selection: TextSelection.collapsed(offset: _editor.text.length),
    );
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
              _topArea(palette),
              Expanded(child: _body()),
              _toolbar(palette),
            ],
          ),
        ),
      ),
    );
  }

  /// The icon row, the status line and the hairline under it.
  Widget _topArea(NotesPalette palette) {
    return SizedBox(
      height: NotesEditorMetrics.bodyTop,
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
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        Note.fileNameWithoutExtension(widget.file),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: NotesEditorMetrics.statusFontSize,
                          height: 1.2,
                          color: palette.sub,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _saveLabel,
                      style: TextStyle(
                        fontSize: NotesEditorMetrics.statusFontSize,
                        height: 1.2,
                        color: palette.sub,
                      ),
                    ),
                  ],
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                top: NotesEditorMetrics.hairlineY,
                child: FadingDivider(
                  left: NotesEditorMetrics.hairlineInset,
                  right: NotesEditorMetrics.hairlineInset,
                ),
              ),
            ],
          );
        },
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
        undoController: _history,
        onChanged: _editor.onChanged,
        autofocus: true,
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
          color: palette.ink,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          hintText: NotesStrings.editorHint,
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
                        icon: Icons.check_box_outlined,
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
