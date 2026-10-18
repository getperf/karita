#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "app_links/app_links_plugin_c_api.h"
#include "flutter_window.h"
#include "utils.h"

// **窓名は1箇所でだけ決める。** `FindWindow` の鍵であると同時にタイトルバーへ出る文字列でも
// あり、2箇所に書くと片方だけ直したときに転送が黙って効かなくなる（harness の main.cpp は
// 複製したままで、ここを移すときに気づいた）。
//
// **harness とは別の名前である**（あちらは `karita_harness`）。同じにすると、起きている
// harness へ本番の受け渡しが飛ぶ。
constexpr const wchar_t *kWindowTitle = L"karita";

// 既に起きている karita へ URI を渡し、前面へ出す。
//
// **Window を増やさない。** `karita://share?url=…` は毎回この exe を起動するので、素通しすると
// 共有のたびに新しい Window が立つ。起きている側を見つけたら `SendAppLink` で渡して終わる —
// 受け取った側は `app_links` の stream に流れ、`AppLinksShareInbox` が拾う。
bool ForwardToRunningInstance() {
  HWND hwnd = FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", kWindowTitle);
  if (!hwnd) return false;
  SendAppLink(hwnd);
  // 最小化されていれば戻す。**任意のページが叩ける穴を受け入れた以上、前面化そのものは
  // 防げない**（browser-handoff-implementation.md「受け入れる判断」）。
  if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
  SetForegroundWindow(hwnd);
  return true;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (ForwardToRunningInstance()) return EXIT_SUCCESS;

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
  // Outer window size in logical pixels, including the title bar and borders.
  Win32Window::Size size(640, 800);
  if (!window.Create(kWindowTitle, origin, size)) {
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
