import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'notes_store.dart';

/// Edits a single note.
///
/// The note is saved automatically a moment after typing stops, and once more when the page is
/// closed, so there is no "save" button to forget.
class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.store, required this.file});

  final NotesStore store;
  final File file;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final TextEditingController _controller = TextEditingController();
  Timer? _saveTimer;
  bool _dirty = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_dirty) {
      // Best-effort final save: the page is being disposed, so the result cannot be shown here.
      widget.store.write(widget.file, _controller.text);
    }
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    String contents = '';
    try {
      contents = await widget.store.read(widget.file);
    } on FileSystemException catch (error) {
      _showMessage('读取失败：${error.osError?.message ?? error.message}');
    }
    if (!mounted) return;
    setState(() {
      _controller.text = contents;
      _loading = false;
    });
  }

  void _onChanged(String value) {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _save);
  }

  Future<void> _save() async {
    if (!_dirty) return;
    _dirty = false;
    try {
      await widget.store.write(widget.file, _controller.text);
    } on FileSystemException catch (error) {
      _showMessage('保存失败：${error.osError?.message ?? error.message}');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          Note.fileNameWithoutExtension(widget.file),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _controller,
                onChanged: _onChanged,
                autofocus: true,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '在这里写点什么……',
                ),
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
            ),
    );
  }
}
