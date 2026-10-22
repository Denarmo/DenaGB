// SPDX-License-Identifier: GPL-3.0-or-later
// SDL3 on a thread of its own: gamepads with hotplug (SDL's mapping
// database; works under Steam Input) and the audio subsystem the platform
// opens its stream on. No SDL window: Flutter owns the window.
// Spec: docs/specs/desktop-shell.md
#ifndef DENA_SDL_INPUT_H
#define DENA_SDL_INPUT_H

#include <atomic>
#include <cstdint>
#include <functional>
#include <string>
#include <thread>
#include <vector>

namespace dena {

struct SdlInputCallbacks {
  // All on the SDL thread. mask: RetroPad bits plus kMenuGuideBit; ns on
  // the runner's clock (now_ns).
  std::function<void(int port, uint32_t mask, int64_t ns)> buttons;
  std::function<void(int port, int lx, int ly, int rx, int ry)> analog;
  std::function<void(const std::vector<std::string> &names)> players;
  std::function<void(int port, const std::string &name)> disconnected;
};

class SdlInput {
 public:
  ~SdlInput() { stop(); }
  // Starts the thread and waits until SDL is up. False when SDL failed
  // (no gamepads and no audio; the UI still runs).
  bool start(SdlInputCallbacks cb);
  void stop();
  bool audio_ok() const { return audio_ok_; }
  int gamepads() const { return gamepads_; }

 private:
  void thread_main(std::atomic<int> *state);

  SdlInputCallbacks cb_;
  std::thread thread_;
  std::atomic<bool> quit_{false};
  std::atomic<bool> audio_ok_{false};
  std::atomic<int> gamepads_{0};
};

}  // namespace dena

#endif
