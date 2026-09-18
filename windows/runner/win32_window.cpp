#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>
#include <windowsx.h>

#include "resource.h"

namespace {

/// The window's own title bar is replaced by one the app draws.
///
/// Nothing about the window *styles* changes: `WS_OVERLAPPEDWINDOW` stays, and with it the
/// drop shadow, the rounded corners on Windows 11, Aero snap, Alt+Space, Alt+F4 and the
/// resize borders. What is removed is only the strip Windows would paint across the top,
/// which is done by claiming the whole window as client area in `WM_NCCALCSIZE`.
LRESULT RemoveStandardTitleBar(HWND window, WPARAM const wparam, LPARAM const lparam) {
  if (wparam != TRUE) {
    return DefWindowProc(window, WM_NCCALCSIZE, wparam, lparam);
  }
  auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
  if (IsZoomed(window)) {
    // A maximised window is sized to the monitor *plus* the frame, so its client area would
    // hang off every edge by the border width. Trim it back to the work area.
    const UINT dpi = GetDpiForWindow(window);
    const int frame = GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) +
                      GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
    params->rgrc[0].left += frame;
    params->rgrc[0].top += frame;
    params->rgrc[0].right -= frame;
    params->rgrc[0].bottom -= frame;
  }
  return 0;
}

/// Offers the resize borders, which Windows would otherwise have taken from the non-client
/// area that `RemoveStandardTitleBar` just removed.
LRESULT HitTestResizeBorders(HWND window, LPARAM const lparam) {
  if (IsZoomed(window)) {
    return HTCLIENT;
  }
  RECT rect;
  GetWindowRect(window, &rect);
  const UINT dpi = GetDpiForWindow(window);
  const int border = GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) +
                     GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
  const long x = GET_X_LPARAM(lparam);
  const long y = GET_Y_LPARAM(lparam);
  const bool left = x < rect.left + border;
  const bool right = x >= rect.right - border;
  const bool top = y < rect.top + border;
  const bool bottom = y >= rect.bottom - border;
  if (top && left) return HTTOPLEFT;
  if (top && right) return HTTOPRIGHT;
  if (bottom && left) return HTBOTTOMLEFT;
  if (bottom && right) return HTBOTTOMRIGHT;
  if (left) return HTLEFT;
  if (right) return HTRIGHT;
  if (top) return HTTOP;
  if (bottom) return HTBOTTOM;
  return HTCLIENT;
}

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  // Windows only offers WM_NCCALCSIZE with the "new frame" flag when a window is resized, so
  // one that has just been created keeps the frame it was born with - title bar and all -
  // until something moves it. Asking for the frame to be recalculated now is what makes the
  // very first frame the app draws already borderless.
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                   SWP_NOACTIVATE);

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_NCCALCSIZE:
      return RemoveStandardTitleBar(hwnd, wparam, lparam);

    case WM_NCHITTEST:
      return HitTestResizeBorders(hwnd, lparam);

    case WM_GETMINMAXINFO: {
      // Below this the sidebar and the note cannot both be shown, and the window would be
      // resizable into a state the layout has never been tested in.
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      const double scale = GetDpiForWindow(hwnd) / 96.0;
      info->ptMinTrackSize.x = static_cast<LONG>(880 * scale);
      info->ptMinTrackSize.y = static_cast<LONG>(560 * scale);
      return 0;
    }

    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      if (wparam == SIZE_MAXIMIZED || wparam == SIZE_RESTORED) {
        OnMaximizedChanged(wparam == SIZE_MAXIMIZED);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  // Take the child's hit testing over: see ChildWndProc.
  child_original_proc_ = reinterpret_cast<WNDPROC>(SetWindowLongPtr(
      content, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(ChildWndProc)));
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

// static
LRESULT CALLBACK Win32Window::ChildWndProc(HWND const child,
                                           UINT const message,
                                           WPARAM const wparam,
                                           LPARAM const lparam) noexcept {
  Win32Window* that = GetThisFromHandle(GetParent(child));
  if (that != nullptr && message == WM_NCHITTEST) {
    return HitTestResizeBorders(GetParent(child), lparam);
  }
  if (that != nullptr && that->child_original_proc_ != nullptr) {
    return CallWindowProc(that->child_original_proc_, child, message, wparam,
                          lparam);
  }
  return DefWindowProc(child, message, wparam, lparam);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

void Win32Window::Minimize() {
  ShowWindow(window_handle_, SW_MINIMIZE);
}

void Win32Window::ToggleMaximize() {
  ShowWindow(window_handle_, IsWindowMaximized() ? SW_RESTORE : SW_MAXIMIZE);
}

void Win32Window::CloseWindow() {
  PostMessage(window_handle_, WM_CLOSE, 0, 0);
}

bool Win32Window::IsWindowMaximized() const {
  return window_handle_ != nullptr && IsZoomed(window_handle_) != 0;
}

void Win32Window::StartDrag() {
  // The one recipe Windows gives for this: let go of the mouse capture this thread holds and
  // tell the window the user grabbed its caption. Everything a title bar normally does -
  // move, snap to a screen edge, double-click to maximise - then happens in the OS.
  ReleaseCapture();
  SendMessage(window_handle_, WM_NCLBUTTONDOWN, HTCAPTION, 0);
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
