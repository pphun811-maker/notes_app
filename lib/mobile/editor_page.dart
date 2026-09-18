import 'dart:io';

import 'package:flutter/material.dart';

import '../desktop/editor_page.dart' as desktop;
import '../notes_store.dart';

/// The Android editor.
///
/// **Not written yet.** The editor is the next piece of work and is specified by
/// `design/final/ed4_expand.png`, `ed4_collapse.png` and `ed4_format.png`
/// (HANDOFF_PHASE3 sections 5.5 and 5.6). Until it lands, this delegates to the
/// phase-2 editor so tapping a note still opens and autosaves it - the list page
/// must never be a dead end.
///
/// The three data-loss risks that used to live in that phase-2 editor (HANDOFF_PHASE3
/// section 10.1) are fixed. The rules that fix them are in [NoteEditorController], and
/// the real Android editor must drive that same controller rather than growing its own
/// copy of the saving logic.
class EditorPage extends StatelessWidget {
  const EditorPage({super.key, required this.store, required this.file});

  final NotesStore store;
  final File file;

  @override
  Widget build(BuildContext context) {
    return desktop.EditorPage(store: store, file: file);
  }
}
