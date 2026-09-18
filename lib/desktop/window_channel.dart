import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The `notes_app/window` channel: what the app has to ask the platform for now that it draws
/// its own title bar.
///
/// Removing the OS title bar removes the behaviour that came with it, and only the Dart side
/// knows where its own buttons and its drag area are, so the asking goes this way. Everything
/// that can stay with Windows does: a drag is handed over with `WM_NCLBUTTONDOWN`/`HTCAPTION`,
/// so moving, snapping to a screen edge and double-click-to-maximise are still the OS's own,
/// not a reimplementation. See `windows/runner/win32_window.cpp`.
///
/// Every call is a no-op where there is no such channel (Android, and tests), because a window
/// that cannot be moved is a far smaller problem than an app that will not start.
abstract final class NotesWindow {
  static const MethodChannel _channel = MethodChannel('notes_app/window');

  /// Whether the window is maximised.
  ///
  /// Windows' own button knows this by itself; a drawn one has to be told, so the platform
  /// side pushes every change over the same channel.
  static final ValueNotifier<bool> maximized = ValueNotifier<bool>(false);

  static bool _listening = false;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'maximizedChanged') {
        maximized.value = call.arguments == true;
      }
      return null;
    });
  }

  static Future<void> minimize() => _invoke('minimize');
  static Future<void> toggleMaximize() => _invoke('toggleMaximize');
  static Future<void> close() => _invoke('close');

  /// Starts a window move. Called when the pointer goes down on the app's own title bar.
  static Future<void> startDrag() => _invoke('startDrag');

  static Future<void> _invoke(String method) async {
    _listen();
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException {
      // Nothing useful to do: the window simply stays where it is.
    } on MissingPluginException {
      // Not Windows. The page is still usable; it just cannot be moved by this bar.
    }
  }
}
