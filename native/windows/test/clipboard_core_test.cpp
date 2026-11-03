// Unit tests for clipboard_core.h with a fake clipboard (no Win32 needed).
// Build & run: g++ -std=c++17 -Wall -Wextra -Werror -I.. clipboard_core_test.cpp && ./a.out
#include "../clipboard_core.h"

#include <cstdio>
#include <map>

using namespace dropclip;

namespace {

int failures = 0;
#define CHECK(cond)                                               \
  do {                                                            \
    if (!(cond)) {                                                \
      std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
      ++failures;                                                 \
    }                                                             \
  } while (0)

const Formats kF{13, 8, 17, 0xC100, 0xC101, 0xC102, 0xC103};

class FakeClipboard : public ClipboardApi {
 public:
  std::map<uint32_t, Bytes> data;
  int lock_count = 0;  // Open() fails this many more times
  bool is_open = false;
  std::vector<uint32_t> reads, sleeps;
  uint32_t seq = 100;

  bool Open() override {
    if (lock_count > 0) {
      --lock_count;
      return false;
    }
    return is_open = true;
  }
  void Close() override { is_open = false; }
  bool IsAvailable(uint32_t f) const override { return data.count(f) > 0; }
  std::optional<Bytes> GetData(uint32_t f) override {
    CHECK(is_open);
    reads.push_back(f);
    auto it = data.find(f);
    if (it == data.end()) return std::nullopt;
    return it->second;
  }
  bool Empty() override {
    data.clear();
    return true;
  }
  bool SetData(uint32_t f, const Bytes& b) override {
    data[f] = b;
    return true;
  }
  uint32_t SequenceNumber() const override { return seq; }
  void Sleep(uint32_t ms) override { sleeps.push_back(ms); }
};

Bytes U16(std::u16string s) {
  Bytes b;
  for (char16_t c : s) {
    b.push_back(uint8_t(c & 0xFF));
    b.push_back(uint8_t(c >> 8));
  }
  b.push_back(0);
  b.push_back(0);
  return b;
}
Bytes B(const std::string& s) { return Bytes(s.begin(), s.end()); }
const Bytes kZero{0, 0, 0, 0}, kOne{1, 0, 0, 0};

bool ReadContent(const FakeClipboard& c) {
  for (uint32_t f : c.reads)
    if (f != kF.history && f != kF.cloud) return true;
  return false;
}

void TestReadsThaiTextAndEmoji() {
  FakeClipboard c;
  c.data[kF.unicode_text] = U16(u"สวัสดี 😀");
  Snapshot s;
  CHECK(ReadSnapshot(c, kF, s) == Status::kOk);
  CHECK(s.change_token == 100);
  CHECK(!s.concealed);
  CHECK(s.items.size() == 1);
  CHECK(s.items[0].mime == "text/plain");
  CHECK(s.items[0].data == B("สวัสดี 😀"));
  CHECK(!c.is_open);  // closed again
}

void TestPrefersPngOverDib() {
  FakeClipboard c;
  c.data[kF.dib] = {1};
  c.data[kF.dib_v5] = {2};
  c.data[kF.png] = {3};
  Snapshot s;
  ReadSnapshot(c, kF, s);
  CHECK(s.items.size() == 1 && s.items[0].mime == "image/png" && s.items[0].data == Bytes{3});
  c.data.erase(kF.png);
  ReadSnapshot(c, kF, s);
  CHECK(s.items.size() == 1 && s.items[0].mime == "image/x-win-dibv5");
}

void TestExcludeMarkerIsConcealedWithoutReading() {
  FakeClipboard c;
  c.data[kF.exclude] = {};
  c.data[kF.unicode_text] = U16(u"hunter2");
  Snapshot s;
  CHECK(ReadSnapshot(c, kF, s) == Status::kOk);
  CHECK(s.concealed && s.items.empty());
  CHECK(c.reads.empty());  // content never touched (§10.4)
}

void TestHistoryOrCloudZeroIsConcealed() {
  for (uint32_t marker : {kF.history, kF.cloud}) {
    FakeClipboard c;
    c.data[marker] = kZero;
    c.data[kF.unicode_text] = U16(u"hunter2");
    Snapshot s;
    ReadSnapshot(c, kF, s);
    CHECK(s.concealed && s.items.empty());
    CHECK(!ReadContent(c));
    CHECK(!c.is_open);
  }
}

void TestHistoryOneIsNotConcealed() {
  FakeClipboard c;
  c.data[kF.history] = kOne;
  c.data[kF.cloud] = {0, 0};  // too short to be a DWORD: ignored
  c.data[kF.unicode_text] = U16(u"ok");
  Snapshot s;
  ReadSnapshot(c, kF, s);
  CHECK(!s.concealed && s.items.size() == 1);
}

void TestLockedRetriesThenFails() {
  FakeClipboard c;
  c.lock_count = 4;
  c.data[kF.unicode_text] = U16(u"x");
  Snapshot s;
  CHECK(ReadSnapshot(c, kF, s) == Status::kLocked);
  CHECK((c.sleeps == std::vector<uint32_t>{50, 100, 200}));
  CHECK(s.items.empty());
}

void TestLockedRecoversOnLastTry() {
  FakeClipboard c;
  c.lock_count = 3;
  c.data[kF.unicode_text] = U16(u"x");
  Snapshot s;
  CHECK(ReadSnapshot(c, kF, s) == Status::kOk);
  CHECK(s.items.size() == 1);
}

void TestLockedWithMarkerFailsClosed() {
  FakeClipboard c;
  c.lock_count = 10;
  c.data[kF.history] = kOne;  // cannot read its value -> assume sensitive
  Snapshot s;
  CHECK(ReadSnapshot(c, kF, s) == Status::kOk);
  CHECK(s.concealed && s.items.empty());
}

void TestEmptyAndBrokenData() {
  FakeClipboard c;
  Snapshot s;
  CHECK(ReadSnapshot(c, kF, s) == Status::kOk && s.items.empty());
  c.data[kF.png] = {};                // empty image is skipped
  c.data[kF.unicode_text] = {0, 0};   // only a NUL
  ReadSnapshot(c, kF, s);
  CHECK(s.items.empty());
  c.data[kF.unicode_text] = {0x41};   // odd length: no full unit
  ReadSnapshot(c, kF, s);
  CHECK(s.items.empty());
}

void TestUtfEdgeCases() {
  CHECK(Utf16ToUtf8({0x00, 0xD8, 0x41, 0x00}) == "\xEF\xBF\xBD" "A");  // lone surrogate
  CHECK(Utf16ToUtf8({0x3D, 0xD8, 0x00, 0xDE, 0x00, 0x00}) == "\xF0\x9F\x98\x80");  // pair
  CHECK(Utf16ToUtf8({0x00, 0xDC}) == "\xEF\xBF\xBD");  // lone low surrogate
}

}  // namespace

int main() {
  TestReadsThaiTextAndEmoji();
  TestPrefersPngOverDib();
  TestExcludeMarkerIsConcealedWithoutReading();
  TestHistoryOrCloudZeroIsConcealed();
  TestHistoryOneIsNotConcealed();
  TestLockedRetriesThenFails();
  TestLockedRecoversOnLastTry();
  TestLockedWithMarkerFailsClosed();
  TestEmptyAndBrokenData();
  TestUtfEdgeCases();
  if (failures != 0) {
    std::printf("%d check(s) failed\n", failures);
    return 1;
  }
  std::printf("clipboard_core: all tests passed\n");
  return 0;
}
