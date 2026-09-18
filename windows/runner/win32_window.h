#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// A class abstraction for a high DPI-aware Win32 Window. Intended to be
// inherited from by classes that wish to specialize with custom
// rendering and input handling
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // Creates a win32 window with |title| that is positioned and sized using
  // |origin| and |size|. New windows are created on the default monitor. Window
  // sizes are specified to the OS in physical pixels, hence to ensure a
  // consistent size this function will scale the inputted width and height as
  // as appropriate for the default monitor. The window is invisible until
  // |Show| is called. Returns true if the window was created successfully.
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // Show the current window. Returns true if the window was successfully shown.
  bool Show();

  // Release OS resources associated with window.
  void Destroy();

  // Inserts |content| into the window tree.
  void SetChildContent(HWND content);

  // Returns the backing Window handle to enable clients to set icon and other
  // window properties. Returns nullptr if the window has been destroyed.
  HWND GetHandle();

  // If true, closing this window will quit the application.
  void SetQuitOnClose(bool quit_on_close);

  // Return a RECT representing the bounds of the current client area.
  RECT GetClientArea();

  // Makes the hosted Flutter view exactly as big as the client area.
  //
  // Called from every message that can change the window's size, and again from a slow timer,
  // because a view that is one resize behind is not a cosmetic problem: Flutter lays the whole
  // app out for the size it was last told, so a stale view shows a note list painted for a
  // smaller window, with the rest of the window left as whatever was on screen before.
  void SyncViewToClient();

  // The window draws its own title bar, so the OS one is removed (see WM_NCCALCSIZE) and the
  // behaviour it used to provide has to be asked for explicitly. These are called from the
  // `notes_app/window` channel by the Dart side, which is the only part that knows where its
  // own buttons and drag area are.
  void Minimize();
  void ToggleMaximize();
  void CloseWindow();
  bool IsWindowMaximized() const;

  // Hands the window to the OS for a caption drag: move, Aero snap and double-click-to-
  // maximise all come from the OS doing this, not from anything reimplemented here.
  void StartDrag();

 protected:
  // Processes and route salient window messages for mouse handling,
  // size change and DPI. Delegates handling of these to member overloads that
  // inheriting classes can handle.
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // Called when the window is maximised or restored, so the UI can redraw the button that
  // offers it. Windows' own button does this for free; a drawn one has to be told.
  virtual void OnMaximizedChanged(bool maximized) {}

  // Called when CreateAndShow is called, allowing subclass window-related
  // setup. Subclasses should return false if setup fails.
  virtual bool OnCreate();

  // Called when Destroy is called.
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // OS callback called by message pump. Handles the WM_NCCREATE message which
  // is passed when the non-client area is being created and enables automatic
  // non-client DPI scaling so that the non-client area automatically
  // responds to changes in DPI. All other messages are handled by
  // MessageHandler.
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // Retrieves a class instance pointer for |window|
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // Sits in front of the hosted child window's own procedure.
  //
  // The Flutter view is a child window covering the whole client area, so every mouse message
  // is delivered to *it*: Windows asks the child where the cursor is, the child answers
  // HTCLIENT, and the parent's WM_NCHITTEST never runs at all. Without this the resize borders
  // of a window with no non-client area would be invisible to the system, and the window could
  // be resized only by the maximise button.
  static LRESULT CALLBACK ChildWndProc(HWND child,
                                       UINT const message,
                                       WPARAM const wparam,
                                       LPARAM const lparam) noexcept;

  // Update the window frame's theme to match the system theme.
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;

  // window handle for top level window.
  HWND window_handle_ = nullptr;

  // window handle for hosted content.
  HWND child_content_ = nullptr;

  // The child's procedure before [ChildWndProc] took its place.
  WNDPROC child_original_proc_ = nullptr;

  // Id of the timer that re-checks the view's size. See SyncViewToClient.
  static constexpr UINT_PTR kViewSyncTimerId = 1;
};

#endif  // RUNNER_WIN32_WINDOW_H_
