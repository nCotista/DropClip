// Unit tests for channel_codec.h. Needs Flutter's header-only
// <flutter/encodable_value.h>; CI downloads it into test/flutter/.
// Build & run: g++ -std=c++17 -Wall -Wextra -Werror -I.. -I. channel_codec_test.cpp && ./a.out
#include "../channel_codec.h"

#include <cstdio>

using namespace dropclip;
using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

namespace {

int failures = 0;
#define CHECK(cond)                                               \
  do {                                                            \
    if (!(cond)) {                                                \
      std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
      ++failures;                                                 \
    }                                                             \
  } while (0)

const EncodableValue& Get(const EncodableValue& map, const char* key) {
  return std::get<EncodableMap>(map).at(EncodableValue(key));
}

EncodableValue ItemValue(EncodableValue mime, EncodableValue data) {
  return EncodableValue(EncodableMap{{EncodableValue("mime"), mime}, {EncodableValue("data"), data}});
}

EncodableValue WriteArgs(EncodableList items) {
  return EncodableValue(EncodableMap{{EncodableValue("items"), EncodableValue(items)}});
}

void TestSnapshotToValue() {
  Snapshot s;
  s.change_token = 0xFFFFFFFFu;  // must stay positive in Dart
  s.items = {{"image/png", {0x89, 0x50}}, {"text/plain", {0x61}}};
  const EncodableValue v = SnapshotToValue(s, 1757280000000);
  CHECK(std::get<int64_t>(Get(v, "change_token")) == 4294967295LL);
  CHECK(std::get<bool>(Get(v, "is_concealed")) == false);
  CHECK(std::get<int64_t>(Get(v, "ts")) == 1757280000000);
  const auto& items = std::get<EncodableList>(Get(v, "items"));
  CHECK(items.size() == 2);
  CHECK(std::get<std::string>(Get(items[0], "mime")) == "image/png");
  CHECK((std::get<std::vector<uint8_t>>(Get(items[0], "data")) == std::vector<uint8_t>{0x89, 0x50}));
}

void TestConcealedSnapshotHasNoItems() {
  Snapshot s;
  s.concealed = true;
  s.items = {{"text/plain", {0x61}}};  // must never leave the process (§10.4)
  const EncodableValue v = SnapshotToValue(s, 0);
  CHECK(std::get<bool>(Get(v, "is_concealed")));
  CHECK(std::get<EncodableList>(Get(v, "items")).empty());
}

void TestNowMs() { CHECK(NowMs() > 1700000000000); }

void TestParseWriteArgs() {
  std::vector<Item> out;
  const EncodableValue args = WriteArgs(
      {ItemValue(EncodableValue("image/png"), EncodableValue(std::vector<uint8_t>{1, 2})),
       ItemValue(EncodableValue("text/plain"), EncodableValue(std::vector<uint8_t>{0x61}))});
  CHECK(ParseWriteArgs(&args, out));
  CHECK(out.size() == 2 && out[0].mime == "image/png" && out[1].data == std::vector<uint8_t>{0x61});
}

void TestParseWriteArgsRejectsMalformed() {
  std::vector<Item> out{{"stale", {}}};
  CHECK(!ParseWriteArgs(nullptr, out) && out.empty());
  const EncodableValue not_map("items");
  CHECK(!ParseWriteArgs(&not_map, out));
  const EncodableValue no_items(EncodableMap{{EncodableValue("x"), EncodableValue(1)}});
  CHECK(!ParseWriteArgs(&no_items, out));
  const EncodableValue empty = WriteArgs({});
  CHECK(!ParseWriteArgs(&empty, out));
  const EncodableValue item_not_map = WriteArgs({EncodableValue("text/plain")});
  CHECK(!ParseWriteArgs(&item_not_map, out));
  const EncodableValue mime_not_string =
      WriteArgs({ItemValue(EncodableValue(1), EncodableValue(std::vector<uint8_t>{1}))});
  CHECK(!ParseWriteArgs(&mime_not_string, out));
  const EncodableValue data_not_bytes =
      WriteArgs({ItemValue(EncodableValue("text/plain"), EncodableValue("hunter2"))});
  CHECK(!ParseWriteArgs(&data_not_bytes, out));
  // One bad item rejects the whole write: no partial clipboard.
  const EncodableValue one_bad = WriteArgs(
      {ItemValue(EncodableValue("image/png"), EncodableValue(std::vector<uint8_t>{1})),
       EncodableValue(5)});
  CHECK(!ParseWriteArgs(&one_bad, out) && out.empty());
}

}  // namespace

int main() {
  TestSnapshotToValue();
  TestConcealedSnapshotHasNoItems();
  TestNowMs();
  TestParseWriteArgs();
  TestParseWriteArgsRejectsMalformed();
  if (failures != 0) {
    std::printf("%d check(s) failed\n", failures);
    return 1;
  }
  std::printf("channel_codec: all tests passed\n");
  return 0;
}
