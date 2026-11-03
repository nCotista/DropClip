// Win32-free clipboard logic for the Windows watcher (T1.7, PROTO §10.4,
// §14.1). Everything that touches the OS goes through ClipboardApi, so this
// file builds and is unit-tested with g++ on any OS (test/clipboard_core_test.cpp).
#pragma once

#include <cstdint>
#include <initializer_list>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace dropclip {

using Bytes = std::vector<uint8_t>;

// The few Win32 clipboard calls we need. The real one is in ClipboardWatcher.cpp.
class ClipboardApi {
 public:
  virtual ~ClipboardApi() = default;
  virtual bool Open() = 0;  // OpenClipboard(our hwnd)
  virtual void Close() = 0;
  virtual bool IsAvailable(uint32_t format) const = 0;  // no Open needed
  virtual std::optional<Bytes> GetData(uint32_t format) = 0;
  virtual bool Empty() = 0;
  virtual bool SetData(uint32_t format, const Bytes& data) = 0;
  virtual uint32_t SequenceNumber() const = 0;
  virtual void Sleep(uint32_t ms) = 0;
};

// Standard ids plus RegisterClipboardFormatW() results.
struct Formats {
  uint32_t unicode_text = 13;  // CF_UNICODETEXT
  uint32_t dib = 8;            // CF_DIB
  uint32_t dib_v5 = 17;        // CF_DIBV5
  uint32_t png = 0;            // "PNG"
  uint32_t exclude = 0;        // "ExcludeClipboardContentFromMonitorProcessing"
  uint32_t history = 0;        // "CanIncludeInClipboardHistory"
  uint32_t cloud = 0;          // "CanUploadToCloudClipboard"
};

struct Item {
  std::string mime;
  Bytes data;
};

struct Snapshot {
  uint32_t change_token = 0;
  bool concealed = false;
  std::vector<Item> items;  // always empty when concealed
};

enum class Status { kOk, kLocked };

// CLIPBOARD_LOCK_RETRY (§16): one try, then 3 retries after 50/100/200 ms.
inline bool OpenWithRetry(ClipboardApi& api) {
  for (uint32_t delay : {50u, 100u, 200u}) {
    if (api.Open()) return true;
    api.Sleep(delay);
  }
  return api.Open();
}

// Closes the clipboard on every return path.
class OpenGuard {
 public:
  explicit OpenGuard(ClipboardApi& api) : api_(api) {}
  ~OpenGuard() { api_.Close(); }
  OpenGuard(const OpenGuard&) = delete;
  OpenGuard& operator=(const OpenGuard&) = delete;

 private:
  ClipboardApi& api_;
};

inline bool IsZeroDword(const std::optional<Bytes>& b) {
  return b && b->size() >= 4 && (*b)[0] == 0 && (*b)[1] == 0 && (*b)[2] == 0 &&
         (*b)[3] == 0;
}

// UTF-16LE up to the first NUL -> UTF-8. Lone surrogates become U+FFFD.
inline std::string Utf16ToUtf8(const Bytes& in) {
  std::string out;
  auto unit = [&](size_t i) { return uint32_t(in[2 * i] | (in[2 * i + 1] << 8)); };
  const size_t n = in.size() / 2;
  for (size_t i = 0; i < n; ++i) {
    uint32_t c = unit(i);
    if (c == 0) break;
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < n && unit(i + 1) >= 0xDC00 &&
        unit(i + 1) <= 0xDFFF) {
      c = 0x10000 + ((c - 0xD800) << 10) + (unit(++i) - 0xDC00);
    } else if (c >= 0xD800 && c <= 0xDFFF) {
      c = 0xFFFD;
    }
    if (c < 0x80) {
      out += char(c);
    } else if (c < 0x800) {
      out += char(0xC0 | (c >> 6));
      out += char(0x80 | (c & 0x3F));
    } else if (c < 0x10000) {
      out += char(0xE0 | (c >> 12));
      out += char(0x80 | ((c >> 6) & 0x3F));
      out += char(0x80 | (c & 0x3F));
    } else {
      out += char(0xF0 | (c >> 18));
      out += char(0x80 | ((c >> 12) & 0x3F));
      out += char(0x80 | ((c >> 6) & 0x3F));
      out += char(0x80 | (c & 0x3F));
    }
  }
  return out;
}

// Reads the current clipboard (§14.1 `read` and change events). The
// sensitive markers (§10.4) are checked BEFORE any content is read; if they
// cannot be checked the change is treated as concealed (fail closed).
inline Status ReadSnapshot(ClipboardApi& api, const Formats& f, Snapshot& out) {
  out = Snapshot{};
  out.change_token = api.SequenceNumber();
  if (f.exclude != 0 && api.IsAvailable(f.exclude)) {
    out.concealed = true;
    return Status::kOk;
  }
  const bool has_history = f.history != 0 && api.IsAvailable(f.history);
  const bool has_cloud = f.cloud != 0 && api.IsAvailable(f.cloud);
  if (!OpenWithRetry(api)) {
    if (has_history || has_cloud) {
      out.concealed = true;
      return Status::kOk;
    }
    return Status::kLocked;
  }
  OpenGuard guard(api);
  if ((has_history && IsZeroDword(api.GetData(f.history))) ||
      (has_cloud && IsZeroDword(api.GetData(f.cloud)))) {
    out.concealed = true;
    return Status::kOk;
  }
  // One image, best first (§11.2: PNG over DIB); the Dart normalizer converts it.
  const std::pair<uint32_t, const char*> images[] = {
      {f.png, "image/png"}, {f.dib_v5, "image/x-win-dibv5"}, {f.dib, "image/x-win-dib"}};
  for (const auto& [format, mime] : images) {
    if (format == 0 || !api.IsAvailable(format)) continue;
    if (auto data = api.GetData(format); data && !data->empty()) {
      out.items.push_back({mime, std::move(*data)});
      break;
    }
  }
  if (api.IsAvailable(f.unicode_text)) {
    if (auto data = api.GetData(f.unicode_text)) {
      const std::string text = Utf16ToUtf8(*data);
      if (!text.empty()) out.items.push_back({"text/plain", Bytes(text.begin(), text.end())});
    }
  }
  return Status::kOk;
}

}  // namespace dropclip
