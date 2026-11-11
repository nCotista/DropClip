#pragma once

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00  // Windows 10
#endif
#ifndef UNICODE
#define UNICODE
#endif
#include <windows.h>

#include <cstring>
#include <functional>
#include <memory>
#include <utility>

#include "clipboard_core.h"

namespace dropclip {

// ClipboardApi on real Win32 calls. `owner` is our message-only window, so
// clipboard content we write is owned by it and can be skipped as echo.
class Win32ClipboardApi : public ClipboardApi {
 public:
  explicit Win32ClipboardApi(HWND owner) : owner_(owner) {}

  bool Open() override { return OpenClipboard(owner_) != FALSE; }
  void Close() override { CloseClipboard(); }
  bool IsAvailable(uint32_t format) const override {
    return IsClipboardFormatAvailable(format) != FALSE;
  }

  std::optional<Bytes> GetData(uint32_t format) override {
    HANDLE handle = GetClipboardData(format);
    if (handle == nullptr) return std::nullopt;
    const SIZE_T size = GlobalSize(handle);
    const auto* p = static_cast<const uint8_t*>(GlobalLock(handle));
    if (p == nullptr) return std::nullopt;
    Bytes out(p, p + size);
    GlobalUnlock(handle);
    return out;
  }

  bool Empty() override { return EmptyClipboard() != FALSE; }

  bool SetData(uint32_t format, const Bytes& data) override {
    HGLOBAL handle = GlobalAlloc(GMEM_MOVEABLE, data.empty() ? 1 : data.size());
    if (handle == nullptr) return false;
    void* p = GlobalLock(handle);
    if (p == nullptr) {
      GlobalFree(handle);
      return false;
    }
    if (!data.empty()) std::memcpy(p, data.data(), data.size());
    GlobalUnlock(handle);
    // On success the OS owns the memory; on failure it is still ours.
    if (SetClipboardData(format, handle) == nullptr) {
      GlobalFree(handle);
      return false;
    }
    return true;
  }

  uint32_t SequenceNumber() const override { return GetClipboardSequenceNumber(); }
  void Sleep(uint32_t ms) override { ::Sleep(ms); }

 private:
  HWND owner_;
};

/**
 * Windows Native Clipboard Watcher using Win32 Event-Driven Listener (PROTO-DC-V2.0 §14.1, FR-03A)
 *
 * Threading: all methods MUST be called on a thread that pumps a Win32 message loop
 * (the Flutter Windows runner's platform thread does). The platform channel (PR 3)
 * maps Status::kLocked to PlatformException('CLIPBOARD_LOCKED').
 */
class WindowsClipboardWatcher {
 public:
  // Called for every change made by another app. On kOk the snapshot is filled
  // (items empty when concealed, §10.4); on kLocked it only has change_token.
  using ChangeCallback = std::function<void(Status status, const Snapshot& snapshot)>;

  explicit WindowsClipboardWatcher(ChangeCallback onChange) : onChange_(std::move(onChange)) {
    formats_.png = RegisterClipboardFormatW(L"PNG");
    formats_.exclude = RegisterClipboardFormatW(L"ExcludeClipboardContentFromMonitorProcessing");
    formats_.history = RegisterClipboardFormatW(L"CanIncludeInClipboardHistory");
    formats_.cloud = RegisterClipboardFormatW(L"CanUploadToCloudClipboard");
  }

  WindowsClipboardWatcher(const WindowsClipboardWatcher&) = delete;
  WindowsClipboardWatcher& operator=(const WindowsClipboardWatcher&) = delete;

  ~WindowsClipboardWatcher() { Stop(); }

  bool Start() {
    if (hwnd_ != nullptr) return true;  // Already running

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = &WindowsClipboardWatcher::WndProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = kClassName;
    if (RegisterClassExW(&wc) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      return false;
    }

    // `this` is handed over through lpParam and stored in GWLP_USERDATA on WM_NCCREATE.
    hwnd_ = CreateWindowExW(0, kClassName, L"DropClipWatcher", 0, 0, 0, 0, 0, HWND_MESSAGE,
                            nullptr, wc.hInstance, this);
    if (hwnd_ == nullptr) return false;

    if (!AddClipboardFormatListener(hwnd_)) {
      DestroyWindow(hwnd_);
      hwnd_ = nullptr;
      return false;
    }
    api_ = std::make_unique<Win32ClipboardApi>(hwnd_);
    return true;
  }

  void Stop() {
    if (hwnd_ == nullptr) return;
    RemoveClipboardFormatListener(hwnd_);
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
    api_.reset();
  }

  // §14.1 methods for the platform channel. They need Start() first.
  Status Read(Snapshot& out) { return ReadSnapshot(*api_, formats_, out); }
  Status Write(const std::vector<Item>& items, uint32_t& token) {
    return WriteItems(*api_, formats_, items, token);
  }
  Status ClearClipboard() { return Clear(*api_); }
  uint32_t ChangeToken() const { return GetClipboardSequenceNumber(); }
  bool IsRunning() const { return api_ != nullptr; }

 private:
  static constexpr const wchar_t* kClassName = L"DropClipWatcherClass";

  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    if (msg == WM_NCCREATE) {
      auto* create = reinterpret_cast<CREATESTRUCTW*>(lParam);
      SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    }
    auto* self = reinterpret_cast<WindowsClipboardWatcher*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (msg == WM_CLIPBOARDUPDATE && self != nullptr) {
      self->OnClipboardUpdate();
      return 0;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
  }

  void OnClipboardUpdate() {
    // Echo of our own write (Write() opened the clipboard with hwnd_).
    if (GetClipboardOwner() == hwnd_ || api_ == nullptr || !onChange_) return;
    Snapshot snapshot;
    const Status status = ReadSnapshot(*api_, formats_, snapshot);
    onChange_(status, snapshot);
  }

  ChangeCallback onChange_;
  Formats formats_;
  HWND hwnd_ = nullptr;
  std::unique_ptr<Win32ClipboardApi> api_;
};

}  // namespace dropclip
