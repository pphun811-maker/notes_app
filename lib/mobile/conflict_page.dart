import 'dart:io';

import 'package:flutter/material.dart';

import '../design.dart';
import '../format.dart';
import '../notes_store.dart';
import '../strings.dart';
import '../sync_conflict.dart';
import 'widgets.dart';

/// The screen that lists Syncthing's conflict copies.
///
/// Reached from the list page's banner or its ⋮ menu, and only ever opened deliberately: the
/// app never shows a copy's generated name as if it were a note. The page exists so that
/// hiding copies from the list cannot hide the *contents* - which is the whole point, because
/// a copy may hold the only version of what was typed on the other device.
///
/// **This page has never been designed.** Like the empty, error and permission states it is
/// built from the app's own palette and type scale rather than from a mock-up; see
/// HANDOFF_PHASE3 section 12 step 7. It reuses the list page's card and rows so that it reads
/// as the same app.
class ConflictCopiesPage extends StatefulWidget {
  const ConflictCopiesPage({super.key, required this.store});

  final NotesStore store;

  @override
  State<ConflictCopiesPage> createState() => _ConflictCopiesPageState();
}

class _ConflictCopiesPageState extends State<ConflictCopiesPage> {
  /// Null until the first listing lands, so the page can tell "not loaded yet" from "none".
  List<Note>? _copies;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<Note> copies = await widget.store.listConflictCopies();
    if (!mounted) return;
    setState(() => _copies = copies);
  }

  /// What to call a copy in the list: the note it belongs to, or the raw name when the file
  /// is not named the way Syncthing names them.
  String _labelOf(Note copy) {
    final String title = SyncConflict.originalTitle(copy.title);
    return title.isEmpty ? copy.title : title;
  }

  @override
  Widget build(BuildContext context) {
    final NotesPalette palette = NotesPalette.of(context);
    final List<Note>? copies = _copies;
    return Scaffold(
      backgroundColor: palette.page,
      body: ListView(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top,
          bottom: MediaQuery.paddingOf(context).bottom + 32,
        ),
        children: <Widget>[
          const _PageHeader(title: NotesStrings.conflicts),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NotesMetrics.headerLeft,
              4,
              NotesMetrics.headerLeft,
              18,
            ),
            child: Text(
              NotesStrings.conflictsExplain,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: palette.sub,
              ),
            ),
          ),
          if (copies == null)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: CircularProgressIndicator(color: palette.amber),
              ),
            )
          else if (copies.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  NotesStrings.conflictNone,
                  style: TextStyle(fontSize: 15, color: palette.sub),
                ),
              ),
            )
          else
            NoteCard(
              child: Padding(
                padding: const EdgeInsets.only(
                  top: NotesMetrics.cardPaddingTop,
                  bottom: NotesMetrics.cardPaddingBottom,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: copies.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const FadingDivider(
                    left: NotesMetrics.dividerInsetInCard,
                    right: NotesMetrics.dividerInsetInCard,
                  ),
                  itemBuilder: (BuildContext context, int index) {
                    final Note copy = copies[index];
                    return NoteRow(
                      title: _labelOf(copy),
                      subtitle: formatNoteSubtitle(copy.modified, ''),
                      onTap: () => _open(copy),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _open(Note copy) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ConflictCopyPage(store: widget.store, copy: copy),
      ),
    );
  }
}

/// One conflict copy, read-only.
///
/// Read-only on purpose: there is no "keep this one" button yet. Overwriting the note the
/// copy belongs to is the one action here that cannot be undone from inside the app, so the
/// first version of this screen shows the text and lets the user copy it out, and leaves the
/// decision to a text editor where they can see both versions.
class ConflictCopyPage extends StatefulWidget {
  const ConflictCopyPage({super.key, required this.store, required this.copy});

  final NotesStore store;
  final Note copy;

  @override
  State<ConflictCopyPage> createState() => _ConflictCopyPageState();
}

class _ConflictCopyPageState extends State<ConflictCopyPage> {
  String? _contents;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final String contents = await widget.store.read(widget.copy.file);
      if (!mounted) return;
      setState(() {
        _contents = contents;
        _error = null;
      });
    } on FileSystemException catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error.osError?.message ?? error.message,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final NotesPalette palette = NotesPalette.of(context);
    final String title = SyncConflict.originalTitle(widget.copy.title);
    return Scaffold(
      backgroundColor: palette.page,
      body: ListView(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top,
          bottom: MediaQuery.paddingOf(context).bottom + 32,
        ),
        children: <Widget>[
          _PageHeader(
            title: title.isEmpty ? NotesStrings.conflicts : title,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NotesMetrics.headerLeft,
              0,
              NotesMetrics.headerLeft,
              6,
            ),
            // The file's own name, extension and all. Everywhere else the app shows a note's
            // title without the `.md`, but this line exists so the user can find *this* file
            // in a file manager if they want to deal with it there, and that means the exact
            // name on disk.
            child: SelectableText(
              widget.copy.file.uri.pathSegments.last,
              style: TextStyle(fontSize: 12, color: palette.sub),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NotesMetrics.headerLeft,
              10,
              NotesMetrics.headerLeft,
              16,
            ),
            child: Text(
              NotesStrings.conflictsExplain,
              style: TextStyle(fontSize: 13, height: 1.6, color: palette.sub),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NotesMetrics.headerLeft,
              ),
              child: Text(
                '${NotesStrings.conflictUnreadable}：$_error',
                style: TextStyle(fontSize: 14, color: palette.sub),
              ),
            )
          else if (_contents == null)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: CircularProgressIndicator(color: palette.amber),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NotesMetrics.headerLeft,
              ),
              child: SelectableText(
                _contents!,
                style: TextStyle(
                  fontSize: NotesEditorMetrics.bodyFontSize,
                  height: NotesEditorMetrics.bodyLineHeight,
                  color: palette.ink,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The bar at the top of both conflict screens: a back arrow and a title.
///
/// The list page's bar is drawn to a mock-up, icon centres included; this page has no
/// mock-up, so it uses the same height and insets without pretending to be pixel-exact.
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final NotesPalette palette = NotesPalette.of(context);
    return SizedBox(
      height: NotesMetrics.barHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: NotesMetrics.headerLeft),
        child: Row(
          children: <Widget>[
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: NotesStrings.conflictBack,
              iconSize: 22,
              icon: Icon(Icons.arrow_back, color: palette.ink),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
