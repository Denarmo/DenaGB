// SPDX-License-Identifier: GPL-3.0-or-later
// The play loop shared by the platform shells: emulator thread, pause and
// auto-save, fast-forward, rewind, states, cheats, input, audio rate control
// and latency metrics. Platform APIs come through RunnerPlatform.
// Spec: docs/specs/shared-runner.md
#ifndef DENA_RUNNER_H
#define DENA_RUNNER_H

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <deque>
#include <functional>
#include <future>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

extern "C" {
#include "dena/audio.h"
#include "dena/host.h"
#include "dena/rewind.h"
}

namespace dena {

class Runner;

// What a shell provides. Unless noted, hooks run on the emulator thread.
class RunnerPlatform {
 public:
  virtual ~RunnerPlatform() = default;

  // Emulator thread start (before the GPU starts) and end.
  virtual void thread_begin() {}
  virtual void thread_end() {}
  // After the GPU start: gpu_ok is false only for a GPU core that failed.
  virtual void video_begin(bool hw, bool gpu_ok) { (void)hw, (void)gpu_ok; }
  // Blocks until wake() or a vsync. With want_frames, a vsync calls
  // runner.on_vsync(ns) from inside this call.
  virtual void wait(bool want_frames) = 0;
  // Any thread: ends a wait() early.
  virtual void wake() = 0;
  // Any thread: there is somewhere to draw.
  virtual bool has_surface() = 0;

  // GPU cores (hw-render.md).
  virtual bool start_gpu(unsigned w, unsigned h, bool depth, bool stencil) = 0;
  virtual bool gpu_ready() = 0;
  virtual uintptr_t gpu_framebuffer() = 0;
  virtual void *gl_proc_address(const char *sym) = 0;
  virtual void stop_gpu() = 0;  // after the core destroyed its context

  // Puts a frame on the surface; false when nothing was shown.
  // direction is -1 while rewinding (shaders that animate), else 1.
  virtual bool draw_software(const dena_frame &frame, int direction) = 0;
  virtual bool draw_gpu(unsigned w, unsigned h, bool bottom_left, int direction) = 0;
  virtual bool read_pixels(unsigned w, unsigned h, bool flip_y, std::vector<uint32_t> &out) = 0;

  // Audio (any thread). open_audio returns the output rate, 0 for none;
  // the platform's audio thread calls runner.read_audio().
  virtual int open_audio() = 0;
  virtual bool start_audio() = 0;
  virtual void pause_audio() = 0;
  virtual void close_audio() = 0;
  virtual int audio_xruns() { return 0; }
};

// Fixed-size sample window with percentile queries (metrics only).
class Samples {
 public:
  explicit Samples(size_t cap) : cap_(cap) {}
  void add(double v);
  bool empty() const { return data_.empty(); }
  double pct(double p) const;
  double max() const;

 private:
  size_t cap_;
  size_t next_ = 0;
  std::vector<double> data_;
};

int64_t now_ns();

class Runner {
 public:
  // Result of start(): see game-session.md, Lifecycle.
  enum StartResult { kStartError = -1, kStartFresh = 0, kStartResumed = 1, kStartBadState = 2 };

  explicit Runner(RunnerPlatform *platform) : platform_(platform) {}
  ~Runner() { stop(); }
  Runner(const Runner &) = delete;
  Runner &operator=(const Runner &) = delete;

  int start(const std::string &core_path, const std::string &rom_path,
            const std::string &system_dir, const std::string &srm_path,
            const std::string &state_path);
  // Saves (battery and auto-save state), then unloads the core.
  void stop();
  bool running() const { return thread_.joinable(); }

  // Internal resolution (shaders.md, Upscale): 0 keeps the core's default,
  // 2-4 multiplies the native size on cores that support it (capped at
  // max_upscale). Takes effect at the next start().
  void set_upscale(int factor) { upscale_ = factor; }
  // Core options set after Dena's own at the next start() (performance.md,
  // Measuring: lets a phone pass compare core settings without a rebuild).
  void set_extra_options(std::vector<std::pair<std::string, std::string>> opts) {
    extra_options_ = std::move(opts);
  }
  // "key=value;key=value" -> pairs; entries without '=' are skipped.
  static std::vector<std::pair<std::string, std::string>> parse_options(const std::string &s);
  // performance.md, Measuring: fn gets a one-line timing summary from the
  // emulator thread about every 5 s of play; empty turns it off. Set before
  // start().
  void set_perf_log(std::function<void(const char *)> fn) { perf_log_ = std::move(fn); }
  // Highest factor the core at core_path renders at (1: no upscale).
  static int max_upscale(const std::string &core_path);
  // The core options start() sets for factor (key, value), in order.
  static std::vector<std::pair<std::string, std::string>> upscale_options(
      const std::string &core_path, int factor);
  // The game's native picture size, for shaders (shaders.md, Native lines).
  // Valid after start().
  void native_size(unsigned *w, unsigned *h) const;

  // Runs fn on the emulator thread between frames and waits for it.
  void run_on_emu(std::function<void()> fn);

  // Pauses frames and audio and writes the battery save and auto-save state.
  void pause();
  void resume();
  bool paused() const { return paused_; }
  void save_now();
  void set_speed(int n);
  // performance.md: audio buffer target, 20..80 ms (default 40); takes
  // effect the next time audio opens (game start).
  void set_audio_latency_ms(int ms) { audio_target_ms_ = uint32_t(std::clamp(ms, 20, 80)); }
  int audio_latency_ms() const { return int(audio_target_ms_.load()); }

  // Rewind (rewind.md): enabled captures states; l2_hold makes a gamepad's
  // L2 rewind while held (for systems that don't use L2).
  void configure_rewind(bool enabled, bool l2_hold);
  void set_rewinding(bool on) { rewind_hold_ = on; }
  bool rewinding() const;

  // Save-state slots (save-states.md). 0 ok, -1 error; load may return DENA_NO_DATA.
  int save_state(const std::string &state_path, const std::string &png_path);
  int load_state(const std::string &state_path);
  // Current frame as PNG (pause-menu.md, Capture). 0 ok, -1 error.
  int screenshot(const std::string &path);
  // Replaces the active cheats (cheats.md).
  void set_cheats(std::vector<std::string> codes);
  // Host mailbox in the core's system RAM (pico8-launcher-cart.md). Any
  // thread. watch_ram picks the window [offset, offset + len) that is copied
  // out after every frame (len 0 stops); read_ram copies the latest snapshot
  // (false before one exists or when the core has no such RAM); write_ram
  // queues bytes that go in before the next frame, in call order.
  void watch_ram(size_t offset, size_t len);
  bool read_ram(uint8_t *out, size_t len);
  void write_ram(size_t offset, const uint8_t *data, size_t len);

  // Achievements (achievements.md). fn runs on the emulator thread after every
  // played frame (not rewound ones) with the loaded core; set before start().
  void set_frame_hook(std::function<void(dena_core *)> fn) { frame_hook_ = std::move(fn); }
  // Hardcore mode (any thread): while on, state loads fail, rewind stops and
  // cheats are cleared and refused.
  void set_hardcore(bool on) { hardcore_ = on; }
  bool hardcore() const { return hardcore_; }

  // Input (any thread); applied on the next frame. event_ns is CLOCK_MONOTONIC.
  void set_buttons(int port, int mask, int64_t event_ns);
  void set_touch(int mask, int64_t event_ns);  // ORed into port 0
  void set_analog(int port, int lx, int ly, int rx, int ry);
  void set_touch_analog(int stick, int x, int y);  // overrides port 0's sticks while held
  void set_pointer(int x, int y, bool pressed);
  // Turbo (turbo.md): buttons in `mask` (libretro joypad bits, all ports)
  // alternate pressed/released every `half_frames` emulated frames while held.
  // mask 0 turns turbo off.
  void set_turbo(int mask, int half_frames);

  // Emulator thread: a vsync at vsync_ns (CLOCK_MONOTONIC). Returns the
  // number of core frames it ran or rewound (0 on panels faster than the
  // game, between its frames).
  int on_vsync(int64_t vsync_ns);
  // Emulator thread: draws the last frame again (paused shader changes, new surfaces).
  void repaint();
  // Emulator thread: forget frame timing (a lost surface).
  void resync() { next_due_ns_ = 0; }

  // Audio thread: fills out with n stereo frames.
  void read_audio(int16_t *out, uint32_t n) { dena_ring_read(&ring_, out, n); }

  std::string metrics_json();
  void reset_metrics();
  // Pixel of the last software frame as 0xRRGGBB, or -1 (instrumentation tests).
  int pixel(int x, int y);
  bool hw() const { return hw_; }
  const std::string &error() const { return error_; }
  void set_error(const std::string &e) { error_ = e; }

 private:
  static void audio_sink(void *user, const int16_t *frames, size_t n);
  static uintptr_t hw_framebuffer(void *self);
  static void *hw_proc_address(void *self, const char *sym);
  static uint64_t pack_analog(int lx, int ly, int rx, int ry);

  void push_audio(const int16_t *frames, size_t n);
  bool open_audio();
  void close_audio();
  void thread_main();
  bool start_gpu();
  const dena_frame *current_frame();
  void run_commands();
  void save_all();
  void reject_state();
  void retry_state_load();
  void reset_rewind();
  void capture_rewind();
  void rewind_one_frame();
  void run_one_frame();
  void present();
  bool draw_frame();
  void perf_sample(int64_t vsync_ns, int frames, bool shown, int64_t run_ns, int64_t present_ns);

  RunnerPlatform *platform_;
  std::mutex life_mtx_;
  std::thread thread_;
  std::atomic<bool> running_{false};

  dena_core *core_ = nullptr;
  dena_av_info av_{};
  int upscale_ = 0;
  std::vector<std::pair<std::string, std::string>> extra_options_;
  unsigned native_w_ = 0, native_h_ = 0;
  bool hw_ = false;  // the core renders with the GPU (hw-render.md)
  std::promise<bool> *gpu_ready_ = nullptr;
  dena_hw_info hw_info_{};
  std::vector<uint32_t> readback_;
  dena_frame readback_frame_{};
  std::string error_;

  std::mutex cmd_mtx_;
  std::deque<std::function<void()>> cmds_;
  std::atomic<bool> paused_{false};
  std::atomic<int> speed_{1};
  std::string srm_path_, state_path_;
  uint64_t last_battery_hash_ = 0;
  int state_retries_ = 0;  // frames left to retry a deferred state load
  int64_t last_battery_check_ns_ = 0;

  dena_rewind *rewind_ = nullptr;  // emulator thread
  std::vector<uint8_t> rewind_state_;
  unsigned rewind_tick_ = 0;
  bool rewind_enabled_ = true;
  bool muted_ = false;
  std::atomic<bool> rewind_hold_{false};
  std::atomic<bool> l2_rewind_{false};

  std::atomic<uint32_t> buttons_[DENA_MAX_PORTS] = {};
  std::atomic<uint32_t> touch_buttons_{0};
  std::atomic<uint32_t> turbo_mask_{0};
  std::atomic<int> turbo_half_{2};
  unsigned turbo_tick_ = 0;  // emulator thread
  std::atomic<uint64_t> analog_[DENA_MAX_PORTS] = {};  // lx, ly, rx, ry (int16)
  std::atomic<uint64_t> touch_analog_{0};
  std::atomic<uint32_t> pointer_{0};  // x << 16 | y, int16 each
  std::atomic<bool> pointer_down_{false};
  std::atomic<int64_t> pending_input_ns_{0};
  int64_t frame_input_ns_ = 0;

  int64_t frame_period_ns_ = 16666667;
  int64_t next_due_ns_ = 0;
  int64_t last_post_ns_ = 0;

  bool audio_open_ = false;
  int32_t out_rate_ = 0;
  std::atomic<uint32_t> audio_target_ms_{40};
  uint32_t target_frames_ = 0;
  dena_ring ring_{};
  dena_resampler resampler_{};
  dena_rate_ctl rate_ctl_{};
  std::vector<int16_t> resampled_;

  std::function<void(dena_core *)> frame_hook_;

  // performance.md, Measuring (emulator thread).
  std::function<void(const char *)> perf_log_;
  struct PerfWindow {
    int64_t start_ns = 0;
    int vsyncs = 0, frames = 0, shown = 0;
    int64_t run_ns = 0, run_max_ns = 0, present_ns = 0, present_max_ns = 0;
  } perf_;
  std::atomic<bool> hardcore_{false};
  bool hardcore_applied_ = false;  // emulator thread
  void apply_hardcore();

  void sync_ram_before();
  void sync_ram_after();
  std::mutex ram_mtx_;
  size_t ram_offset_ = 0, ram_len_ = 0;
  std::vector<uint8_t> ram_snapshot_;  // empty until a frame ran with a window
  std::vector<std::pair<size_t, std::vector<uint8_t>>> ram_writes_;

  std::mutex frame_mtx_;
  std::vector<uint32_t> last_frame_;
  uint32_t last_w_ = 0, last_h_ = 0;

  std::mutex metrics_mtx_;
  Samples input_to_post_{256};
  Samples frame_interval_{600};
  unsigned missed_ = 0;
  uint64_t frames_ = 0;
};

}  // namespace dena

#endif
