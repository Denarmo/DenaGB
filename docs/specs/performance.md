# Emulation performance

Goal (CLAUDE.md §1): stable 60 fps, input-to-photon under 50 ms, no audio crackle.

## Emulator thread scheduling (Android)

- The emulator thread (Choreographer-paced, `shells/android/.../runner.cpp`) sets
  its nice value to -10 at start, above normal app threads and equal to
  display-urgent work, so GC, decoding and sync work cannot delay a frame.
  Failure is logged and ignored.
- On API 33+ it opens an ADPF performance-hint session (`APerformanceHint_*`,
  resolved with `dlsym`; minSdk is 26) with a 16.67 ms target and reports the
  wall time of each vsync's work (`Runner::on_vsync`). The governor then
  raises clocks before frames are missed. Older devices skip this silently.
- The session closes when the emulator thread ends.

## Measuring

Android reads three debug properties at each game start, set over adb with
`adb shell setprop debug.dena.<name> <value>` (they reset at reboot):

| Property | Effect |
| --- | --- |
| `debug.dena.perf=1` | Every ~5 s of play, logcat tag `Dena` gets `perf: <core fps>, <shown fps>, <vsyncs/s>, core <ms/frame> (max), present <ms> (max)` (`Runner::set_perf_log`). |
| `debug.dena.core_options=k=v;k=v` | Core options set after Dena's own (`Runner::set_extra_options`), e.g. `melonds_jit_fast_memory=enabled;melonds_threaded_renderer=disabled`. |
| `debug.dena.shader=off` | The session draws without a shader (CPU blit for software cores). |

A game starts without a tap through its link:
`adb shell am start -a android.intent.action.VIEW -n app.dena.emu.gb/app.dena.dena_emu.MainActivity -d denagb://play/<sha1>`.
The app is `profileable` from the shell, so `simpleperf record --app
app.dena.emu.gb` works on release builds (Android 10+).

## Audio latency

Settings → Playback → Audio latency: 40 ms (Normal, default), 30 ms (Low),
20 ms (Lowest, may crackle). The runner clamps 20..80 ms and applies it when
audio opens at game start (`Runner::set_audio_latency_ms`). On Linux
handhelds the ALSA hardware buffer adds about half the setting on top
(handheld-session.md, Audio).

Device numbers (frame time p50/p99, dropped frames) come from the rig
(`tools/rig`) via `dumpsys gfxinfo` / the runner's frame stats; host numbers
from `dena-harness run` wall time per frame.

## Core compiler flags

Android cores built through `cores/libretro-make.sh` (FCEUmm, bsnes, melonDS,
PCSX ReARMed, fake-08) use `APP_OPTIM=release` and `-O3` instead of
ndk-build's default `-O2`. `ANDROID_OPT` overrides it (`ANDROID_OPT=-O2` to
compare). NEON is already on for arm64-v8a. LTO is left off until the
integrated phone pass shows the `-O3` result; mGBA and PPSSPP build with
CMake `Release` and are unchanged.

## DS (melonDS)

The 0.0.8 phone pass measured 43-51 fps on the Pokemon SoulSilver title at
73-80 % CPU (report-v0.0.8). The Android melonDS build has the ARM64 JIT on
(core default) but no OpenGL renderer, so the 3D software rasteriser ran on
the emulator thread. Dena now sets `melonds_threaded_renderer=enabled`, which
moves it to a second core. JIT branch and literal optimisations are already on
by default; fast memory stays off (ds.md).

Verify in the next combined pass: SoulSilver title for 60 s with SurfaceFlinger
timestats. Pass is >= 59 fps average and no new graphics glitches against 0.0.8
(compare a screenshot of the title and an overworld scene). If it is still
short, the next steps are a frame-skip option for DS and turning the OpenGL
ES renderer on at 1x for 3D-heavy games.

Cause of the 31 fps (DenaGB phone pass 2026-10-18, POCO F7 Ultra, Snapdragon 8
Elite, 120 Hz): the core ran at 60 fps with 11.7 ms per frame, but only ~29 vsync
callbacks per second reached the emulator thread, each running two frames
(`perf: 60.0 core fps, 29.4 shown fps`). The next frame callback was posted after
the vsync's work, so one late frame made the next vsync carry two frames, which
skipped the following vsync too: a lock at half the refresh rate, with audio
underruns. Android now posts the next callback before running the frames, reports
only vsyncs that ran the game to ADPF, and asks the surface for 60 Hz.

2x-4x DS (ds.md, Internal resolution) moves 3D to the GPU through melonDS's
OpenGL renderer on GLES 3.2, which also takes the 3D rasteriser off the CPU.
Its cost is the extra GPU fill and the per-frame texture uploads (VRAM and
palette, plus the 2D layers for the compositor). Measure in the combined pass
at each factor: SoulSilver title and an overworld scene for 60 s, fps average
and CPU %. Pass is >= 59 fps at 2x; 3x and 4x are reported, not gated.
