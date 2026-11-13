#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

// One DropClip per user config folder: a second launch (shortcut, hotkey,
// login item) brings the running window forward and exits, instead of a
// second process with the same identity watching the same clipboard.
bool AlreadyRunning() {
  wchar_t appdata[MAX_PATH] = L"";
  ::GetEnvironmentVariableW(L"APPDATA", appdata, MAX_PATH);
  std::wstring name = L"Local\\DropClip-";
  for (const wchar_t* c = appdata; *c != L'\0'; ++c) {
    name += (*c == L'\\' || *c == L':') ? L'_' : *c;
  }
  // Intentionally never closed: the OS releases it when this process ends.
  ::CreateMutexW(nullptr, FALSE, name.c_str());
  if (::GetLastError() != ERROR_ALREADY_EXISTS) return false;
  HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"DropClip");
  if (existing != nullptr) {
    ::ShowWindow(existing, SW_SHOW);
    ::ShowWindow(existing, SW_RESTORE);
    ::SetForegroundWindow(existing);
  }
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (AlreadyRunning()) {
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
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"DropClip", origin, size)) {
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
