// SPDX-License-Identifier: GPL-3.0-or-later
// Spec: docs/specs/desktop-shell.md
#include "desktop_platform.h"

#include <SDL3/SDL.h>

#include <chrono>
#include <cstdio>
#include <thread>

namespace dena {

namespace {

constexpr int kAudioRate = 48000;
constexpr uint32_t kAudioChunk = 256;  // frames per read from the ring

}  // namespace

DesktopPlatform::DesktopPlatform(DesktopPlatformConfig cfg) : cfg_(std::move(cfg)) {
  set_refresh(cfg_.refresh_mhz);
}

DesktopPlatform::~DesktopPlatform() {
  runner.stop();
  close_audio();
}

void DesktopPlatform::thread_begin() {
  next_tick_ns_ = 0;
#ifdef _WIN32
  d3d_.init();
  d3d_.clear();
  SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_ABOVE_NORMAL);
#else
  mailbox_.clear();
#endif
}

void DesktopPlatform::wait_clock(int64_t *ns) {
  const int64_t period = 1000000000000LL / refresh_mhz_;
  const int64_t now = now_ns();
  if (next_tick_ns_ == 0 || now - next_tick_ns_ > 100000000LL) next_tick_ns_ = now;
  next_tick_ns_ += period;
  const int64_t left = next_tick_ns_ - now_ns();
  if (left > 0) std::this_thread::sleep_for(std::chrono::nanoseconds(left));
  *ns = next_tick_ns_;
}

void DesktopPlatform::wait(bool want_frames) {
  if (!want_frames) {
    std::unique_lock<std::mutex> lk(wake_mtx_);
    wake_cv_.wait_for(lk, std::chrono::milliseconds(250), [this] { return woken_; });
    woken_ = false;
    return;
  }
  // Commands queued meanwhile run when this returns (at most one frame late).
  int64_t ns = 0;
#ifdef _WIN32
  bool vblank = false;
  if (clock_frames_ > 0) {
    clock_frames_--;
  } else {
    const int64_t before = now_ns();
    vblank = d3d_.wait_vblank(static_cast<HWND>(cfg_.window));
    ns = now_ns();
    // A sleeping display answers at once: pace by the clock for a while.
    if (vblank && ns - before < 500000) {
      if (++fast_vblanks_ > 5) {
        fast_vblanks_ = 0;
        clock_frames_ = 120;
      }
    } else {
      fast_vblanks_ = 0;
    }
  }
  if (!vblank) wait_clock(&ns);
#else
  // TODO(desktop): Wayland presentation feedback; until then the monitor's
  // refresh rate drives a clock (desktop-shell.md, Vsync).
  wait_clock(&ns);
#endif
  {
    std::lock_guard<std::mutex> lk(wake_mtx_);
    woken_ = false;
  }
  runner.on_vsync(ns);
}

void DesktopPlatform::wake() {
  {
    std::lock_guard<std::mutex> lk(wake_mtx_);
    woken_ = true;
  }
  wake_cv_.notify_all();
}

bool DesktopPlatform::start_gpu(unsigned w, unsigned h, bool depth, bool stencil) {
  if (!gl_.init(w, h, depth, stencil)) return false;
#ifdef _WIN32
  d3d_.attach_gl(&gl_);  // false: frames are read back instead
#endif
  return true;
}

void DesktopPlatform::stop_gpu() {
#ifdef _WIN32
  d3d_.detach_gl();
#endif
  gl_.shutdown();
}

bool DesktopPlatform::put_frame(const uint32_t *xrgb, unsigned w, unsigned h) {
#ifdef _WIN32
  if (!d3d_.put_pixels(xrgb, w, h)) return false;
#else
  mailbox_.put(xrgb, w, h);
#endif
  if (cfg_.frame_ready) cfg_.frame_ready();
  return true;
}

bool DesktopPlatform::draw_software(const dena_frame &f, int) {
  return put_frame(f.pixels, f.width, f.height);
}

bool DesktopPlatform::draw_gpu(unsigned w, unsigned h, bool bottom_left, int) {
#ifdef _WIN32
  if (d3d_.gl_attached()) {
    if (!d3d_.put_gl(w, h, bottom_left)) return false;
    if (cfg_.frame_ready) cfg_.frame_ready();
    return true;
  }
#endif
  if (!gl_.read_pixels(w, h, bottom_left, readback_)) return false;
  return put_frame(readback_.data(), w, h);
}

void DesktopPlatform::audio_callback(void *user, SDL_AudioStream *stream, int additional, int) {
  auto *self = static_cast<DesktopPlatform *>(user);
  uint32_t frames = uint32_t(additional > 0 ? additional : 0) / 4;  // S16 stereo
  self->audio_buf_.resize(kAudioChunk * 2);
  while (frames > 0) {
    const uint32_t n = frames < kAudioChunk ? frames : kAudioChunk;
    self->runner.read_audio(self->audio_buf_.data(), n);
    SDL_PutAudioStreamData(stream, self->audio_buf_.data(), int(n * 4));
    frames -= n;
  }
}

int DesktopPlatform::open_audio() {
  if (!audio_ || stream_) return stream_ ? kAudioRate : 0;
  SDL_AudioSpec spec{SDL_AUDIO_S16, 2, kAudioRate};
  stream_ = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, audio_callback, this);
  if (!stream_) {
    std::fprintf(stderr, "dena: audio: %s\n", SDL_GetError());
    return 0;
  }
  return kAudioRate;  // the stream converts to the device's own format
}

bool DesktopPlatform::start_audio() { return stream_ && SDL_ResumeAudioStreamDevice(stream_); }

void DesktopPlatform::pause_audio() {
  if (!stream_) return;
  SDL_PauseAudioStreamDevice(stream_);
  SDL_ClearAudioStream(stream_);
}

void DesktopPlatform::close_audio() {
  if (!stream_) return;
  SDL_DestroyAudioStream(stream_);  // also closes the device
  stream_ = nullptr;
}

}  // namespace dena
