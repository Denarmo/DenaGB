// SPDX-License-Identifier: GPL-3.0-or-later
// The desktop host's pure parts, tested without SDL, GL or a window:
// controller and keyboard bindings, port assignment, core file names,
// storage paths and the session events sent to Dart.
// Spec: docs/specs/desktop-shell.md
#ifndef DENA_DESKTOP_MAP_H
#define DENA_DESKTOP_MAP_H

#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace dena {

constexpr int kDesktopPorts = 4;  // DENA_MAX_PORTS

// RetroPad joypad bit (RETRO_DEVICE_ID_JOYPAD_*) for an SDL3 gamepad button
// (SDL_GamepadButton value), -1 when unbound. Positional: the bottom face
// button is RetroPad B, the right one A (Nintendo layout), as on Android.
int pad_button_bit(int sdl_button);
// SDL_GamepadButton values the bindings use (stable SDL3 ABI).
enum : int {
  kSdlSouth = 0, kSdlEast = 1, kSdlWest = 2, kSdlNorth = 3, kSdlBack = 4,
  kSdlGuide = 5, kSdlStart = 6, kSdlLeftStick = 7, kSdlRightStick = 8,
  kSdlLeftShoulder = 9, kSdlRightShoulder = 10, kSdlDpadUp = 11,
  kSdlDpadDown = 12, kSdlDpadLeft = 13, kSdlDpadRight = 14,
};
// Trigger travel (0..32767) past which L2/R2 count as pressed.
constexpr int kTriggerThreshold = 12000;

// RetroPad bit for a keyboard key (DENA_DESKTOP_KEY_* or ASCII), -1 when
// unbound. Escape is the menu key (kKeyMenu), not a RetroPad button.
int key_bit(int key);
constexpr int kKeyMenu = -2;
int key_action(int key);  // key_bit, or kKeyMenu for Escape

// Start + Select, or Guide, opens the pause menu (gamepads.md).
bool is_menu_combo(uint32_t mask);
constexpr uint32_t kMenuGuideBit = 1u << 16;  // outside the 16 RetroPad bits

// Controllers to ports: the lowest free port, in connection order. A fifth
// controller waits without a port until one frees up.
class PortTable {
 public:
  // Returns the port given to device id, or -1 when all are taken.
  int connect(uint32_t id, const std::string &name);
  // Returns the port the device had, -1 when it had none. A waiting device
  // takes the freed port.
  int disconnect(uint32_t id);
  int port_of(uint32_t id) const;
  // Names per port, "" for a free one (GameEventsApi.onPlayersChanged).
  std::vector<std::string> names() const;
  int count() const { return int(devices_.size()); }

 private:
  struct Device {
    uint32_t id;
    std::string name;
    int port;
  };
  std::vector<Device> devices_;
};

// Android's core library name ("libmgba_libretro.so") as the desktop file
// name: "mgba_libretro.dll" on Windows, "mgba_libretro.so" elsewhere. PS1
// becomes Beetle PSX HW (mednafen_psx_hw), the x86_64 PS1 core.
std::string desktop_core_file(const std::string &android_name, bool windows);
// Where to look for that core, in order: <root>/cores, then <lib_dir>/cores.
std::vector<std::string> core_candidates(const std::string &android_name, const std::string &root,
                                         const std::string &lib_dir, bool windows);

// Pigeon payloads for GameEventsApi calls the desktop host sends.
std::vector<uint8_t> encode_no_args();  // onMenuRequested, onGamepadUsed
std::vector<uint8_t> encode_players_changed(const std::vector<std::string> &names);

// One latency log line: {"t_ms":<unix ms>, <metrics fields>}.
std::string latency_line(int64_t unix_ms, const std::string &metrics_json);

}  // namespace dena

#endif
