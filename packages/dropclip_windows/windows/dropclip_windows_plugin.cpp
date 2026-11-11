#include "include/dropclip_windows/dropclip_windows_plugin_c_api.h"

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <vector>

#include "ClipboardWatcher.h"
#include "channel_codec.h"

namespace dropclip {
namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using Result = std::unique_ptr<flutter::MethodResult<EncodableValue>>;
using StreamError = std::unique_ptr<flutter::StreamHandlerError<EncodableValue>>;

constexpr char kLocked[] = "CLIPBOARD_LOCKED";
constexpr char kLockedMessage[] = "clipboard is held by another app";

// Serves the PROTO §14.1 channels on Windows (T1.7) with the same contract as
// dropclip_macos (T1.6), so NativeClipboard works on both. Everything runs on
// the platform thread, which also pumps the watcher's message-only window.
class DropclipWindowsPlugin : public flutter::Plugin {
 public:
  explicit DropclipWindowsPlugin(flutter::BinaryMessenger* messenger)
      : watcher_([this](Status status, const Snapshot& snapshot) { OnChange(status, snapshot); }),
        methods_(messenger, "dropclip/clipboard", &flutter::StandardMethodCodec::GetInstance()),
        events_(messenger, "dropclip/clipboard/events",
                &flutter::StandardMethodCodec::GetInstance()) {
    methods_.SetMethodCallHandler(
        [this](const flutter::MethodCall<EncodableValue>& call, Result result) {
          Handle(call, std::move(result));
        });
    events_.SetStreamHandler(std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
        [this](const EncodableValue*,
               std::unique_ptr<flutter::EventSink<EncodableValue>>&& sink) -> StreamError {
          sink_ = std::move(sink);
          return nullptr;
        },
        [this](const EncodableValue*) -> StreamError {
          sink_.reset();
          return nullptr;
        }));
  }

 private:
  void Handle(const flutter::MethodCall<EncodableValue>& call, Result result) {
    const std::string& method = call.method_name();
    if (method == "start") {
      if (watcher_.Start()) {
        result->Success();
      } else {
        result->Error("START_FAILED", "AddClipboardFormatListener failed");
      }
      return;
    }
    if (method == "stop") {
      watcher_.Stop();
      result->Success();
      return;
    }
    if (method == "changeToken") {
      result->Success(EncodableValue(static_cast<int64_t>(watcher_.ChangeToken())));
      return;
    }
    if (method != "read" && method != "write" && method != "clear") {
      result->NotImplemented();
      return;
    }
    if (!watcher_.IsRunning()) {
      result->Error("NOT_STARTED", "call start first");
      return;
    }

    if (method == "read") {
      Snapshot snapshot;
      if (watcher_.Read(snapshot) == Status::kOk) {
        result->Success(SnapshotToValue(snapshot, NowMs()));
        return;
      }
    } else if (method == "write") {
      std::vector<Item> items;
      if (!ParseWriteArgs(call.arguments(), items)) {
        result->Error("BAD_ARGS", "expected {items: [{mime, data}]}");
        return;
      }
      uint32_t token = 0;
      if (watcher_.Write(items, token) == Status::kOk) {
        result->Success(EncodableValue(EncodableMap{
            {EncodableValue("change_token"), EncodableValue(static_cast<int64_t>(token))}}));
        return;
      }
    } else if (watcher_.ClearClipboard() == Status::kOk) {
      result->Success();
      return;
    }
    result->Error(kLocked, kLockedMessage);
  }

  void OnChange(Status status, const Snapshot& snapshot) {
    if (!sink_) return;
    if (status == Status::kLocked) {
      sink_->Error(kLocked, kLockedMessage);
    } else {
      sink_->Success(SnapshotToValue(snapshot, NowMs()));
    }
  }

  // Declared first so it is destroyed last, after the channels stop calling us.
  WindowsClipboardWatcher watcher_;
  std::unique_ptr<flutter::EventSink<EncodableValue>> sink_;
  flutter::MethodChannel<EncodableValue> methods_;
  flutter::EventChannel<EncodableValue> events_;
};

}  // namespace
}  // namespace dropclip

void DropclipWindowsPluginCApiRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
  auto* windows_registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  windows_registrar->AddPlugin(
      std::make_unique<dropclip::DropclipWindowsPlugin>(windows_registrar->messenger()));
}
