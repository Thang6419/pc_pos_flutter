#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command)
{

  // ==========================================================================
  // 1. CHẶN PHẦN MỀM MỞ BẢN THỨ 2 (SINGLE INSTANCE)
  // ==========================================================================
  HANDLE hMutex = CreateMutexA(NULL, TRUE, "PC_POS_SINGLE_INSTANCE_MUTEX");

  if (GetLastError() == ERROR_ALREADY_EXISTS)
  {
    // Tìm cửa sổ của bản app đang chạy trước đó bằng Class Name mặc định của Flutter và Window Title "pc_pos"
    HWND hwnd = FindWindowA("FLUTTER_RUNNER_WIN32_WINDOW", "pc_pos");
    if (hwnd)
    {
      // Nếu app cũ đang bị thu nhỏ (Iconified/Minimized) thì khôi phục lại
      if (IsIconic(hwnd))
      {
        ShowWindow(hwnd, SW_RESTORE);
      }
      // Đẩy cửa sổ cũ lên trên cùng và focus vào nó
      SetForegroundWindow(hwnd);
      SetActiveWindow(hwnd);
    }

    // Đóng handle mutex của bản này và thoát luôn, không cho chạy tiếp xuống dưới
    if (hMutex)
      CloseHandle(hMutex);
    return 0;
  }
  // ==========================================================================

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent())
  {
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
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"pc_pos", origin, size))
  {
    if (hMutex)
      CloseHandle(hMutex); // Đóng hMutex nếu lỗi khởi tạo window
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0))
  {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();

  // 2. GIẢI PHÓNG MUTEX KHI ỨNG DỤNG ĐÓNG HOÀN TOÀN
  if (hMutex)
  {
    CloseHandle(hMutex);
  }

  return EXIT_SUCCESS;
}