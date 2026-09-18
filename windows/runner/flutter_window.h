#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;
  void OnMaximizedChanged(bool maximized) override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // `notes_app/window`: the few things only the app can do now that it draws its own title
  // bar. The Dart side owns the buttons and the drag area, so it is the side that has to ask;
  // in return this channel tells it when the maximised state changes, which is what keeps the
  // drawn button showing the right glyph.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> window_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
