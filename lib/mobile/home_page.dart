import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design.dart';
import '../format.dart';
import '../notes_store.dart';
import '../settings.dart';
import '../strings.dart';
import 'app_menu.dart';
import 'conflict_page.dart';
import 'editor_page.dart';
import 'widgets.dart';

/// The Android list page, drawn to `design/final/v5_light.png`, `v5_dark.png`,
/// `v5_refresh.png` and `v4_select.png`.
///
/// It talks to the same [NotesStore] the desktop interface uses; the data layer is
/// untouched. What is new here is the look, plus the three refresh fixes the
/// handoff asked for along the way:
///
///  * refreshing no longer replaces the body with a full-screen spinner (bug #4),
///  * returning from the background no longer does either (bug #5),
///  * overlapping refreshes can no longer land out of order (bug #6).
class NotesHomePage extends StatefulWidget {
  const NotesHomePage({super.key, this.store});

  /// The data layer to read notes from.
  ///
  /// Defaults to the real notes folder. Tests inject a temporary folder instead,
  /// which is the only reason this is a parameter at all.
  final NotesStore? store;

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage>
    with WidgetsBindingObserver {
  late final NotesStore _store =
      widget.store ?? NotesStore(Directory(NotesStore.defaultDirectoryPath));
  final TextEditingController _searchController = TextEditingController();

  List<Note> _notes = <Note>[];

  /// Syncthing's conflict copies, which [NotesStore.listNotes] deliberately leaves out.
  ///
  /// Kept here only so the user can be told they exist: the banner below the top bar and the
  /// ⋮ menu entry both lead to [ConflictCopiesPage]. Nothing on this page ever renders a
  /// copy's generated name as if it were a note.
  List<Note> _conflicts = <Note>[];

  /// True only until the very first load finishes. Later loads never flip this, so
  /// the list stays on screen while it refreshes.
  bool _firstLoad = true;

  /// Set when a load fails, so the error replaces a stale list.
  String? _error;
  bool _hasAccess = true;

  /// Guards against two refreshes finishing out of order: only the newest wins.
  int _loadToken = 0;
  bool _loadInFlight = false;

  bool _searching = false;
  String _query = '';

  /// Non-null means multi-select mode is active.
  Set<String>? _selection;

  /// Notes whose deletion is being written to disk right now.
  final Set<String> _busyDeletes = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the "All files access" screen, or from the phone being locked:
    // re-check access and pick up whatever Syncthing has brought in. This must not
    // blank the list - see [_load].
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  /// Reloads the note list.
  ///
  /// The previous list stays on screen for the whole call. The phase-2 code set
  /// `_loading = true` up front, which swapped the body for a
  /// `CircularProgressIndicator` and made the screen flash on every refresh and
  /// every trip through the background.
  Future<void> _load() async {
    if (_loadInFlight) {
      // A load is already running and its result will be newer than anything we
      // could start now, so let it land rather than racing it.
      return;
    }
    _loadInFlight = true;
    final int token = ++_loadToken;
    try {
      final bool hasAccess = await NotesStore.hasStorageAccess();
      if (!mounted || token != _loadToken) return;
      if (!hasAccess) {
        setState(() {
          _hasAccess = false;
          _firstLoad = false;
          _notes = <Note>[];
          _conflicts = <Note>[];
          _selection = null;
        });
        return;
      }

      await _store.ensureDirectoryExists();
      final List<Note> notes = await _store.listNotes();
      final List<Note> conflicts = await _store.listConflictCopies();
      // Which notices the user has already swiped away lives in the settings file, so it has
      // to be read before the banner can decide whether it is still wanted.
      await appSettings.load();
      if (!mounted || token != _loadToken) return;
      setState(() {
        _hasAccess = true;
        _notes = notes;
        _conflicts = conflicts;
        _firstLoad = false;
        _error = null;
        // Drop selections whose note has gone (deleted here, or removed by Syncthing).
        final Set<String>? selection = _selection;
        if (selection != null) {
          final Set<String> live = notes.map((Note n) => n.file.path).toSet();
          selection.removeWhere((String path) => !live.contains(path));
          if (selection.isEmpty) _selection = null;
        }
      });
    } on FileSystemException catch (error) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _hasAccess = true;
        _firstLoad = false;
        _error = '无法打开笔记文件夹：${error.osError?.message ?? error.message}';
      });
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> _createNote() async {
    try {
      final File file = await _store.createNote();
      if (!mounted) return;
      await _openEditor(file);
    } on FileSystemException catch (error) {
      if (!mounted) return;
      _toast('新建失败：${error.osError?.message ?? error.message}');
    }
  }

  Future<void> _openEditor(File file) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => EditorPage(store: _store, file: file),
      ),
    );
    await _load();
  }

  Future<void> _openConflicts() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ConflictCopiesPage(store: _store),
      ),
    );
    await _load();
  }

  /// Whether the list should still be telling the user about conflict copies.
  ///
  /// The banner is a notice, not a fixture: once it is swiped away the copies it named stay
  /// quiet, and the ⋮ menu entry stays as the way back to them. Syncthing gives every copy a
  /// name carrying the moment it was made, so a newly conflicted note is never in the
  /// dismissed list and its notice is shown.
  bool get _showsConflictNotice => _conflicts.any(
        (Note note) =>
            !appSettings.isConflictDismissed(note.file.uri.pathSegments.last),
      );

  /// Puts the notice away for every copy currently in the folder.
  ///
  /// Deliberately synchronous: the store updates its in-memory list before its first `await`,
  /// and a `Dismissible` throws if the widget it dismissed is still in the tree on the next
  /// build. Writing the file is left to finish on its own.
  void _dismissConflictNotice() {
    setState(() {
      for (final Note note in _conflicts) {
        unawaited(appSettings.dismissConflict(note.file.uri.pathSegments.last));
      }
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // --- multi-select --------------------------------------------------------

  void _enterSelection(Note note) {
    setState(() {
      _searching = false;
      _searchController.clear();
      _query = '';
      _selection = <String>{note.file.path};
    });
  }

  void _toggleSelection(Note note) {
    setState(() {
      final Set<String> selection = _selection!;
      if (!selection.remove(note.file.path)) selection.add(note.file.path);
      if (selection.isEmpty) _selection = null;
    });
  }

  /// Ticks every visible note.
  ///
  /// Deliberately a one-way action: the bar shows 全选/取消全选 by state, and the
  /// two must mean exactly what they say. Deriving "toggle" from
  /// `selection.length == visible.length` was wrong whenever the selection had
  /// been narrowed by a search.
  void _selectAll() {
    final List<Note> visible = _visibleNotes;
    if (visible.isEmpty) return;
    setState(() {
      _selection = visible.map((Note n) => n.file.path).toSet();
    });
  }

  void _clearSelection() {
    setState(() => _selection = null);
  }

  Future<void> _confirmDeleteSelected() async {
    final Set<String> selection = _selection ?? <String>{};
    if (selection.isEmpty) return;

    final List<Note> targets = _notes
        .where((Note n) => selection.contains(n.file.path))
        .toList(growable: false);
    if (targets.isEmpty) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(
          targets.length == 1
              ? NotesStrings.confirmDeleteOne
              : NotesStrings.confirmDeleteMany(targets.length),
        ),
        content: Text(
          NotesStrings.deleteWarning(
            targets.map((Note n) => n.title).join('、'),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(NotesStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              NotesStrings.delete,
              style: TextStyle(color: NotesColors.red, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyDeletes.addAll(selection));

    int deleted = 0;
    final List<String> failed = <String>[];
    for (final Note note in targets) {
      try {
        await _store.delete(note);
        deleted++;
      } on FileSystemException {
        // Leave it ticked so the user can try again.
        failed.add(note.title);
      }
    }

    if (!mounted) return;
    setState(() {
      _busyDeletes.removeAll(selection);
      _selection = null;
      if (failed.isEmpty) {
        _notes = _notes
            .where((Note n) => !selection.contains(n.file.path))
            .toList(growable: false);
      }
    });

    _toast(
      failed.isEmpty
          ? (deleted == 1
              ? NotesStrings.deletedOne
              : NotesStrings.deletedMany(deleted))
          : '${NotesStrings.deleteFailed}：${failed.join('、')}',
    );
    // Re-read from disk so the list matches reality either way.
    await _load();
  }

  // --- search --------------------------------------------------------------

  void _openSearch() {
    setState(() {
      _selection = null;
      _searching = true;
    });
  }

  void _closeSearch() {
    setState(() {
      _searching = false;
      _searchController.clear();
      _query = '';
    });
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

  // --- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final NotesPalette palette = NotesPalette.of(context);
    // Match the system bars to the page so there is no seam at the top or bottom.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            palette.isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness:
            palette.isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: palette.page,
        systemNavigationBarIconBrightness:
            palette.isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: palette.page,
        body: _buildBody(palette),
      ),
    );
  }

  Widget _buildBody(NotesPalette palette) {
    if (!_hasAccess) {
      return _PermissionPrompt(onGranted: _load);
    }
    if (_firstLoad) {
      return Center(child: CircularProgressIndicator(color: palette.amber));
    }

    final List<Note> notes = _visibleNotes;
    final Set<String>? selection = _selection;
    final EdgeInsets insets = MediaQuery.paddingOf(context);
    final double safeBottom = insets.bottom;

    return Stack(
      children: <Widget>[
        RefreshIndicator(
          onRefresh: _load,
          color: palette.amber,
          backgroundColor: palette.card,
          child: ListView(
            padding: EdgeInsets.only(
              top: insets.top,
              bottom: safeBottom + 32,
            ),
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              if (selection != null)
                _SelectionTopBar(
                  count: selection.length,
                  allSelected:
                      notes.isNotEmpty && selection.length == notes.length,
                  canDelete: selection.isNotEmpty,
                  busy: _busyDeletes.isNotEmpty,
                  onClose: () => setState(() => _selection = null),
                  onSelectAll: _selectAll,
                  onClearSelection: _clearSelection,
                  onDelete: _confirmDeleteSelected,
                )
              else if (_searching)
                _SearchBar(
                  controller: _searchController,
                  onChanged: (String value) => setState(() => _query = value),
                  onClose: _closeSearch,
                )
              else
                _Header(
                  key: const ValueKey<String>('notes-header'),
                  count: _notes.length,
                  conflictCount: _conflicts.length,
                  onCreate: _createNote,
                  onSearch: _openSearch,
                  onRescan: _load,
                  onSelect: () => setState(() => _selection = <String>{}),
                  onConflicts: _openConflicts,
                ),
              if (selection == null && !_searching && _showsConflictNotice)
                _ConflictBanner(
                  count: _conflicts.length,
                  onTap: _openConflicts,
                  onDismiss: _dismissConflictNotice,
                ),
              _buildContent(notes, selection, palette),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent(
    List<Note> notes,
    Set<String>? selection,
    NotesPalette palette,
  ) {
    if (_error != null) {
      return _CenteredMessage(
        icon: Icons.folder_off_outlined,
        title: NotesStrings.errorTitle,
        detail: '$_error\n\n文件夹：${_store.directory.path}',
        palette: palette,
      );
    }
    if (notes.isEmpty) {
      return _CenteredMessage(
        icon: _searching ? Icons.search_off : Icons.note_add_outlined,
        title: _searching ? '没有匹配的笔记' : NotesStrings.emptyTitle,
        detail: _searching
            ? '换个词试试。'
            : '${NotesStrings.emptyDetail}\n\n'
                '笔记就是这个文件夹里的 .md 文本文件：\n${_store.directory.path}',
        palette: palette,
      );
    }

    final bool selecting = selection != null;
    // The card hangs directly off the header, separated only by a small sliver of
    // page background.
    //
    // This is a gap, not an absolute position: applying an absolute `cardTop` here
    // double-counted the header (which already occupies the top of the scroll
    // content) and pushed the card a further header-height down - the dead band
    // under the top bar that the user rejected.
    return Padding(
      padding: const EdgeInsets.only(top: NotesMetrics.cardGap),
      child: NoteCard(
        child: Padding(
          padding: const EdgeInsets.only(
            top: NotesMetrics.cardPaddingTop,
            bottom: NotesMetrics.cardPaddingBottom,
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: notes.length,
            separatorBuilder: (BuildContext context, int index) =>
                const FadingDivider(
              left: NotesMetrics.dividerInsetInCard,
              right: NotesMetrics.dividerInsetInCard,
            ),
            itemBuilder: (BuildContext context, int index) {
              final Note note = notes[index];
              return NoteRow(
                title: note.title,
                subtitle: formatNoteSubtitle(note.modified, note.preview),
                selected: selecting ? selection.contains(note.file.path) : null,
                onTap: selecting
                    ? () => _toggleSelection(note)
                    : () => _openEditor(note.file),
                onLongPress: selecting
                    ? () => _toggleSelection(note)
                    : () => _enterSelection(note),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The normal top bar: search and "more" on the right, then the big title.
class _Header extends StatelessWidget {
  const _Header({
    super.key,
    required this.count,
    required this.conflictCount,
    required this.onCreate,
    required this.onSearch,
    required this.onRescan,
    required this.onSelect,
    required this.onConflicts,
  });

  /// The bar is [NotesMetrics.barHeight] tall, which puts the icon centres 27dp
  /// below the top of the content area and the title's baseline just under them.
  final int count;

  /// How many Syncthing conflict copies are sitting in the folder.
  ///
  /// The menu entry only appears when this is above zero: an entry that opens an empty page
  /// is worse than no entry, and the copies are the kind of thing that is either there or
  /// not.
  final int conflictCount;

  final VoidCallback onCreate;
  final VoidCallback onSearch;
  final VoidCallback onRescan;
  final VoidCallback onSelect;
  final VoidCallback onConflicts;

  @override
  Widget build(BuildContext context) {
    final NotesPalette palette = NotesPalette.of(context);
    return SizedBox(
      height: NotesMetrics.barHeight + MediaQuery.paddingOf(context).top,
      child: Padding(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              left: NotesMetrics.headerLeft,
              top: NotesMetrics.titleTop,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    NotesStrings.listTitle,
                    style: TextStyle(
                      fontSize: NotesMetrics.titleSize,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    NotesStrings.noteCount(count),
                    style: TextStyle(
                      fontSize: NotesMetrics.countSize,
                      color: palette.sub,
                    ),
                  ),
                ],
              ),
            ),
            BarIcon(
              icon: Icons.add,
              centerY: NotesMetrics.barIconCenterY,
              inset: NotesMetrics.newNoteIconInset,
              tooltip: NotesStrings.newNote,
              onPressed: onCreate,
            ),
            BarIcon(
              icon: Icons.search,
              centerY: NotesMetrics.barIconCenterY,
              inset: NotesMetrics.searchIconInset,
              tooltip: NotesStrings.searchHint,
              onPressed: onSearch,
            ),
            Builder(
              builder: (BuildContext iconContext) => BarIcon(
                icon: Icons.more_horiz,
                centerY: NotesMetrics.barIconCenterY,
                inset: NotesMetrics.moreIconInset,
                tooltip: '更多',
                onPressed: () => _showMoreMenu(
                  iconContext,
                  onRescan,
                  onSelect,
                  conflictCount,
                  onConflicts,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMoreMenu(
    BuildContext context,
    VoidCallback onRescan,
    VoidCallback onSelect,
    int conflictCount,
    VoidCallback onConflicts,
  ) async {
    final String? choice = await showAppMenu(context, <AppMenuItem>[
      const AppMenuItem(
        value: 'rescan',
        label: NotesStrings.rescan,
        icon: Icons.refresh,
      ),
      if (conflictCount > 0)
        AppMenuItem(
          value: 'conflicts',
          label: NotesStrings.conflictsMenu(conflictCount),
          icon: Icons.call_split,
        ),
      const AppMenuItem(
        value: 'select',
        label: NotesStrings.selectMode,
        icon: Icons.checklist,
      ),
    ]);
    if (choice == 'rescan') onRescan();
    if (choice == 'conflicts') onConflicts();
    if (choice == 'select') onSelect();
  }
}

/// The strip that says Syncthing has left conflict copies behind.
///
/// It sits in the page background between the top bar and the card, so it reads as a notice
/// about the list rather than as another note. Swiping it left puts it away for good - the
/// copies themselves stay, and the ⋮ menu entry is still there, which is why dismissing the
/// notice cannot lose anything. It has no close button: the swipe is the whole gesture, and
/// the banner disappears as it is dragged.
class _ConflictBanner extends StatelessWidget {
  const _ConflictBanner({
    required this.count,
    required this.onTap,
    required this.onDismiss,
  });

  final int count;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final NotesPalette palette = NotesPalette.of(context);
    final BorderRadius radius =
        BorderRadius.circular(NotesMetrics.cardRadius);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NotesMetrics.cardMargin,
        10,
        NotesMetrics.cardMargin,
        0,
      ),
      child: Dismissible(
        key: const ValueKey<String>('conflict-notice'),
        direction: DismissDirection.endToStart,
        onDismissed: (DismissDirection _) => onDismiss(),
        background: Container(
          decoration: BoxDecoration(
            color: NotesColors.red,
            borderRadius: radius,
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 18),
          child: const Icon(
            Icons.delete_outline,
            size: 22,
            color: Colors.white,
          ),
        ),
        child: Material(
          color: palette.chipSelected,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
              child: Row(
                children: <Widget>[
                  Icon(Icons.call_split, size: 20, color: palette.accentText),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      NotesStrings.conflictsFound(count),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: NotesType.emphasis,
                        color: palette.ink,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 20, color: palette.sub),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon pinned so its centre lands exactly on the designed point.
///
/// The mock-up positions these by centre (`x = W - 84, y = 48`), not by edge, so
/// the control is laid out around that point rather than padded towards it.
class BarIcon extends StatelessWidget {
  const BarIcon({
    super.key,
    required this.icon,
    required this.centerY,
    required this.inset,
    required this.onPressed,
    this.tooltip,
  });

  static const double size = 44;

  final IconData icon;
  final double centerY;
  final double inset;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: inset - size / 2,
      top: centerY - size / 2,
      child: SizedBox(
        width: size,
        height: size,
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          iconSize: 24,
          padding: EdgeInsets.zero,
          icon: Icon(icon, color: NotesPalette.of(context).ink),
        ),
      ),
    );
  }
}

/// The search field that replaces the header while searching.
///
/// The design only specifies the search *icon*; the field it opens is not in the
/// mock-ups, so this follows the page's own colours and radii.
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final NotesPalette palette = NotesPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 16,
        left: NotesMetrics.headerLeft,
        right: NotesMetrics.headerLeft,
        bottom: 16,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.search, size: 20, color: palette.sub),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      onChanged: onChanged,
                      autofocus: true,
                      style: TextStyle(fontSize: 15, color: palette.ink),
                      cursorColor: palette.amber,
                      cursorWidth: 1.5,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: NotesStrings.searchHint,
                        hintStyle: TextStyle(fontSize: 15, color: palette.sub),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              onPressed: onClose,
              iconSize: 24,
              padding: EdgeInsets.zero,
              tooltip: '关闭搜索',
              icon: Icon(Icons.close, color: palette.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// The top bar shown in multi-select mode.
class _SelectionTopBar extends StatelessWidget {
  const _SelectionTopBar({
    required this.count,
    required this.allSelected,
    required this.canDelete,
    required this.busy,
    required this.onClose,
    required this.onSelectAll,
    required this.onClearSelection,
    required this.onDelete,
  });

  static const double _barHeight = 96;
  static const double _tapSize = 44;

  /// "全选" sits to the left of the bin. Its tap target must not reach under the
  /// bin's 44dp target: the bin sits later in the `Stack`, so it wins any overlap
  /// and silently swallowed taps meant for 全选.
  ///
  /// On the 412dp design canvas the label's right edge lands at x = 334; on the
  /// narrower real screen the same 56dp lane on the right is all there is, so the
  /// label is right-aligned into it instead.
  static const double _selectAllButtonWidth = 76;
  static const double _selectAllRight = 56;

  final int count;
  final bool allSelected;
  final bool canDelete;
  final bool busy;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final NotesPalette palette = NotesPalette.of(context);
    return SizedBox(
      height: _barHeight + MediaQuery.paddingOf(context).top,
      child: Padding(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: Stack(
          children: <Widget>[
            Positioned(
              left: NotesMetrics.selectionCloseCenterX - _tapSize / 2,
              top: NotesMetrics.barIconCenterY - _tapSize / 2,
              child: _IconTap(
                icon: Icons.close,
                color: palette.ink,
                tooltip: '退出多选',
                onPressed: onClose,
              ),
            ),
            Positioned(
              left: NotesMetrics.selectionTitleLeft,
              height: NotesMetrics.barIconCenterY * 2,
              top: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  NotesStrings.selectedCount(count),
                  style: TextStyle(
                    fontSize: NotesMetrics.selectionTitleSize,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                  ),
                ),
              ),
            ),
            Positioned(
              right: _selectAllRight,
              top: NotesMetrics.barIconCenterY - _tapSize / 2,
              child: SizedBox(
                width: _selectAllButtonWidth,
                height: _tapSize,
                child: TextButton(
                  onPressed: allSelected ? onClearSelection : onSelectAll,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerRight,
                  ),
                  child: Text(
                    allSelected
                        ? NotesStrings.deselectAll
                        : NotesStrings.selectAll,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: NotesMetrics.selectAllSize,
                      fontWeight: FontWeight.w700,
                      color: palette.accentText,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: NotesMetrics.moreIconInset - _tapSize / 2,
              top: NotesMetrics.barIconCenterY - _tapSize / 2,
              child: _IconTap(
                icon: Icons.delete_outline,
                color: canDelete ? NotesColors.red : NotesColors.disabled,
                tooltip: NotesStrings.deleteSelected,
                onPressed: canDelete && !busy ? onDelete : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 44x44 tap target around a bare icon.
class _IconTap extends StatelessWidget {
  const _IconTap({
    required this.icon,
    required this.color,
    this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        iconSize: 24,
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: color),
      ),
    );
  }
}

/// The empty / error placeholder.
///
/// **This page has never been designed.** The mock-ups cover the list, the editor
/// and the format panel only, so this is a plain, low-risk treatment built from
/// the same palette and type scale. See HANDOFF_PHASE3 section 12, step 7.
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.detail,
    required this.palette,
  });

  final IconData icon;
  final String title;
  final String detail;
  final NotesPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 48, color: palette.sub),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.6, color: palette.sub),
          ),
        ],
      ),
    );
  }
}

/// Shown when Android has not granted access to the shared notes folder yet.
///
/// Never actually seen on this device - ColorOS grants it automatically - so it is
/// deliberately kept close to the phase-2 version rather than invented anew.
class _PermissionPrompt extends StatelessWidget {
  const _PermissionPrompt({required this.onGranted});

  final Future<void> Function() onGranted;

  @override
  Widget build(BuildContext context) {
    final NotesPalette palette = NotesPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.folder_shared_outlined, size: 56, color: palette.sub),
            const SizedBox(height: 16),
            Text(
              NotesStrings.permissionTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              NotesStrings.permissionDetail,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.6, color: palette.sub),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async {
                await NotesStore.requestStorageAccess();
              },
              style: FilledButton.styleFrom(backgroundColor: palette.amber),
              icon: const Icon(Icons.settings, color: Colors.white),
              label: const Text(
                NotesStrings.grantAccess,
                style: TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onGranted,
              child: Text(
                NotesStrings.recheckAccess,
                style: TextStyle(color: palette.accentText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
