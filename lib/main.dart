import 'package:flutter/material.dart';

import 'app.dart';

/// The app entry point.
///
/// The shell lives in `app.dart` (theme and the phone/desktop split), the shared
/// data layer in `notes_store.dart`, and the two interfaces in `mobile/` and
/// `desktop/`.
void main() {
  runApp(const NotesApp());
}
