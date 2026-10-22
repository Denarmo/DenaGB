// SPDX-License-Identifier: GPL-3.0-or-later
// Spec: docs/specs/desktop-shell.md
#include "sdl_input.h"

#include <SDL3/SDL.h>

#include <chrono>
#include <cstdio>
#include <map>

#include "desktop_map.h"
#include "runner.h"

namespace dena {

namespace {

struct Pad {
  SDL_Gamepad *gp = nullptr;
  std::string name;
  uint32_t mask = 0;
  int axis[6] = {};
};

}  // namespace

bool SdlInput::start(SdlInputCallbacks cb) {
  if (thread_.joinable()) return true;
  cb_ = std::move(cb);
  quit_ = false;
  std::atomic<int> state{0};  // 0 starting, 1 up, -1 failed
  thread_ = std::thread(&SdlInput::thread_main, this, &state);
  while (state == 0) std::this_thread::sleep_for(std::chrono::milliseconds(1));
  if (state < 0) {
    thread_.join();
    return false;
  }
  return true;
}

void SdlInput::stop() {
  if (!thread_.joinable()) return;
  quit_ = true;
  thread_.join();
}

void SdlInput::thread_main(std::atomic<int> *state) {
  // There is no SDL window, so SDL never sees focus: keep pad events
  // flowing while the Flutter window is in front.
  SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
  SDL_SetHint(SDL_HINT_JOYSTICK_THREAD, "1");  // Windows raw input on its own thread
  SDL_SetHint(SDL_HINT_AUDIO_DEVICE_SAMPLE_FRAMES, "256");
  const bool pads = SDL_InitSubSystem(SDL_INIT_GAMEPAD);
  if (!pads) std::fprintf(stderr, "dena: SDL gamepads: %s\n", SDL_GetError());
  audio_ok_ = SDL_InitSubSystem(SDL_INIT_AUDIO);
  if (!audio_ok_) std::fprintf(stderr, "dena: SDL audio: %s\n", SDL_GetError());
  if (!pads && !audio_ok_) {
    SDL_Quit();
    *state = -1;
    return;
  }
  // SDL timestamps count from SDL's start; the runner's clock from boot.
  const int64_t offset = now_ns() - int64_t(SDL_GetTicksNS());
  *state = 1;  // `state` is gone after this

  PortTable ports;
  std::map<SDL_JoystickID, Pad> pads_by_id;
  auto send_buttons = [&](const Pad &p, SDL_JoystickID id, int64_t ns) {
    const int port = ports.port_of(id);
    if (port >= 0 && cb_.buttons) cb_.buttons(port, p.mask, ns);
  };
  auto send_analog = [&](const Pad &p, SDL_JoystickID id) {
    const int port = ports.port_of(id);
    if (port >= 0 && cb_.analog)
      cb_.analog(port, p.axis[SDL_GAMEPAD_AXIS_LEFTX], p.axis[SDL_GAMEPAD_AXIS_LEFTY],
                 p.axis[SDL_GAMEPAD_AXIS_RIGHTX], p.axis[SDL_GAMEPAD_AXIS_RIGHTY]);
  };

  while (!quit_) {
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
      switch (e.type) {
        case SDL_EVENT_GAMEPAD_ADDED: {
          const SDL_JoystickID id = e.gdevice.which;
          if (pads_by_id.count(id)) break;
          Pad p;
          p.gp = SDL_OpenGamepad(id);
          if (!p.gp) break;
          const char *name = SDL_GetGamepadName(p.gp);
          p.name = name ? name : "Controller";
          ports.connect(uint32_t(id), p.name);
          pads_by_id[id] = p;
          gamepads_ = int(pads_by_id.size());
          if (cb_.players) cb_.players(ports.names());
          break;
        }
        case SDL_EVENT_GAMEPAD_REMOVED: {
          const SDL_JoystickID id = e.gdevice.which;
          auto it = pads_by_id.find(id);
          if (it == pads_by_id.end()) break;
          const std::string name = it->second.name;
          SDL_CloseGamepad(it->second.gp);
          pads_by_id.erase(it);
          gamepads_ = int(pads_by_id.size());
          const int port = ports.disconnect(uint32_t(id));
          if (port >= 0) {
            if (cb_.buttons) cb_.buttons(port, 0, now_ns());
            if (cb_.analog) cb_.analog(port, 0, 0, 0, 0);
            if (cb_.disconnected) cb_.disconnected(port, name);
            // A waiting controller may have moved into the port.
            for (auto &[other, pad] : pads_by_id)
              if (ports.port_of(uint32_t(other)) == port) {
                send_buttons(pad, other, now_ns());
                send_analog(pad, other);
              }
          }
          if (cb_.players) cb_.players(ports.names());
          break;
        }
        case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
        case SDL_EVENT_GAMEPAD_BUTTON_UP: {
          auto it = pads_by_id.find(e.gbutton.which);
          if (it == pads_by_id.end()) break;
          uint32_t bit = 0;
          if (e.gbutton.button == kSdlGuide) {
            bit = kMenuGuideBit;
          } else if (int b = pad_button_bit(e.gbutton.button); b >= 0) {
            bit = 1u << b;
          } else {
            break;
          }
          Pad &p = it->second;
          p.mask = e.gbutton.down ? (p.mask | bit) : (p.mask & ~bit);
          send_buttons(p, it->first, int64_t(e.gbutton.timestamp) + offset);
          break;
        }
        case SDL_EVENT_GAMEPAD_AXIS_MOTION: {
          auto it = pads_by_id.find(e.gaxis.which);
          if (it == pads_by_id.end() || e.gaxis.axis >= 6) break;
          Pad &p = it->second;
          p.axis[e.gaxis.axis] = e.gaxis.value;
          if (e.gaxis.axis == SDL_GAMEPAD_AXIS_LEFT_TRIGGER ||
              e.gaxis.axis == SDL_GAMEPAD_AXIS_RIGHT_TRIGGER) {
            const uint32_t bit = e.gaxis.axis == SDL_GAMEPAD_AXIS_LEFT_TRIGGER ? 1u << 12 : 1u << 13;
            const uint32_t mask = e.gaxis.value > kTriggerThreshold ? (p.mask | bit) : (p.mask & ~bit);
            if (mask != p.mask) {
              p.mask = mask;
              send_buttons(p, it->first, int64_t(e.gaxis.timestamp) + offset);
            }
          } else {
            send_analog(p, it->first);
          }
          break;
        }
        default:
          break;
      }
    }
    // XInput is polled: 1 ms keeps pad latency under a millisecond.
    SDL_DelayNS(1000000);
  }
  for (auto &[id, pad] : pads_by_id) SDL_CloseGamepad(pad.gp);
  gamepads_ = 0;
  SDL_Quit();
}

}  // namespace dena
