// Reference impl of Sankofa_ReadLinkHeader — the .vmcode LinkTable parser the
// engine calls before Dart_LoadELF (Tasks 6/7, §7.2). Format = exactly what
// aot_tools/lib/src/linker.dart LinkTable.toBytes() emits (CODEPUSH_SPEC §4):
//   [count uint32 BE][ (sim uint32 BE, cpu uint32 BE) × count ][ pad → 4096 ].
// Returns the 4096-aligned header size (offset where the ELF begins), or -1 on
// a malformed/too-small buffer. (The VM version also stashes the sim→cpu map;
// shown here as an out-vector to keep the parser pure + testable.)
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

static uint32_t RdU32BE(const uint8_t* p) {
  return (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16) |
         (uint32_t(p[2]) << 8) | uint32_t(p[3]);
}

struct LinkPair { uint32_t sim, cpu; };

long Sankofa_ReadLinkHeader(const void* mapping, long size,
                            std::vector<LinkPair>* out /*nullable*/) {
  if (mapping == nullptr || size < 4) return -1;
  const uint8_t* p = static_cast<const uint8_t*>(mapping);
  const uint32_t count = RdU32BE(p);
  const long table_bytes = 4L + 8L * long(count);   // count + pairs
  if (table_bytes > size) return -1;                // truncated
  if (out != nullptr) {
    out->clear();
    out->reserve(count);
    for (uint32_t i = 0; i < count; ++i) {
      const uint8_t* e = p + 4 + 8 * i;
      out->push_back({RdU32BE(e), RdU32BE(e + 4)});
    }
  }
  // 4096-align (matches LinkTable.toBytes padToAlignment=4096).
  const long aligned = (table_bytes + 4095) & ~long(4095);
  if (aligned > size) return -1;                    // pad runs past buffer
  return aligned;
}

// ---- test: build a blob byte-for-byte like LinkTable.toBytes(), parse it ----
static void PutU32BE(std::vector<uint8_t>& b, uint32_t v) {
  b.push_back(v >> 24); b.push_back(v >> 16); b.push_back(v >> 8); b.push_back(v);
}
static std::vector<uint8_t> MakeVmcode(const std::vector<LinkPair>& pairs,
                                       int elf_payload_len) {
  std::vector<uint8_t> b;
  PutU32BE(b, uint32_t(pairs.size()));
  for (auto& m : pairs) { PutU32BE(b, m.sim); PutU32BE(b, m.cpu); }
  while (b.size() % 4096 != 0) b.push_back(0);      // pad → 4096
  for (int i = 0; i < elf_payload_len; ++i) b.push_back(0x7f); // fake ELF
  return b;
}
static int fails = 0;
static void check(bool ok, const char* what) {
  printf("  [%s] %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails++;
}
int main() {
  // case 1: 3 mappings → header padded to 4096, ELF follows.
  std::vector<LinkPair> in = {{0x10, 0x20}, {0x34, 0x40}, {0x58, 0x60}};
  auto blob = MakeVmcode(in, 1234);
  std::vector<LinkPair> got;
  long off = Sankofa_ReadLinkHeader(blob.data(), long(blob.size()), &got);
  check(off == 4096, "offset == 4096 (1-page header)");
  check(got.size() == 3, "parsed 3 pairs");
  check(got.size()==3 && got[1].sim==0x34 && got[1].cpu==0x40, "pair[1] sim/cpu correct");
  check(long(blob.size()) == 4096 + 1234, "ELF payload starts at offset");

  // case 2: empty table (count 0) still pads to 4096.
  auto e = MakeVmcode({}, 8);
  check(Sankofa_ReadLinkHeader(e.data(), long(e.size()), nullptr) == 4096, "empty table → 4096");

  // case 3: large table spanning 2 pages.
  std::vector<LinkPair> big(600); for (uint32_t i=0;i<600;i++) big[i]={i,i*2};
  auto bb = MakeVmcode(big, 16);                     // 4+4800=4804 → pad 8192
  long boff = Sankofa_ReadLinkHeader(bb.data(), long(bb.size()), &got);
  check(boff == 8192, "600 pairs → 8192 (2-page header)");
  check(got.size()==600 && got[599].cpu==1198, "last pair correct");

  // case 4: malformed (truncated) → -1.
  check(Sankofa_ReadLinkHeader(blob.data(), 3, nullptr) == -1, "size<4 → -1");
  uint8_t hdr[4]; hdr[0]=0;hdr[1]=0;hdr[2]=0xff;hdr[3]=0xff; // count=65535, no body
  check(Sankofa_ReadLinkHeader(hdr, 4, nullptr) == -1, "count exceeds buffer → -1");

  printf(fails ? "\nFAILED (%d)\n" : "\nALL PASS\n", fails);
  return fails ? 1 : 0;
}
