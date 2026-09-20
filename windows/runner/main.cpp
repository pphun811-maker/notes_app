#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

namespace {

// The window class the runner registers (see win32_window.cpp). Spelled out a second time
// because that file keeps the name to itself; if it is ever renamed, this is the place to
// follow.
constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

// Names the flag that says "a copy is already running".
//
// A named mutex lives in the kernel rather than in a file, so every process on the machine can
// ask whether the name is taken, and the kernel drops it the moment the last handle closes.
// That last part is what makes it the right tool here: a copy that was killed instead of closed
// leaves nothing behind, so the next launch starts normally.
//
// `Local\` scopes the name to this logged-in session. `Global\` would not: creating objects in
// the global namespace needs a privilege ordinary accounts do not have, so it would fail to
// start the app at all for them.
constexpr const wchar_t kSingleInstanceMutexName[] =
    L"Local\\Notes_SingleInstance";

// Shows and focuses the copy of the window that is already open.
//
// `SetForegroundWindow` is refused unless Windows agrees that the caller may take the
// foreground, and a process that was just started is not always on that list - the click that
// started it went to the shell. Attaching to the current foreground thread's input queue is
// the documented way round it: while the two threads are attached they share the right to set
// the foreground window. Bringing the window to the top of the Z order is the last resort, and
// still activates it.
void BringToFront(HWND window) {
  if (::IsIconic(window)) {
    ::ShowWindow(window, SW_RESTORE);
  }
  if (::SetForegroundWindow(window)) {
    return;
  }

  const HWND foreground = ::GetForegroundWindow();
  const DWORD foreground_thread =
      foreground ? ::GetWindowThreadProcessId(foreground, nullptr) : 0;
  const DWORD this_thread = ::GetCurrentThreadId();
  if (foreground_thread != 0 && foreground_thread != this_thread &&
      ::AttachThreadInput(this_thread, foreground_thread, TRUE)) {
    ::SetForegroundWindow(window);
    ::AttachThreadInput(this_thread, foreground_thread, FALSE);
    return;
  }

  ::BringWindowToTop(window);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Two copies of Notes must not run at once.
  //
  // Each copy holds its own picture of the note folder in memory and writes whole files back,
  // so two of them silently overwrite each other's edits - the same failure HANDOFF_PHASE7
  // section 2.7 chased down inside a single process. Double-clicking the icon twice is enough
  // to make it happen, so the second copy hands the launch over to the first and leaves.
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    ::CloseHandle(instance_mutex);
    HWND existing = ::FindWindowW(kWindowClassName, nullptr);
    if (existing != nullptr) {
      BringToFront(existing);
    }
    return EXIT_SUCCESS;
  }

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

  if (instance_mutex != nullptr) {
    ::CloseHandle(instance_mutex);
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
