import 'dart:io';

import 'package:flutter/material.dart';

import 'editor_page.dart';
import 'notes_store.dart';

void main() {
  runApp(const NotesApp());
}

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const NotesHomePage(),
    );
  }
}

/// Lists the notes in the notes folder and opens the editor.
class NotesHomePage extends StatefulWidget {
  const NotesHomePage({super.key});

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage>
    with WidgetsBindingObserver {
  final NotesStore _store =
      NotesStore(Directory(NotesStore.defaultDirectoryPath));

  List<Note> _notes = <Note>[];
  bool _loading = true;
  bool _hasAccess = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the "All files access" screen: re-check whether it was granted.
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    if (!await NotesStore.hasStorageAccess()) {
      if (!mounted) return;
      setState(() {
        _hasAccess = false;
        _loading = false;
        _notes = <Note>[];
      });
      return;
    }

    try {
      await _store.ensureDirectoryExists();
      final List<Note> notes = await _store.listNotes();
      if (!mounted) return;
      setState(() {
        _hasAccess = true;
        _notes = notes;
        _loading = false;
      });
    } on FileSystemException catch (error) {
      if (!mounted) return;
      setState(() {
        _hasAccess = true;
        _loading = false;
        _notes = <Note>[];
        _error = '无法打开笔记文件夹：${error.osError?.message ?? error.message}';
      });
    }
  }

  Future<void> _createNote() async {
    try {
      final File file = await _store.createNote();
      if (!mounted) return;
      await _openEditor(file);
    } on FileSystemException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('新建失败：${error.osError?.message ?? error.message}'),
        ),
      );
    }
  }

  Future<void> _openEditor(File file) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            EditorPage(store: _store, file: file),
      ),
    );
    await _refresh();
  }

  Future<void> _confirmDelete(Note note) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除这篇笔记？'),
        content: Text('“${note.title}”将被永久删除，无法撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _store.delete(note);
    } on FileSystemException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除失败：${error.osError?.message ?? error.message}'),
        ),
      );
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: <Widget>[
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: '重新扫描笔记文件夹',
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _hasAccess
          ? FloatingActionButton.extended(
              onPressed: _createNote,
              icon: const Icon(Icons.add),
              label: const Text('新建'),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (!_hasAccess) {
      return _PermissionPrompt(onGranted: _refresh);
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _CenteredMessage(
        icon: Icons.folder_off_outlined,
        title: '打不开笔记文件夹',
        detail: '$_error\n\n文件夹：${_store.directory.path}',
      );
    }
    if (_notes.isEmpty) {
      return _CenteredMessage(
        icon: Icons.note_add_outlined,
        title: '还没有笔记',
        detail: '点右下角的“新建”写第一篇。\n\n'
            '笔记就是这个文件夹里的 .md 文本文件：\n${_store.directory.path}',
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        itemCount: _notes.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) {
          final Note note = _notes[index];
          return ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(
              note.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              note.preview.isEmpty
                  ? _formatTime(note.modified)
                  : '${_formatTime(note.modified)} · ${note.preview}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _openEditor(note.file),
            onLongPress: () => _confirmDelete(note),
          );
        },
      ),
    );
  }

  static String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}

/// Shown when Android has not granted access to the shared notes folder yet.
class _PermissionPrompt extends StatelessWidget {
  const _PermissionPrompt({required this.onGranted});

  final Future<void> Function() onGranted;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.folder_shared_outlined, size: 56),
            const SizedBox(height: 16),
            Text(
              '需要“所有文件访问权限”',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              '笔记以普通文本文件的形式放在手机的共享文件夹里，'
              '这样 Syncthing 才能把它同步到电脑。\n\n'
              '请在弹出的设置页面里打开“允许管理所有文件”，然后返回本应用。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async {
                await NotesStore.requestStorageAccess();
              },
              icon: const Icon(Icons.settings),
              label: const Text('去授权'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onGranted,
              child: const Text('我已授权，重新检查'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 56),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
