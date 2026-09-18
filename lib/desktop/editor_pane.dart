import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../load_failed_view.dart';
import '../format.dart';
import '../markdown_controller.dart';
import '../markdown_span.dart';
import '../note_editor_controller.dart';
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

  late final MarkdownEditingController _body = MarkdownEditingController();

  final TextEditingController _title = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _bodyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _editor.addListener(_onEditorChanged);
    _titleFocus.addListener(_onTitleFocusChanged);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _editor.removeListener(_onEditorChanged);
    _titleFocus.removeListener(_onTitleFocusChanged);
    _titleFocus.dispose();
    _bodyFocus.dispose();
    _title.dispose();
    _body.dispose();
    _editor.dispose();
    super.dispose();
  }

  /// Writes whatever is pending. Called before the pane is replaced, and before the window
  /// closes, so a switch of notes can never lose the last keystrokes.
  Future<void> flush() => _editor.flush();

  /// Saves and waits for the file. Leaving is not allowed to race the write.
  Future<void> close() => _editor.close();

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
    return ColoredBox(
      color: p.surface,
      child: _body_(p),
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
                        formatNoteDate(widget.modified),
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
    final String state = _editor.error != null
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
            Text(
              state,
              style: TextStyle(fontSize: 12, color: p.faint),
            ),
            const Spacer(),
            Text(
              widget.file.path,
              style: TextStyle(fontSize: 12, color: p.faint),
            ),
          ],
        ),
      ),
    );
  }
}
