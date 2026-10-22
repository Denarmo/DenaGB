// SPDX-License-Identifier: GPL-3.0-or-later
// Spec: docs/specs/shared-runner.md (moved from the Android shell's runner.cpp)
#include "runner.h"

#include <time.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

extern "C" {
#include "dena/session.h"
}

namespace dena {

namespace {

constexpr int64_t kBatteryCheckNs = 30LL * 1000000000LL;  // game-session.md
constexpr int kMaxSpeed = 8;
constexpr size_t kRewindBudget = 32u << 20;  // rewind.md
constexpr int kRewindInterval = 2;           // capture every 2nd frame
constexpr uint16_t kL2 = 1u << 12;           // RETRO_DEVICE_ID_JOYPAD_L2
constexpr int kStateRetryFrames = 600;       // ~10 s of boot for a GPU core

void log_error(const char *msg, const char *arg = "") {
  std::fprintf(stderr, "dena: %s%s\n", msg, arg);
}

// Where Dena differs from a core's declared defaults, by core library name.
struct CoreOverride {
  const char *core, *key, *value;
};
constexpr CoreOverride kCoreOverrides[] = {
    // ds.md: the touch screen arrives as the libretro pointer, not a mouse.
    {"melonds", "melonds_touch_mode", "Touch"},
    // ds.md: JIT without fast memory (its SIGSEGV handler and shared-memory
    // mirrors are the fragile part on Android).
    {"melonds", "melonds_jit_fast_memory", "disabled"},
    // performance.md, DS: the Android build has only the software renderer;
    // threaded, 3D rasterises on its own core instead of the emulator thread.
    {"melonds", "melonds_threaded_renderer", "enabled"},
};

std::string core_name(const std::string &core_path) {
  return core_path.substr(core_path.find_last_of("/\\") + 1);
}

// shaders.md, Upscale: the core option that sets the internal resolution,
// value per factor 1-4 (nullptr: the core has no such factor), and an option
// that 2x-4x also need.
struct Upscale {
  const char *core, *key;
  const char *values[4];
  unsigned native_w, native_h;  // 1x picture (base geometry is the render size)
  const char *gpu_key = nullptr, *gpu_value = nullptr;
};
constexpr Upscale kUpscales[] = {
    {"mupen64plus", "mupen64plus-43screensize",
     {"320x240", "640x480", "960x720", "1280x960"}, 320, 240},
    {"ppsspp", "ppsspp_internal_resolution",
     {"480x272", "960x544", "1440x816", "1920x1088"}, 480, 272},
    {"pcsx_rearmed", "pcsx_rearmed_neon_enhancement_enable",
     {"disabled", "enabled", nullptr, nullptr}, 0, 0},
    // ds.md, Internal resolution: 2x-4x switch to the OpenGL ES renderer; 1x
    // (Auto) keeps the threaded software renderer. The core always outputs
    // 4x (1024x1536) once OpenGL is on.
    {"melonds", "melonds_opengl_resolution",
     {"1x native (256x192)", "2x native (512x384)", "3x native (768x576)",
      "4x native (1024x768)"},
     256, 384, "melonds_opengl_renderer", "enabled"},
};

const Upscale *find_upscale(const std::string &core_path) {
  std::string name = core_name(core_path);
  for (const auto &u : kUpscales)
    if (name.find(u.core) != std::string::npos) return &u;
  return nullptr;
}

void apply_core_overrides(dena_core *core, const std::string &core_path, int upscale,
                          const std::vector<std::pair<std::string, std::string>> &extra) {
  std::string name = core_name(core_path);
  for (const auto &o : kCoreOverrides)
    if (name.find(o.core) != std::string::npos) dena_core_set_option(core, o.key, o.value);
  for (const auto &kv : Runner::upscale_options(core_path, upscale))
    dena_core_set_option(core, kv.first.c_str(), kv.second.c_str());
  for (const auto &kv : extra) dena_core_set_option(core, kv.first.c_str(), kv.second.c_str());
}

}  // namespace

std::vector<std::pair<std::string, std::string>> Runner::upscale_options(
    const std::string &core_path, int factor) {
  std::vector<std::pair<std::string, std::string>> out;
  const Upscale *u = find_upscale(core_path);
  if (!u || factor < 1) return out;  // 0: the core's own default
  int f = std::min(factor, max_upscale(core_path));
  out.emplace_back(u->key, u->values[f - 1]);
  if (u->gpu_key && f >= 2) out.emplace_back(u->gpu_key, u->gpu_value);
  return out;
}

std::vector<std::pair<std::string, std::string>> Runner::parse_options(const std::string &s) {
  std::vector<std::pair<std::string, std::string>> out;
  size_t pos = 0;
  while (pos <= s.size()) {
    size_t end = s.find(';', pos);
    if (end == std::string::npos) end = s.size();
    std::string item = s.substr(pos, end - pos);
    size_t eq = item.find('=');
    if (eq != std::string::npos && eq > 0) out.emplace_back(item.substr(0, eq), item.substr(eq + 1));
    pos = end + 1;
  }
  return out;
}

int Runner::max_upscale(const std::string &core_path) {
  const Upscale *u = find_upscale(core_path);
  if (!u) return 1;
  int f = 1;
  while (f < 4 && u->values[f]) f++;
  return f;
}

void Runner::native_size(unsigned *w, unsigned *h) const {
  *w = native_w_;
  *h = native_h_;
}

int64_t now_ns() {
  timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return int64_t(ts.tv_sec) * 1000000000LL + ts.tv_nsec;
}

void Samples::add(double v) {
  if (data_.size() < cap_) data_.push_back(v);
  else data_[next_ % cap_] = v;
  next_++;
}

double Samples::pct(double p) const {
  std::vector<double> s(data_);
  std::sort(s.begin(), s.end());
  size_t i = size_t(std::ceil(p / 100.0 * double(s.size())));
  return s[i == 0 ? 0 : std::min(i - 1, s.size() - 1)];
}

double Samples::max() const { return *std::max_element(data_.begin(), data_.end()); }

int Runner::start(const std::string &core_path, const std::string &rom_path,
                  const std::string &system_dir, const std::string &srm_path,
                  const std::string &state_path) {
#ifdef _WIN32
  _putenv_s("DENA_SYSTEM_DIR", system_dir.c_str());  // host tests on Windows
#else
  setenv("DENA_SYSTEM_DIR", system_dir.c_str(), 1);
#endif
  std::lock_guard<std::mutex> lk(life_mtx_);
  if (thread_.joinable()) {
    error_ = "already running";
    return kStartError;
  }
  // libretro has no thread affinity; after loading, every core call
  // happens on the emulator thread.
  char err[512] = {0};
  core_ = dena_core_load(core_path.c_str(), err, sizeof err);
  if (!core_) {
    error_ = err;
    return kStartError;
  }
  apply_core_overrides(core_, core_path, upscale_, extra_options_);
  dena_hw_hooks hooks{&Runner::hw_framebuffer, &Runner::hw_proc_address, this};
  dena_core_set_hw_hooks(core_, &hooks);
  if (dena_core_load_game(core_, rom_path.c_str(), err, sizeof err) != 0) {
    error_ = err;
    dena_core_unload(core_);
    core_ = nullptr;
    return kStartError;
  }
  dena_core_set_hashing(core_, 0);
  srm_path_ = srm_path;
  state_path_ = state_path;
  int result = kStartFresh;
  if (!srm_path_.empty()) dena_battery_load(core_, srm_path_.c_str());
  last_battery_hash_ = dena_battery_hash(core_);
  hw_ = dena_core_hw_info(core_, &hw_info_) == 1;
  state_retries_ = 0;
  if (!state_path_.empty()) {
    int rc = dena_state_load_file(core_, state_path_.c_str());
    if (rc == 0) {
      result = kStartResumed;
    } else if (rc != DENA_NO_DATA && hw_) {
      // GPU cores (PPSSPP) refuse states until their renderer exists, a few
      // frames into the boot: retry from the emulator thread (game-session.md).
      state_retries_ = kStateRetryFrames;
      result = kStartResumed;
    } else if (rc != DENA_NO_DATA) {
      reject_state();
      result = kStartBadState;
    }
  }
  dena_core_av_info(core_, &av_);
  {
    const Upscale *u = find_upscale(core_path);
    native_w_ = u && u->native_w ? u->native_w : av_.base_width;
    native_h_ = u && u->native_h ? u->native_h : av_.base_height;
  }
  reset_rewind();
  paused_ = false;
  speed_ = 1;
  touch_buttons_ = 0;
  pointer_ = 0;
  pointer_down_ = false;
  touch_analog_ = 0;
  for (auto &a : analog_) a = 0;
  for (auto &b : buttons_) b = 0;
  reset_metrics();
  perf_ = PerfWindow{};
  if (!open_audio()) log_error("audio unavailable; running silent");
  dena_core_set_audio_sink(core_, &Runner::audio_sink, this);
  running_ = true;
  std::promise<bool> gpu_ok;
  auto gpu_fut = gpu_ok.get_future();
  gpu_ready_ = &gpu_ok;
  thread_ = std::thread(&Runner::thread_main, this);
  if (!gpu_fut.get()) {  // GPU core whose context could not be created
    thread_.join();
    close_audio();
    dena_core_unload(core_);
    core_ = nullptr;
    error_ = "This game needs OpenGL ES 3, which this device could not start";
    return kStartError;
  }
  return result;
}

void Runner::run_on_emu(std::function<void()> fn) {
  if (!thread_.joinable() || std::this_thread::get_id() == thread_.get_id()) {
    fn();
    return;
  }
  std::promise<void> done;
  auto fut = done.get_future();
  {
    std::lock_guard<std::mutex> lk(cmd_mtx_);
    cmds_.push_back([&] {
      fn();
      done.set_value();
    });
  }
  platform_->wake();
  fut.wait();
}

void Runner::pause() {
  run_on_emu([this] {
    paused_ = true;
    save_all();
  });
  if (audio_open_) platform_->pause_audio();
}

void Runner::resume() {
  if (audio_open_) platform_->start_audio();
  run_on_emu([this] {
    paused_ = false;
    next_due_ns_ = 0;
  });
}

void Runner::save_now() {
  run_on_emu([this] { save_all(); });
}

void Runner::set_speed(int n) { speed_ = std::clamp(n, 1, kMaxSpeed); }

void Runner::configure_rewind(bool enabled, bool l2_hold) {
  run_on_emu([&] {
    rewind_enabled_ = enabled;
    if (!enabled && rewind_) dena_rewind_clear(rewind_);
  });
  l2_rewind_ = l2_hold;
}

uint64_t Runner::pack_analog(int lx, int ly, int rx, int ry) {
  auto u = [](int v) { return uint64_t(uint16_t(int16_t(std::clamp(v, -0x7fff, 0x7fff)))); };
  return u(lx) | u(ly) << 16 | u(rx) << 32 | u(ry) << 48;
}

void Runner::set_analog(int port, int lx, int ly, int rx, int ry) {
  if (port >= 0 && port < DENA_MAX_PORTS) analog_[port] = pack_analog(lx, ly, rx, ry);
}

void Runner::set_touch_analog(int stick, int x, int y) {
  uint64_t v = touch_analog_.load();
  int shift = stick == 1 ? 32 : 0;
  uint64_t part = pack_analog(x, y, 0, 0) & 0xffffffffu;
  touch_analog_ = (v & ~(uint64_t(0xffffffffu) << shift)) | (part << shift);
}

void Runner::set_pointer(int x, int y, bool pressed) {
  pointer_.store((uint32_t(uint16_t(int16_t(x))) << 16) | uint16_t(int16_t(y)));
  pointer_down_ = pressed;
}

int Runner::save_state(const std::string &state_path, const std::string &png_path) {
  int rc = -1;
  run_on_emu([&] {
    if (!core_) return;
    rc = dena_state_save_file(core_, state_path.c_str());
    if (rc == 0 && !png_path.empty()) dena_frame_write_png(current_frame(), png_path.c_str());
  });
  return rc;
}

int Runner::screenshot(const std::string &path) {
  int rc = -1;
  run_on_emu([&] {
    if (core_) rc = dena_frame_write_png(current_frame(), path.c_str());
  });
  return rc;
}

void Runner::set_cheats(std::vector<std::string> codes) {
  run_on_emu([&] {
    if (!core_) return;
    dena_core_cheats_reset(core_);
    if (hardcore_) return;
    for (size_t i = 0; i < codes.size(); i++)
      dena_core_cheat_set(core_, unsigned(i), 1, codes[i].c_str());
  });
}

int Runner::load_state(const std::string &state_path) {
  int rc = -1;
  if (hardcore_) {
    set_error("Loading states is off in hardcore mode");
    return rc;
  }
  run_on_emu([&] {
    if (!core_) return;
    rc = dena_state_load_file(core_, state_path.c_str());
    if (rc == 0 && rewind_) dena_rewind_clear(rewind_);
    next_due_ns_ = 0;
  });
  return rc;
}

void Runner::stop() {
  std::lock_guard<std::mutex> lk(life_mtx_);
  if (!thread_.joinable()) return;
  run_on_emu([this] { save_all(); });
  running_ = false;
  platform_->wake();
  thread_.join();
  close_audio();
  dena_rewind_destroy(rewind_);
  rewind_ = nullptr;
  dena_core_unload(core_);
  core_ = nullptr;
}

void Runner::set_buttons(int port, int mask, int64_t event_ns) {
  if (port < 0 || port >= DENA_MAX_PORTS) return;
  uint16_t prev = uint16_t(buttons_[port].exchange(uint32_t(mask)));
  if (prev != uint16_t(mask)) {
    int64_t expected = 0;
    // Only the first unserved change is timed; later ones within the same
    // frame are served by the same frame.
    pending_input_ns_.compare_exchange_strong(expected, event_ns);
  }
}

void Runner::set_touch(int mask, int64_t event_ns) {
  uint16_t prev = uint16_t(touch_buttons_.exchange(uint32_t(mask)));
  if (prev != uint16_t(mask)) {
    int64_t expected = 0;
    pending_input_ns_.compare_exchange_strong(expected, event_ns);
  }
}

void Runner::set_turbo(int mask, int half_frames) {
  turbo_half_ = half_frames < 1 ? 1 : half_frames;
  turbo_mask_ = uint32_t(mask) & 0xffffu;
}

std::string Runner::metrics_json() {
  std::lock_guard<std::mutex> lk(metrics_mtx_);
  char buf[768];
  auto fmt3 = [](const Samples &s, double a, double b, bool max) {
    char t[128];
    if (s.empty()) return std::string("null");
    std::snprintf(t, sizeof t, "{\"p50\":%.2f,\"p%s\":%.2f,\"max\":%.2f}", s.pct(a),
                  b == 95 ? "95" : "99", s.pct(b), max ? s.max() : 0.0);
    return std::string(t);
  };
  std::snprintf(
      buf, sizeof buf,
      "{\"frames\":%llu,\"input_to_post_ms\":%s,\"present_ms\":null,"
      "\"frame_interval_ms\":%s,\"missed_frames\":%u,\"audio_xruns\":%d,"
      "\"audio_underruns\":%u,\"audio_buffer_ms\":%.1f,\"audio_rate\":%d}",
      (unsigned long long)frames_, fmt3(input_to_post_, 50, 95, true).c_str(),
      fmt3(frame_interval_, 50, 99, true).c_str(), missed_,
      audio_open_ ? platform_->audio_xruns() : 0,
      ring_.buf ? atomic_load(&ring_.underruns) : 0u,
      out_rate_ ? 1000.0 * dena_ring_fill(&ring_) / out_rate_ : 0.0, out_rate_);
  return buf;
}

int Runner::pixel(int x, int y) {
  std::lock_guard<std::mutex> lk(frame_mtx_);
  if (x < 0 || y < 0 || x >= int(last_w_) || y >= int(last_h_)) return -1;
  return int(last_frame_[size_t(y) * last_w_ + size_t(x)]);
}

void Runner::reset_metrics() {
  std::lock_guard<std::mutex> lk(metrics_mtx_);
  input_to_post_ = Samples(256);
  frame_interval_ = Samples(600);
  missed_ = 0;
  frames_ = 0;
  last_post_ns_ = 0;
  next_due_ns_ = 0;
  frame_input_ns_ = 0;
  pending_input_ns_ = 0;
}

void Runner::audio_sink(void *user, const int16_t *frames, size_t n) {
  static_cast<Runner *>(user)->push_audio(frames, n);
}

void Runner::push_audio(const int16_t *frames, size_t n) {
  if (!audio_open_ || speed_ > 1 || muted_) return;  // no audio while fast-forwarding or rewinding
  double mul = dena_rate_ctl_update(&rate_ctl_, dena_ring_fill(&ring_), target_frames_);
  size_t need = size_t(double(n) * out_rate_ / av_.sample_rate * 1.01) + 4;
  if (resampled_.size() < need * 2) resampled_.resize(need * 2);
  uint32_t m = dena_resample(&resampler_, frames, uint32_t(n), resampled_.data(),
                             uint32_t(need), mul);
  dena_ring_write(&ring_, resampled_.data(), m);
}

bool Runner::open_audio() {
  out_rate_ = platform_->open_audio();
  if (out_rate_ <= 0) {
    out_rate_ = 0;
    return false;
  }
  target_frames_ = uint32_t(out_rate_ * audio_target_ms_.load() / 1000);
  dena_ring_init(&ring_, target_frames_ * 4);
  std::vector<int16_t> silence(size_t(target_frames_) * 2, 0);
  dena_ring_write(&ring_, silence.data(), target_frames_);  // prefill
  dena_resampler_init(&resampler_, av_.sample_rate, out_rate_);
  dena_rate_ctl_init(&rate_ctl_, 0.005);
  audio_open_ = true;
  if (!platform_->start_audio()) {
    close_audio();
    return false;
  }
  return true;
}

void Runner::close_audio() {
  if (audio_open_) platform_->close_audio();
  audio_open_ = false;
  out_rate_ = 0;
  dena_ring_free(&ring_);
}

// ---- emulator thread ----

void Runner::thread_main() {
  platform_->thread_begin();
  bool gpu = !hw_ || start_gpu();
  if (!gpu) running_ = false;
  platform_->video_begin(hw_, gpu);
  gpu_ready_->set_value(gpu);
  gpu_ready_ = nullptr;
  frame_period_ns_ = int64_t(1e9 / (av_.fps > 0 ? av_.fps : 60.0));
  while (running_) {
    run_commands();
    platform_->wait(platform_->has_surface() && !paused_);
  }
  run_commands();
  if (platform_->gpu_ready()) {
    if (hw_) dena_core_hw_context_destroy(core_);
    platform_->stop_gpu();
  }
  platform_->thread_end();
}

bool Runner::start_gpu() {
  unsigned w = std::max(av_.max_width, 1u), h = std::max(av_.max_height, 1u);
  if (!platform_->start_gpu(w, h, hw_info_.depth, hw_info_.stencil)) {
    log_error("GPU rendering could not start (EGL/GLES 3)");
    return false;
  }
  dena_core_hw_context_reset(core_);
  return true;
}

void Runner::repaint() {
  if (core_ && (hw_ || dena_core_frame(core_)->pixels)) draw_frame();
}

uintptr_t Runner::hw_framebuffer(void *self) {
  return static_cast<Runner *>(self)->platform_->gpu_framebuffer();
}

void *Runner::hw_proc_address(void *self, const char *sym) {
  return static_cast<Runner *>(self)->platform_->gl_proc_address(sym);
}

const dena_frame *Runner::current_frame() {
  unsigned w, h;
  if (!hw_ || !dena_core_hw_frame(core_, &w, &h)) return dena_core_frame(core_);
  if (!platform_->read_pixels(w, h, hw_info_.bottom_left_origin, readback_))
    return dena_core_frame(core_);
  readback_frame_ = dena_frame{w, h, readback_.data()};
  return &readback_frame_;
}

void Runner::run_commands() {
  std::deque<std::function<void()>> todo;
  {
    std::lock_guard<std::mutex> lk(cmd_mtx_);
    todo.swap(cmds_);
  }
  for (auto &c : todo) c();
}

void Runner::reject_state() {
  // Keep the rejected state for diagnosis and start fresh.
  log_error("saved state rejected: ", state_path_.c_str());
  std::rename(state_path_.c_str(), (state_path_ + ".bad").c_str());
}

void Runner::retry_state_load() {
  if (dena_state_load_file(core_, state_path_.c_str()) == 0) {
    state_retries_ = 0;
    if (rewind_) dena_rewind_clear(rewind_);
  } else if (--state_retries_ == 0) {
    reject_state();
  }
}

void Runner::save_all() {
  if (!core_) return;
  // A state still waiting to load must not be overwritten by the fresh boot.
  if (state_retries_ > 0) return;
  if (!srm_path_.empty() && dena_battery_save(core_, srm_path_.c_str()) == 0)
    last_battery_hash_ = dena_battery_hash(core_);
  if (!state_path_.empty() && dena_state_save_file(core_, state_path_.c_str()) < 0)
    log_error("auto-save state failed: ", state_path_.c_str());
}

int Runner::on_vsync(int64_t vsync_ns) {
  if (!running_ || paused_) return 0;
  if (!platform_->has_surface()) {  // no surface: resync timing when it returns
    next_due_ns_ = 0;
    return 0;
  }
  if (next_due_ns_ == 0 || vsync_ns - next_due_ns_ > 100000000LL) {
    next_due_ns_ = vsync_ns;  // start, or resync after a stall
  }
  // Run every core frame due by this vsync (allowing 2 ms early), so
  // 90/120 Hz panels keep native speed; fast-forward runs speed_ times as many.
  int speed = speed_;
  int due = 0, guard = 0;
  while (vsync_ns + 2000000LL >= next_due_ns_ && guard++ < 3) {
    due++;
    next_due_ns_ += frame_period_ns_;
  }
  int64_t t0 = perf_log_ ? now_ns() : 0;
  bool rewind = rewinding();
  if (rewind) {
    for (int i = 0; i < due; i++) rewind_one_frame();
  } else {
    for (int i = 0; i < due * speed; i++) run_one_frame();
  }
  int64_t t1 = perf_log_ ? now_ns() : 0;
  if (due) present();
  if (perf_log_) perf_sample(vsync_ns, rewind ? 0 : due * speed, due > 0, t1 - t0, now_ns() - t1);
  if (vsync_ns - last_battery_check_ns_ > kBatteryCheckNs) {
    last_battery_check_ns_ = vsync_ns;
    uint64_t h = dena_battery_hash(core_);
    if (h != last_battery_hash_ && !srm_path_.empty() &&
        dena_battery_save(core_, srm_path_.c_str()) == 0)
      last_battery_hash_ = h;
  }
  return rewind ? due : due * speed;
}

// performance.md, Measuring: emulated frames per second, frames shown, and
// the time the core and the presenter take per vsync, over ~5 s windows.
void Runner::perf_sample(int64_t vsync_ns, int frames, bool shown, int64_t run_ns,
                         int64_t present_ns) {
  PerfWindow &w = perf_;
  if (w.start_ns == 0 || vsync_ns < w.start_ns) {
    w = PerfWindow{};
    w.start_ns = vsync_ns;
    return;
  }
  w.vsyncs++;
  w.frames += frames;
  if (shown) {
    w.shown++;
    w.present_ns += present_ns;
    w.present_max_ns = std::max(w.present_max_ns, present_ns);
  }
  if (frames) {
    w.run_ns += run_ns;
    w.run_max_ns = std::max(w.run_max_ns, run_ns / frames);
  }
  int64_t span = vsync_ns - w.start_ns;
  if (span < 5000000000LL) return;
  double s = double(span) / 1e9;
  char line[256];
  std::snprintf(line, sizeof line,
                "perf: %.1f core fps, %.1f shown fps, %.1f vsyncs/s, core %.2f ms/frame "
                "(max %.2f), present %.2f ms (max %.2f)",
                w.frames / s, w.shown / s, w.vsyncs / s,
                w.frames ? double(w.run_ns) / 1e6 / w.frames : 0.0, double(w.run_max_ns) / 1e6,
                w.shown ? double(w.present_ns) / 1e6 / w.shown : 0.0,
                double(w.present_max_ns) / 1e6);
  perf_log_(line);
  w = PerfWindow{};
  w.start_ns = vsync_ns;
}

bool Runner::rewinding() const {
  if (!rewind_) return false;  // rewind off for this core: L2 is just a button
  if (hardcore_) return false;
  if (rewind_hold_) return true;
  if (!l2_rewind_) return false;
  for (const auto &b : buttons_)
    if (b.load() & kL2) return true;
  return false;
}

void Runner::reset_rewind() {
  dena_rewind_destroy(rewind_);
  rewind_ = nullptr;
  rewind_tick_ = 0;
  // No rewind when the core can't serialize, or when a state is so large
  // (PPSSPP, ~40 MB) that capturing every few frames would stall the game and
  // the budget could not hold two of them (rewind.md).
  size_t size = dena_core_state_size(core_);
  if (size == 0 || size > kRewindBudget / 2) {
    rewind_state_.clear();
    rewind_state_.shrink_to_fit();
    return;
  }
  rewind_state_.assign(size, 0);
  rewind_ = dena_rewind_create(kRewindBudget);
}

void Runner::capture_rewind() {
  if (!rewind_ || !rewind_enabled_ || hardcore_ || ++rewind_tick_ % kRewindInterval) return;
  size_t size = dena_core_state_size(core_);
  if (size != rewind_state_.size()) rewind_state_.assign(size, 0);
  if (size && dena_core_save_state(core_, rewind_state_.data(), size) == 0)
    dena_rewind_push(rewind_, rewind_state_.data(), size);
}

// One backwards step every kRewindInterval frames; the restored state is run
// for one frame (no input, muted) so its picture can be shown.
void Runner::rewind_one_frame() {
  if (!rewind_ || ++rewind_tick_ % kRewindInterval) return;
  size_t size = rewind_state_.size();
  if (dena_rewind_step_back(rewind_, rewind_state_.data(), size) != 0) return;
  dena_core_load_state(core_, rewind_state_.data(), size);
  for (int p = 0; p < DENA_MAX_PORTS; p++) dena_core_set_buttons(core_, unsigned(p), 0);
  muted_ = true;
  dena_core_run_frame(core_);
  muted_ = false;
  // That frame moved the core past the capture: reload it so resuming
  // continues from the captured point (it is now the buffer's newest).
  dena_core_load_state(core_, rewind_state_.data(), size);
}

// Emulator thread: the first frame after hardcore turns on drops what it bans.
void Runner::apply_hardcore() {
  if (hardcore_ == hardcore_applied_) return;
  hardcore_applied_ = hardcore_;
  if (!hardcore_applied_) return;
  dena_core_cheats_reset(core_);
  if (rewind_) dena_rewind_clear(rewind_);
}

void Runner::run_one_frame() {
  apply_hardcore();
  capture_rewind();
  // Turbo buttons read as released on the off half of each cycle. The cycle
  // restarts while none is held, so a tap always lands on an "on" frame.
  uint32_t masks[DENA_MAX_PORTS], held = 0;
  uint32_t turbo = turbo_mask_.load();
  for (int p = 0; p < DENA_MAX_PORTS; p++) {
    masks[p] = buttons_[p].load() | (p == 0 ? touch_buttons_.load() : 0u);
    if (l2_rewind_) masks[p] &= ~uint32_t(kL2);
    held |= masks[p];
  }
  if (!(held & turbo)) turbo_tick_ = 0;
  bool turbo_off = (turbo_tick_++ / unsigned(turbo_half_.load())) % 2 == 1;
  for (int p = 0; p < DENA_MAX_PORTS; p++) {
    uint32_t mask = masks[p];
    if (turbo_off) mask &= ~turbo;
    dena_core_set_buttons(core_, unsigned(p), uint16_t(mask));
  }
  for (int p = 0; p < DENA_MAX_PORTS; p++) {
    uint64_t a = analog_[p].load();
    if (p == 0 && touch_analog_.load()) a = touch_analog_.load();
    for (unsigned s = 0; s < 2; s++)
      dena_core_set_analog(core_, unsigned(p), s, int16_t(a >> (32 * s)),
                           int16_t(a >> (32 * s + 16)));
  }
  uint32_t ptr = pointer_.load();
  dena_core_set_pointer(core_, int16_t(ptr >> 16), int16_t(ptr & 0xffff), pointer_down_);
  int64_t input_ns = pending_input_ns_.exchange(0);
  if (input_ns) frame_input_ns_ = input_ns;
  sync_ram_before();
  dena_core_run_frame(core_);
  sync_ram_after();
  if (frame_hook_) frame_hook_(core_);
  frames_++;
  if (state_retries_ > 0) retry_state_load();
}

void Runner::watch_ram(size_t offset, size_t len) {
  std::lock_guard<std::mutex> lk(ram_mtx_);
  ram_offset_ = offset;
  ram_len_ = len;
  ram_snapshot_.clear();
}

bool Runner::read_ram(uint8_t *out, size_t len) {
  std::lock_guard<std::mutex> lk(ram_mtx_);
  if (ram_snapshot_.empty() || len > ram_snapshot_.size()) return false;
  std::memcpy(out, ram_snapshot_.data(), len);
  return true;
}

void Runner::write_ram(size_t offset, const uint8_t *data, size_t len) {
  std::lock_guard<std::mutex> lk(ram_mtx_);
  ram_writes_.emplace_back(offset, std::vector<uint8_t>(data, data + len));
}

// Emulator thread: queued writes that fit the core's system RAM go in.
void Runner::sync_ram_before() {
  std::lock_guard<std::mutex> lk(ram_mtx_);
  if (ram_writes_.empty()) return;
  size_t size = 0;
  auto *ram = static_cast<uint8_t *>(dena_core_memory(core_, 2 /* RETRO_MEMORY_SYSTEM_RAM */, &size));
  for (auto &w : ram_writes_)
    if (ram && w.first <= size && w.second.size() <= size - w.first)
      std::memcpy(ram + w.first, w.second.data(), w.second.size());
  ram_writes_.clear();
}

void Runner::sync_ram_after() {
  std::lock_guard<std::mutex> lk(ram_mtx_);
  if (!ram_len_) return;
  size_t size = 0;
  auto *ram = static_cast<uint8_t *>(dena_core_memory(core_, 2 /* RETRO_MEMORY_SYSTEM_RAM */, &size));
  if (!ram || ram_offset_ > size || ram_len_ > size - ram_offset_) return;
  ram_snapshot_.assign(ram + ram_offset_, ram + ram_offset_ + ram_len_);
}

void Runner::present() {
  if (!draw_frame()) return;
  int64_t posted = now_ns();
  std::lock_guard<std::mutex> ml(metrics_mtx_);
  if (frame_input_ns_) {
    input_to_post_.add(double(posted - frame_input_ns_) / 1e6);
    frame_input_ns_ = 0;
  }
  if (last_post_ns_) {
    double interval = double(posted - last_post_ns_) / 1e6;
    frame_interval_.add(interval);
    if (interval > 1.5 * double(frame_period_ns_) / 1e6) missed_++;
  }
  last_post_ns_ = posted;
}

bool Runner::draw_frame() {
  int direction = rewinding() ? -1 : 1;
  if (hw_) {
    unsigned w, h;
    if (!dena_core_hw_frame(core_, &w, &h)) return false;
    return platform_->draw_gpu(w, h, hw_info_.bottom_left_origin, direction);
  }
  const dena_frame *f = dena_core_frame(core_);
  if (!f->pixels || f->width == 0) return false;
  {
    std::lock_guard<std::mutex> lk(frame_mtx_);
    last_frame_.assign(f->pixels, f->pixels + size_t(f->width) * f->height);
    last_w_ = f->width;
    last_h_ = f->height;
  }
  return platform_->draw_software(*f, direction);
}

}  // namespace dena
