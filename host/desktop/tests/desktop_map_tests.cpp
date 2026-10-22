// SPDX-License-Identifier: GPL-3.0-or-later
// Spec: docs/specs/desktop-shell.md
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "dena/desktop.h"
#include "dena/std_codec.h"
#include "desktop_map.h"

static int g_failed = 0;
#define CHECK(c)                                                  \
  do {                                                            \
    if (!(c)) {                                                   \
      std::fprintf(stderr, "%s:%d: CHECK(%s)\n", __FILE__, __LINE__, #c); \
      g_failed++;                                                 \
    }                                                             \
  } while (0)

using namespace dena;

static void test_pad_buttons() {
  CHECK(pad_button_bit(kSdlSouth) == 0);   // B
  CHECK(pad_button_bit(kSdlEast) == 8);    // A
  CHECK(pad_button_bit(kSdlWest) == 1);    // Y
  CHECK(pad_button_bit(kSdlNorth) == 9);   // X
  CHECK(pad_button_bit(kSdlBack) == 2);    // Select
  CHECK(pad_button_bit(kSdlStart) == 3);
  CHECK(pad_button_bit(kSdlDpadUp) == 4);
  CHECK(pad_button_bit(kSdlDpadRight) == 7);
  CHECK(pad_button_bit(kSdlLeftShoulder) == 10);
  CHECK(pad_button_bit(kSdlRightStick) == 15);
  CHECK(pad_button_bit(kSdlGuide) == -1);  // the menu, not a RetroPad button
  CHECK(pad_button_bit(99) == -1);
}

static void test_keys() {
  CHECK(key_bit('X') == 8);
  CHECK(key_bit('Z') == 0);
  CHECK(key_bit(DENA_DESKTOP_KEY_ENTER) == 3);
  CHECK(key_bit(DENA_DESKTOP_KEY_RSHIFT) == 2);
  CHECK(key_bit(DENA_DESKTOP_KEY_LEFT) == 6);
  CHECK(key_bit('P') == -1);
  CHECK(key_action(DENA_DESKTOP_KEY_ESCAPE) == kKeyMenu);
  CHECK(key_action('Q') == 10);
}

static void test_menu_combo() {
  CHECK(is_menu_combo(kMenuGuideBit));
  CHECK(is_menu_combo((1u << 2) | (1u << 3)));
  CHECK(is_menu_combo((1u << 2) | (1u << 3) | (1u << 8)));
  CHECK(!is_menu_combo(1u << 3));
  CHECK(!is_menu_combo(0));
}

static void test_ports() {
  PortTable t;
  CHECK(t.connect(10, "Xbox") == 0);
  CHECK(t.connect(11, "DualSense") == 1);
  CHECK(t.connect(10, "Xbox") == 0);  // already connected
  CHECK(t.connect(12, "8BitDo") == 2);
  CHECK(t.connect(13, "Switch Pro") == 3);
  CHECK(t.connect(14, "Fifth") == -1);  // waits
  CHECK(t.count() == 5);
  std::vector<std::string> n = t.names();
  CHECK(n.size() == 4 && n[0] == "Xbox" && n[3] == "Switch Pro");
  CHECK(t.disconnect(11) == 1);
  CHECK(t.port_of(14) == 1);  // the waiting pad took the free port
  CHECK(t.names()[1] == "Fifth");
  CHECK(t.disconnect(10) == 0);
  CHECK(t.names()[0].empty());
  CHECK(t.connect(15, "New") == 0);  // lowest free port
  CHECK(t.disconnect(99) == -1);
}

static void test_core_names() {
  CHECK(desktop_core_file("libmgba_libretro.so", true) == "mgba_libretro.dll");
  CHECK(desktop_core_file("libmgba_libretro.so", false) == "mgba_libretro.so");
  CHECK(desktop_core_file("mupen64plus_libretro", true) == "mupen64plus_libretro.dll");
  CHECK(desktop_core_file("libpcsx_rearmed_libretro.so", true) == "mednafen_psx_hw_libretro.dll");
  std::vector<std::string> c = core_candidates("libfceumm_libretro.so", "/data", "/app/lib", false);
  CHECK(c.size() == 2 && c[0] == "/data/cores/fceumm_libretro.so" &&
        c[1] == "/app/lib/cores/fceumm_libretro.so");
  CHECK(core_candidates("libx.so", "", "/lib", true).size() == 1);
}

static void test_encoders() {
  std::vector<uint8_t> none = encode_no_args();
  CHECK(none.size() == 1 && none[0] == 0);  // a single null

  std::vector<uint8_t> m = encode_players_changed({"Xbox", "", "", ""});
  struct dena_val vals[16];
  struct dena_val_arena arena = {vals, 16, 0};
  struct dena_val root;
  CHECK(dena_decode(m.data(), m.size(), &arena, &root) == 0);
  const struct dena_val *names = dena_list_at(&root, 0);
  CHECK(names && dena_list_at(names, 0) && dena_val_string_eq(dena_list_at(names, 0), "Xbox"));
  CHECK(names && dena_list_at(names, 3) && dena_val_string_eq(dena_list_at(names, 3), ""));
}

static void test_latency_line() {
  CHECK(latency_line(5, "{\"frames\":3}") == "{\"t_ms\":5,\"frames\":3}");
  CHECK(latency_line(7, "{}") == "{\"t_ms\":7}");
  CHECK(latency_line(7, "") == "{\"t_ms\":7}");
}

int main() {
  test_pad_buttons();
  test_keys();
  test_menu_combo();
  test_ports();
  test_core_names();
  test_encoders();
  test_latency_line();
  if (g_failed) {
    std::fprintf(stderr, "%d check(s) failed\n", g_failed);
    return 1;
  }
  std::printf("desktop_map: ok\n");
  return 0;
}
