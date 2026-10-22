// SPDX-License-Identifier: GPL-3.0-or-later
// Spec: docs/specs/desktop-shell.md
#include "desktop_map.h"

#include <algorithm>
#include <cstdio>

#include "dena/desktop.h"
#include "dena/std_codec.h"

namespace dena {

namespace {

// RETRO_DEVICE_ID_JOYPAD_* (libretro.h).
enum : int {
  kB = 0, kY = 1, kSelect = 2, kStart = 3, kUp = 4, kDown = 5, kLeft = 6,
  kRight = 7, kA = 8, kX = 9, kL = 10, kR = 11, kL3 = 14, kR3 = 15,
};

template <typename Fn>
std::vector<uint8_t> encode(Fn fn) {
  std::vector<uint8_t> out(64);
  for (;;) {
    struct dena_buf b = {out.data(), 0, out.size(), false};
    fn(&b);
    if (!b.failed) {
      out.resize(b.len);
      return out;
    }
    out.resize(out.size() * 2);
  }
}

}  // namespace

int pad_button_bit(int sdl_button) {
  switch (sdl_button) {
    case kSdlSouth: return kB;
    case kSdlEast: return kA;
    case kSdlWest: return kY;
    case kSdlNorth: return kX;
    case kSdlBack: return kSelect;
    case kSdlStart: return kStart;
    case kSdlLeftStick: return kL3;
    case kSdlRightStick: return kR3;
    case kSdlLeftShoulder: return kL;
    case kSdlRightShoulder: return kR;
    case kSdlDpadUp: return kUp;
    case kSdlDpadDown: return kDown;
    case kSdlDpadLeft: return kLeft;
    case kSdlDpadRight: return kRight;
    default: return -1;
  }
}

// RetroArch's long-standing keyboard defaults, so players coming from it
// find the same keys: arrows, X = A, Z = B, S = X, A = Y, Q/W = L/R,
// Enter = Start, right Shift or Backspace = Select.
int key_bit(int key) {
  switch (key) {
    case DENA_DESKTOP_KEY_UP: return kUp;
    case DENA_DESKTOP_KEY_DOWN: return kDown;
    case DENA_DESKTOP_KEY_LEFT: return kLeft;
    case DENA_DESKTOP_KEY_RIGHT: return kRight;
    case 'X': return kA;
    case 'Z': return kB;
    case 'S': return kX;
    case 'A': return kY;
    case 'Q': return kL;
    case 'W': return kR;
    case DENA_DESKTOP_KEY_ENTER: return kStart;
    case DENA_DESKTOP_KEY_RSHIFT:
    case DENA_DESKTOP_KEY_BACKSPACE: return kSelect;
    default: return -1;
  }
}

int key_action(int key) { return key == DENA_DESKTOP_KEY_ESCAPE ? kKeyMenu : key_bit(key); }

bool is_menu_combo(uint32_t mask) {
  const uint32_t start_select = (1u << kStart) | (1u << kSelect);
  return (mask & kMenuGuideBit) != 0 || (mask & start_select) == start_select;
}

int PortTable::connect(uint32_t id, const std::string &name) {
  if (int p = port_of(id); p >= 0) return p;
  bool used[kDesktopPorts] = {};
  for (const Device &d : devices_)
    if (d.port >= 0) used[d.port] = true;
  int port = -1;
  for (int i = 0; i < kDesktopPorts && port < 0; i++)
    if (!used[i]) port = i;
  devices_.push_back({id, name, port});
  return port;
}

int PortTable::disconnect(uint32_t id) {
  auto it = std::find_if(devices_.begin(), devices_.end(), [id](const Device &d) { return d.id == id; });
  if (it == devices_.end()) return -1;
  const int port = it->port;
  devices_.erase(it);
  if (port >= 0) {
    for (Device &d : devices_)
      if (d.port < 0) {
        d.port = port;  // the longest-waiting controller moves in
        break;
      }
  }
  return port;
}

int PortTable::port_of(uint32_t id) const {
  for (const Device &d : devices_)
    if (d.id == id) return d.port;
  return -1;
}

std::vector<std::string> PortTable::names() const {
  std::vector<std::string> out(kDesktopPorts);
  for (const Device &d : devices_)
    if (d.port >= 0) out[size_t(d.port)] = d.name;
  return out;
}

std::string desktop_core_file(const std::string &android_name, bool windows) {
  std::string base = android_name;
  if (base.compare(0, 3, "lib") == 0) base = base.substr(3);
  const std::string so = ".so";
  if (base.size() > so.size() && base.compare(base.size() - so.size(), so.size(), so) == 0)
    base.resize(base.size() - so.size());
  // PCSX ReARMed is ARM only; x86_64 builds ship Beetle PSX HW for PS1
  // (docs/dev/desktop-cores.md).
  if (base == "pcsx_rearmed_libretro") base = "mednafen_psx_hw_libretro";
  return base + (windows ? ".dll" : ".so");
}

std::vector<std::string> core_candidates(const std::string &android_name, const std::string &root,
                                         const std::string &lib_dir, bool windows) {
  const std::string file = desktop_core_file(android_name, windows);
  std::vector<std::string> out;
  if (!root.empty()) out.push_back(root + "/cores/" + file);
  if (!lib_dir.empty()) out.push_back(lib_dir + "/cores/" + file);
  return out;
}

std::vector<uint8_t> encode_no_args() {
  // Pigeon sends a single null for a no-argument FlutterApi call.
  return encode([](struct dena_buf *b) { dena_put_null(b); });
}

std::vector<uint8_t> encode_players_changed(const std::vector<std::string> &names) {
  return encode([&](struct dena_buf *b) {
    dena_put_list_start(b, 1);
    dena_put_list_start(b, names.size());
    for (const std::string &n : names) dena_put_string(b, n.c_str());
  });
}

std::string latency_line(int64_t unix_ms, const std::string &metrics_json) {
  char head[48];
  std::snprintf(head, sizeof head, "{\"t_ms\":%lld", static_cast<long long>(unix_ms));
  std::string body = metrics_json;
  if (!body.empty() && body.front() == '{') body.erase(0, 1);
  if (body.empty() || body == "}") return std::string(head) + "}";
  return std::string(head) + "," + body;
}

}  // namespace dena
