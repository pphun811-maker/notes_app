#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);

  // The window opens centred and sized for the screen it is actually on.
  //
  // It used to open at a fixed 1280x720 in the top-left corner, which is a size that says
  // nothing about the display: on this machine the screen is 2560x1600, so the window covered
  // barely a quarter of it while sitting against the corner. `Create` scales these logical
  // numbers by the monitor's DPI, so the work area has to be brought back to logical pixels
  // before anything can be worked out from it.
  RECT work_area{};
  ::SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0);
  const double scale = ::GetDpiForSystem() / 96.0;
  const int work_width =
      static_cast<int>((work_area.right - work_area.left) / scale);
  const int work_height =
      static_cast<int>((work_area.bottom - work_area.top) / scale);

  Win32Window::Size size(
      static_cast<unsigned int>(std::clamp(work_width * 3 / 5, 760, 1180)),
      static_cast<unsigned int>(std::clamp(work_height * 4 / 5, 560, 880)));
  Win32Window::Point origin(
      static_cast<unsigned int>(work_area.left / scale +
                                (work_width - static_cast<int>(size.width)) / 2),
      static_cast<unsigned int>(work_area.top / scale +
                                (work_height - static_cast<int>(size.height)) / 2));

  if (!window.Create(L"Notes", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
