// Converts between clipboard_core types and the Flutter StandardMethodCodec
// values of the PROTO §14.1 channels. Win32-free, so it is unit-tested with
// g++ (test/channel_codec_test.cpp) next to clipboard_core.h.
#pragma once

#include <flutter/encodable_value.h>

#include <chrono>
#include <cstdint>
#include <string>
#include <vector>

#include "clipboard_core.h"

namespace dropclip {

inline int64_t NowMs() {
  using namespace std::chrono;
  return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

// One `ClipSnapshot` map (§14.1): {change_token, is_concealed, items, ts}.
// Items are always empty for a concealed snapshot (§10.4).
inline flutter::EncodableValue SnapshotToValue(const Snapshot& s, int64_t ts_ms) {
  using flutter::EncodableMap;
  using flutter::EncodableValue;
  flutter::EncodableList items;
  if (!s.concealed) {
    for (const auto& item : s.items) {
      items.emplace_back(EncodableMap{{EncodableValue("mime"), EncodableValue(item.mime)},
                                      {EncodableValue("data"), EncodableValue(item.data)}});
    }
  }
  return EncodableValue(EncodableMap{
      {EncodableValue("change_token"), EncodableValue(static_cast<int64_t>(s.change_token))},
      {EncodableValue("is_concealed"), EncodableValue(s.concealed)},
      {EncodableValue("items"), EncodableValue(items)},
      {EncodableValue("ts"), EncodableValue(ts_ms)},
  });
}

// `write` arguments: {items: [{mime: String, data: Uint8List}, ...]}.
// Returns false (and leaves `out` empty) on any missing or mistyped field.
inline bool ParseWriteArgs(const flutter::EncodableValue* args, std::vector<Item>& out) {
  using flutter::EncodableMap;
  using flutter::EncodableValue;
  out.clear();
  const auto* map = args ? std::get_if<EncodableMap>(args) : nullptr;
  if (map == nullptr) return false;
  const auto list_it = map->find(EncodableValue("items"));
  if (list_it == map->end()) return false;
  const auto* list = std::get_if<flutter::EncodableList>(&list_it->second);
  if (list == nullptr || list->empty()) return false;
  for (const auto& entry : *list) {
    const auto* item = std::get_if<EncodableMap>(&entry);
    if (item == nullptr) break;
    const auto mime = item->find(EncodableValue("mime"));
    const auto data = item->find(EncodableValue("data"));
    const auto* mime_str = mime == item->end() ? nullptr : std::get_if<std::string>(&mime->second);
    const auto* bytes =
        data == item->end() ? nullptr : std::get_if<std::vector<uint8_t>>(&data->second);
    if (mime_str == nullptr || bytes == nullptr) break;
    out.push_back({*mime_str, *bytes});
  }
  if (out.size() != list->size()) {
    out.clear();
    return false;
  }
  return true;
}

}  // namespace dropclip
