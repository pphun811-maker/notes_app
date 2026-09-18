import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../load_failed_view.dart';
import '../note_editor_controller.dart';
import '../notes_store.dart';
import '../strings.dart';

/// Edits a single note.
///
/// The note is saved automatically a moment after typing stops, and once more when the page is
/// closed, so there is no "save" button to forget.
///
/// This widget only draws the editor: the rules that keep the file in step with the text live in
/// [NoteEditorController], which the Android editor drives as well. The Android editor used to
/// forward to this page; it now has a UI of its own (`lib/mobile/editor_page.dart`) and shares
/// only the controller, so a change here no longer reaches Android - that is what the shared
/// controller is for.
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

  /// The last message shown in a snack bar, so a retry loop does not stack up
  /// dozens of identical ones.
  String? _shownError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _editor.addListener(_onEditorChanged);
    unawaited(_reload());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _editor.removeListener(_onEditorChanged);
    _field.dispose();
    _editor.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On Android this is the last moment the app is guaranteed to get: past it the
    // process can be killed without `dispose()` ever running, and the phase-2 editor
    // lost its final write in exactly that gap.
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

  /// Copies the controller's text into the field.
  ///
  /// Assigning the text programmatically does not fire `onChanged`, so this can
  /// never loop back into the controller.
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  /// Saves whatever is pending, and only then lets the page close.
  Future<void> _handlePop(bool didPop) async {
    if (didPop) return;
    await _editor.close();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // The page closes through this callback rather than on its own, so the last
      // keystrokes are on disk before the route goes away.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) => _handlePop(didPop),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            Note.fileNameWithoutExtension(widget.file),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_editor.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_editor.loadFailed) {
      return LoadFailedView(message: _editor.error ?? '', onRetry: _retryLoad);
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _field,
        onChanged: _editor.onChanged,
        autofocus: true,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: NotesStrings.editorHint,
        ),
        style: const TextStyle(fontSize: 16, height: 1.5),
      ),
    );
  }
}
