// SPDX-License-Identifier: GPL-3.0-or-later
// Shared runner acceptance tests (docs/specs/shared-runner.md) with the test
// core and a fake platform: vsyncs are driven by hand, audio is a fake output.
// Usage: runner_tests <testcore> <tmpdir>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "runner.h"

namespace {

int failures = 0;

#define CHECK(cond)                                               \
  do {                                                            \
    if (!(cond)) {                                                \
      std::fprintf(stderr, "%s:%d: FAIL %s\n", __FILE__, __LINE__, #cond); \
      failures++;                                                 \
    }                                                             \
  } while (0)

class FakePlatform : public dena::RunnerPlatform {
 public:
  std::vector<uint64_t> shown;  // hash of every frame drawn (emulator thread)
  bool surface = true;
  int audio_rate = 48000;

  void wait(bool) override {
    std::unique_lock<std::mutex> lk(mtx_);
    cv_.wait_for(lk, std::chrono::milliseconds(20), [this] { return woken_; });
    woken_ = false;
  }
  void wake() override {
    std::lock_guard<std::mutex> lk(mtx_);
    woken_ = true;
    cv_.notify_all();
  }
  bool has_surface() override { return surface; }
  bool gpu = false;  // a GPU platform (hw-render.md); frames show as hash 0
  bool gpu_started = false;
  bool start_gpu(unsigned, unsigned, bool, bool) override { return gpu_started = gpu; }
  bool gpu_ready() override { return gpu_started; }
  uintptr_t gpu_framebuffer() override { return 0; }
  void *gl_proc_address(const char *) override { return nullptr; }
  void stop_gpu() override { gpu_started = false; }
  bool draw_software(const dena_frame &f, int) override {
    shown.push_back(dena_frame_hash(&f));
    return true;
  }
  bool draw_gpu(unsigned, unsigned, bool, int) override {
    shown.push_back(0);
    return true;
  }
  bool read_pixels(unsigned, unsigned, bool, std::vector<uint32_t> &) override { return false; }
  int open_audio() override { return audio_rate; }
  bool start_audio() override { return true; }
  void pause_audio() override {}
  void close_audio() override {}

 private:
  std::mutex mtx_;
  std::condition_variable cv_;
  bool woken_ = false;
};

const int64_t kPeriod = 16666667;  // the test core runs at 60 fps

struct Fixture {
  FakePlatform fake;
  dena::Runner runner{&fake};
  int64_t t = 1000000000LL;

  void vsync(int64_t step) {
    t += step;
    runner.run_on_emu([&] { runner.on_vsync(t); });
  }
  unsigned long long frames() {
    unsigned long long n = 0;
    std::sscanf(runner.metrics_json().c_str(), "{\"frames\":%llu", &n);
    return n;
  }
  double audio_ms() {
    std::string m = runner.metrics_json();
    double ms = -1;
    size_t at = m.find("\"audio_buffer_ms\":");
    if (at != std::string::npos) std::sscanf(m.c_str() + at, "\"audio_buffer_ms\":%lf", &ms);
    return ms;
  }
  uint64_t last() {
    uint64_t h = 0;
    runner.run_on_emu([&] { h = fake.shown.empty() ? 0 : fake.shown.back(); });
    return h;
  }
};

std::string g_core, g_dir, g_rom;

bool exists(const std::string &p) {
  FILE *f = std::fopen(p.c_str(), "rb");
  if (f) std::fclose(f);
  return f != nullptr;
}

void write_file(const std::string &p, const char *data) {
  FILE *f = std::fopen(p.c_str(), "wb");
  if (!f) return;
  std::fputs(data, f);
  std::fclose(f);
}

int start(Fixture &fx, const std::string &name) {
  return fx.runner.start(g_core, g_rom, g_dir, g_dir + "/" + name + ".srm",
                         g_dir + "/" + name + ".state");
}

void test_lifecycle() {
  std::remove((g_dir + "/life.state").c_str());
  std::remove((g_dir + "/life.srm").c_str());
  {
    Fixture fx;
    CHECK(start(fx, "life") == dena::Runner::kStartFresh);
    CHECK(start(fx, "life") == dena::Runner::kStartError);  // already running
    for (int i = 0; i < 5; i++) fx.vsync(kPeriod);
    fx.runner.stop();
    CHECK(exists(g_dir + "/life.state"));
  }
  {
    Fixture fx;
    CHECK(start(fx, "life") == dena::Runner::kStartResumed);
    fx.runner.stop();
  }
  write_file(g_dir + "/life.state", "not a state");
  std::remove((g_dir + "/life.state.bad").c_str());
  {
    Fixture fx;
    CHECK(start(fx, "life") == dena::Runner::kStartBadState);
    CHECK(exists(g_dir + "/life.state.bad"));
    fx.runner.stop();
  }
  {
    Fixture fx;
    CHECK(fx.runner.start(g_dir + "/no_such_core", g_rom, g_dir, "", "") ==
          dena::Runner::kStartError);
    CHECK(!fx.runner.error().empty());
  }
}

// Frames run in one second of vsyncs at the given display period.
unsigned long long frames_per_second(int64_t vsync_period) {
  Fixture fx;
  start(fx, "pace");
  int n = int(1000000000LL / vsync_period);
  for (int i = 0; i < n; i++) fx.vsync(vsync_period);
  unsigned long long f = fx.frames();
  fx.runner.stop();
  return f;
}

void test_pacing() {
  for (int64_t p : {kPeriod, int64_t(11111111), int64_t(8333333)}) {
    unsigned long long f = frames_per_second(p);
    if (f < 59 || f > 61) std::fprintf(stderr, "period %lld: %llu frames\n", (long long)p, f);
    CHECK(f >= 59 && f <= 61);
  }
  Fixture fx;
  start(fx, "pace");
  fx.vsync(kPeriod);
  unsigned long long f0 = fx.frames();
  fx.vsync(3 * kPeriod);  // a short hitch catches up (at most 3 per vsync)
  CHECK(fx.frames() - f0 == 3);
  f0 = fx.frames();
  fx.vsync(500000000LL);  // a long stall resyncs instead of racing
  CHECK(fx.frames() - f0 == 1);
  fx.runner.set_speed(3);
  f0 = fx.frames();
  for (int i = 0; i < 10; i++) fx.vsync(kPeriod);
  CHECK(fx.frames() - f0 == 30);
  fx.runner.set_speed(99);  // clamped to 8
  f0 = fx.frames();
  fx.vsync(kPeriod);
  CHECK(fx.frames() - f0 == 8);
  fx.runner.set_speed(1);
  fx.fake.surface = false;  // no surface: nothing runs
  f0 = fx.frames();
  fx.vsync(kPeriod);
  CHECK(fx.frames() == f0);
  fx.runner.stop();
}

void test_pause() {
  std::remove((g_dir + "/pause.state").c_str());
  std::remove((g_dir + "/pause.srm").c_str());
  Fixture fx;
  start(fx, "pause");
  fx.runner.set_buttons(0, 1 << 3, dena::now_ns());  // Start: changes battery RAM
  fx.vsync(kPeriod);
  fx.runner.set_buttons(0, 0, dena::now_ns());
  fx.vsync(kPeriod);
  fx.runner.pause();
  CHECK(fx.runner.paused());
  CHECK(exists(g_dir + "/pause.state"));
  CHECK(exists(g_dir + "/pause.srm"));
  unsigned long long f0 = fx.frames();
  fx.vsync(kPeriod);
  CHECK(fx.frames() == f0);
  fx.runner.resume();
  fx.vsync(kPeriod);
  CHECK(fx.frames() == f0 + 1);
  fx.runner.stop();
}

void test_rewind() {
  Fixture fx;
  start(fx, "rewind");
  for (int i = 0; i < 40; i++) fx.vsync(kPeriod);
  std::vector<uint64_t> history;
  fx.runner.run_on_emu([&] { history = fx.fake.shown; });
  auto seen = [&](uint64_t h) {
    for (uint64_t x : history)
      if (x == h) return true;
    return false;
  };
  uint64_t newest = history.back();
  fx.runner.set_rewinding(true);
  CHECK(fx.runner.rewinding());
  for (int i = 0; i < 8; i++) fx.vsync(kPeriod);
  uint64_t back = fx.last();
  CHECK(back != newest && seen(back));
  fx.runner.set_rewinding(false);
  fx.vsync(kPeriod);
  CHECK(seen(fx.last()));  // resumed from the captured point
  // L2 hold: a gamepad's L2 rewinds only when configured.
  fx.runner.set_buttons(0, 1 << 12, dena::now_ns());
  CHECK(!fx.runner.rewinding());
  fx.runner.configure_rewind(true, true);
  CHECK(fx.runner.rewinding());
  fx.runner.set_buttons(0, 0, dena::now_ns());
  CHECK(!fx.runner.rewinding());
  fx.runner.stop();
}

void set_env(const char *k, const char *v) {
#ifdef _WIN32
  _putenv_s(k, v ? v : "");
#else
  if (v) setenv(k, v, 1);
  else unsetenv(k);
#endif
}

std::string read_file(const std::string &p) {
  std::string out;
  FILE *f = std::fopen(p.c_str(), "rb");
  if (!f) return out;
  char buf[4096];
  size_t n;
  while ((n = std::fread(buf, 1, sizeof buf, f)) > 0) out.append(buf, n);
  std::fclose(f);
  return out;
}

// rewind.md: a state too large for the budget turns rewind off; L2 is then
// an ordinary button and the game keeps running.
void test_heavy_state() {
  set_env("DENA_TEST_STATE_PAD", "20000000");
  Fixture fx;
  start(fx, "heavy");
  for (int i = 0; i < 5; i++) fx.vsync(kPeriod);
  fx.runner.set_rewinding(true);
  CHECK(!fx.runner.rewinding());
  fx.runner.set_rewinding(false);
  fx.runner.configure_rewind(true, true);
  fx.runner.set_buttons(0, 1 << 12, dena::now_ns());
  CHECK(!fx.runner.rewinding());
  unsigned long long before = fx.frames();
  for (int i = 0; i < 3; i++) fx.vsync(kPeriod);
  CHECK(fx.frames() > before);
  fx.runner.stop();
  set_env("DENA_TEST_STATE_PAD", nullptr);
}

// game-session.md: a GPU core that refuses states during its boot resumes a
// few frames in, and the saved state is not overwritten before that.
void test_late_state() {
  set_env("DENA_TEST_HW", "1");
  std::string state = g_dir + "/late.state";
  std::remove(state.c_str());
  std::remove((state + ".bad").c_str());
  {
    Fixture fx;
    fx.fake.gpu = true;
    CHECK(start(fx, "late") == dena::Runner::kStartFresh);
    for (int i = 0; i < 10; i++) fx.vsync(kPeriod);
    fx.runner.stop();
  }
  std::string saved = read_file(state);
  CHECK(!saved.empty());
  set_env("DENA_TEST_LATE_STATE", "3");
  {
    Fixture fx;  // stopped before the core accepts the state
    fx.fake.gpu = true;
    CHECK(start(fx, "late") == dena::Runner::kStartResumed);
    fx.runner.stop();
    CHECK(read_file(state) == saved);
  }
  {
    Fixture fx;  // accepted once the core is ready
    fx.fake.gpu = true;
    CHECK(start(fx, "late") == dena::Runner::kStartResumed);
    for (int i = 0; i < 6; i++) fx.vsync(kPeriod);
    fx.runner.stop();
    CHECK(!exists(state + ".bad"));
    CHECK(read_file(state) != saved);  // saved again after resuming
  }
  set_env("DENA_TEST_LATE_STATE", nullptr);
  set_env("DENA_TEST_HW", nullptr);
}

void test_states_and_cheats() {
  Fixture fx;
  start(fx, "slot");
  for (int i = 0; i < 5; i++) fx.vsync(kPeriod);
  std::string slot = g_dir + "/slot1.state", png = g_dir + "/slot1.png";
  CHECK(fx.runner.save_state(slot, png) == 0);
  CHECK(exists(png));
  fx.vsync(kPeriod);
  uint64_t after_save = fx.last();
  for (int i = 0; i < 10; i++) fx.vsync(kPeriod);
  CHECK(fx.runner.load_state(slot) == 0);
  fx.vsync(kPeriod);
  CHECK(fx.last() == after_save);
  CHECK(fx.runner.load_state(g_dir + "/no_such.state") != 0);

  CHECK(fx.runner.load_state(slot) == 0);
  fx.runner.set_cheats({"REDSQUARE"});
  fx.vsync(kPeriod);
  CHECK(fx.last() != after_save);
  fx.runner.set_cheats({});
  CHECK(fx.runner.load_state(slot) == 0);
  fx.vsync(kPeriod);
  CHECK(fx.last() == after_save);
  CHECK(fx.runner.screenshot(g_dir + "/shot.png") == 0);
  CHECK(fx.runner.pixel(0, 0) >= 0);
  CHECK(fx.runner.pixel(-1, 0) == -1);
  fx.runner.stop();
}

// The RAM mailbox (pico8-launcher-cart.md): writes go in before a frame and
// the watched window is read back after it.
void test_ram_mailbox() {
  Fixture fx;
  start(fx, "ram");
  uint8_t got[2] = {0, 0};
  CHECK(!fx.runner.read_ram(got, 2));  // nothing watched yet
  fx.runner.watch_ram(0, 2);
  const uint8_t v = 41;
  fx.runner.write_ram(0, &v, 1);
  fx.runner.write_ram(255, got, 2);  // past the end: dropped
  fx.vsync(kPeriod);
  CHECK(fx.runner.read_ram(got, 2));
  CHECK(got[0] == 41 && got[1] == 42);
  CHECK(!fx.runner.read_ram(got, 3));  // larger than the window
  fx.runner.watch_ram(250, 10);         // window past the end: no snapshot
  fx.vsync(kPeriod);
  CHECK(!fx.runner.read_ram(got, 1));
  fx.runner.stop();
}

void test_audio() {
  Fixture fx;
  start(fx, "audio");
  double ms0 = fx.audio_ms();
  CHECK(ms0 > 30);  // prefilled
  for (int i = 0; i < 5; i++) fx.vsync(kPeriod);
  double ms1 = fx.audio_ms();
  CHECK(ms1 > ms0);  // nobody reads the fake output, so the ring fills
  fx.runner.set_speed(4);
  for (int i = 0; i < 5; i++) fx.vsync(kPeriod);
  CHECK(fx.audio_ms() == ms1);  // muted while fast-forwarding
  std::vector<int16_t> out(480 * 2);
  fx.runner.read_audio(out.data(), 480);
  CHECK(fx.audio_ms() < ms1);
  fx.runner.stop();

  Fixture silent;
  silent.fake.audio_rate = 0;  // no audio device: the game still runs
  CHECK(start(silent, "audio") >= 0);
  silent.vsync(kPeriod);
  CHECK(silent.frames() == 1);
  silent.runner.stop();
}

// performance.md, Measuring: one summary per ~5 s window of vsyncs.
void test_perf_log() {
  Fixture fx;
  std::vector<std::string> lines;
  fx.runner.set_perf_log([&](const char *l) { lines.push_back(l); });
  CHECK(start(fx, "perf") >= 0);
  for (int i = 0; i < 301; i++) fx.vsync(kPeriod);  // just over 5 s at 60 Hz
  fx.runner.stop();
  CHECK(lines.size() == 1);
  if (!lines.empty()) {
    double core = 0, shown = 0;
    CHECK(std::sscanf(lines[0].c_str(), "perf: %lf core fps, %lf shown fps", &core, &shown) == 2);
    CHECK(core > 59.0 && core < 61.0);
    CHECK(shown > 59.0 && shown < 61.0);
  }
}

}  // namespace

static void test_parse_options() {
  using Opts = std::vector<std::pair<std::string, std::string>>;
  CHECK(dena::Runner::parse_options("").empty());
  CHECK(dena::Runner::parse_options("a=1;b=two words;;=x;c") ==
        (Opts{{"a", "1"}, {"b", "two words"}}));
  CHECK(dena::Runner::parse_options("k=v=w") == (Opts{{"k", "v=w"}}));
}

// shaders.md, Upscale.
static void test_max_upscale() {
  CHECK(dena::Runner::max_upscale("/x/libmupen64plus_next_libretro.so") == 4);
  CHECK(dena::Runner::max_upscale("ppsspp_libretro.so") == 4);
  CHECK(dena::Runner::max_upscale("libpcsx_rearmed_libretro.so") == 2);
  CHECK(dena::Runner::max_upscale("libmgba_libretro.so") == 1);
  CHECK(dena::Runner::max_upscale("libmelonds_libretro.so") == 4);
  // ds.md, Internal resolution: 2x-4x also turn the OpenGL ES renderer on;
  // Auto keeps the software renderer.
  using Opts = std::vector<std::pair<std::string, std::string>>;
  CHECK(dena::Runner::upscale_options("libmelonds_libretro.so", 0).empty());
  CHECK(dena::Runner::upscale_options("libmelonds_libretro.so", 3) ==
        (Opts{{"melonds_opengl_resolution", "3x native (768x576)"},
              {"melonds_opengl_renderer", "enabled"}}));
  CHECK(dena::Runner::upscale_options("libmelonds_libretro.so", 9) ==
        (Opts{{"melonds_opengl_resolution", "4x native (1024x768)"},
              {"melonds_opengl_renderer", "enabled"}}));
  CHECK(dena::Runner::upscale_options("ppsspp_libretro.so", 2) ==
        (Opts{{"ppsspp_internal_resolution", "960x544"}}));
  CHECK(dena::Runner::upscale_options("libmgba_libretro.so", 2).empty());
}

int main(int argc, char **argv) {
  if (argc < 3) {
    std::fprintf(stderr, "usage: runner_tests <testcore> <tmpdir>\n");
    return 2;
  }
  g_core = argv[1];
  g_dir = argv[2];
  test_max_upscale();
  test_parse_options();
  g_rom = g_dir + "/test.rom";
  write_file(g_rom, "dena");
  test_lifecycle();
  test_pacing();
  test_pause();
  test_rewind();
  test_states_and_cheats();
  test_ram_mailbox();
  test_heavy_state();
  test_late_state();
  test_audio();
  test_perf_log();
  if (failures) {
    std::fprintf(stderr, "%d failure(s)\n", failures);
    return 1;
  }
  std::printf("runner: all passed\n");
  return 0;
}
