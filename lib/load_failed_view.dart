import 'dart:async';

import 'package:flutter/material.dart';

import 'strings.dart';

/// Shown instead of the editor when a note could not be read.
///
/// This is the fix for the worst of the three data-loss bugs: the phase-2 editor
/// showed an empty text field after a failed read, so the first keystroke replaced
/// the contents of a note it had never managed to read. Here the text is simply not
/// editable until the read succeeds.
///
/// Both editors show this, so it deliberately uses stock Material styling rather
/// than either page's palette. It has no mock-up - like the list page's empty and
/// error states, this screen was never designed.
class LoadFailedView extends StatelessWidget {
  const LoadFailedView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  /// The reason, already formatted - for example `读取失败：Permission denied`.
  final String message;

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              NotesStrings.loadFailedTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              NotesStrings.loadFailedDetail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => unawaited(onRetry()),
              child: const Text(NotesStrings.retryLoad),
            ),
          ],
        ),
      ),
    );
  }
}
