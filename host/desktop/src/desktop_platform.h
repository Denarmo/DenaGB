// SPDX-License-Identifier: GPL-3.0-or-later
// The shared runner's desktop platform (Windows and Linux, x86_64): vsync
// from DXGI or the display's refresh rate, SDL3 audio reading the runner's
// ring, desktop GL for GPU cores, frames to Flutter's texture.
// Spec: docs/specs/desktop-shell.md
#ifndef DENA_DESKTOP_PLATFORM_H
#define DENA_DESKTOP_PLATFORM_H

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <vector>

#include "gl_desktop.h"
#include "runner.h"
#ifdef _WIN32
#include "d3d_frames.h"
#else
#include "frame_mailbox.h"
#endif

struct SDL_AudioStream;

namespace dena {

struct DesktopPlatformConfig {
  void *window = nullptr;  // HWND (Windows)
  int refresh_mhz = 60000;
  std::function<void()> frame_ready;  // any thread
};

class DesktopPlatform : public RunnerPlatform {
 public:
  explicit DesktopPlatform(DesktopPlatformConfig cfg);
  ~DesktopPlatform() override;

  Runner runner{this};

  void set_refresh(int mhz) { refresh_mhz_ = mhz > 0 ? mhz : 60000; }
  // Whether SDL audio is up (before the first game).
  void set_audio(bool on) { audio_ = on; }
  // Raster thread: the newest frame (desktop.h, dena_desktop_frame_*).
#ifdef _WIN32
  void *take_d3d(uint32_t *w, uint32_t *h) { return d3d_.take(w, h); }
#else
  const MailFrame *take_rgba(bool *fresh) { return mailbox_.take(fresh); }
#endif

  void thread_begin() override;
  void wait(bool want_frames) override;
  void wake() override;
  bool has_surface() override { return true; }

  bool start_gpu(unsigned w, unsigned h, bool depth, bool stencil) override;
  bool gpu_ready() override { return gl_.ready(); }
  uintptr_t gpu_framebuffer() override { return gl_.framebuffer(); }
  void *gl_proc_address(const char *sym) override { return DesktopGl::proc_address(sym); }
  void stop_gpu() override;

  bool draw_software(const dena_frame &frame, int direction) override;
  bool draw_gpu(unsigned w, unsigned h, bool bottom_left, int direction) override;
  bool read_pixels(unsigned w, unsigned h, bool bottom_left,
                   std::vector<uint32_t> &out) override {
    return gl_.read_pixels(w, h, bottom_left, out);
  }

  int open_audio() override;
  bool start_audio() override;
  void pause_audio() override;
  void close_audio() override;

 private:
  static void audio_callback(void *self, SDL_AudioStream *stream, int additional, int total);
  void wait_clock(int64_t *ns);
  bool put_frame(const uint32_t *xrgb, unsigned w, unsigned h);

  DesktopPlatformConfig cfg_;
  std::atomic<int> refresh_mhz_{60000};
  std::atomic<bool> audio_{false};
  DesktopGl gl_;  // emulator thread
  std::vector<uint32_t> readback_;
#ifdef _WIN32
  D3dFrames d3d_;
  int fast_vblanks_ = 0;    // WaitForVBlank returning at once (display off)
  int clock_frames_ = 0;    // frames left on the clock after that
#else
  FrameMailbox mailbox_;
#endif
  int64_t next_tick_ns_ = 0;

  std::mutex wake_mtx_;
  std::condition_variable wake_cv_;
  bool woken_ = false;

  SDL_AudioStream *stream_ = nullptr;
  std::vector<int16_t> audio_buf_;  // SDL's audio thread only
};

}  // namespace dena

#endif
