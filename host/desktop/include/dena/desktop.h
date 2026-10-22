/* SPDX-License-Identifier: GPL-3.0-or-later
 * The desktop host library (dena_host.dll / libdena_host.so): the shared
 * runner with an SDL3 platform, answering the session's Pigeon calls for the
 * stock Flutter Windows and Linux runners, plus the dart:ffi entry points.
 * The runners load it at run time (desktop_loader.h), so a build without it
 * still starts (no games). Spec: docs/specs/desktop-shell.md */
#ifndef DENA_DESKTOP_H
#define DENA_DESKTOP_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Bumped when a runner-facing function or struct changes. */
#define DENA_DESKTOP_API_VERSION 1

struct dena_desktop_config {
  uint32_t struct_size; /* sizeof(struct dena_desktop_config) */
  void *user;
  /* Any thread: a new game frame is ready (mark the texture available). */
  void (*frame_ready)(void *user);
  /* Any thread: send this Pigeon message to Dart. The runner copies it and
   * sends it from the platform thread; no reply is expected. */
  void (*send)(void *user, const char *channel, const uint8_t *msg, size_t len);
  /* Windows: the top-level HWND, so vsync follows the monitor it is on.
   * NULL elsewhere. */
  void *window;
  /* The display's refresh rate in mHz for clock pacing; 0 for 60 Hz.
   * Windows reads vblanks from DXGI and uses this only as a fallback. */
  int refresh_mhz;
};

/* Main thread, once. Returns DENA_DESKTOP_API_VERSION, or 0 when the
 * library could not start (no game sessions; the UI still runs). */
int dena_desktop_init(const struct dena_desktop_config *cfg);
/* Main thread: stops a running game (it saves first) and SDL. */
void dena_desktop_shutdown(void);

/* The GameHostApi channels to answer, one per line. Static storage. */
const char *dena_desktop_channels(void);
/* Main thread: a platform message from Dart on one of those channels.
 * Returns true when handled; *reply (free with dena_desktop_free) and
 * *reply_len hold the response. */
bool dena_desktop_message(const char *channel, const uint8_t *msg, size_t len, uint8_t **reply,
                          size_t *reply_len);
void dena_desktop_free(void *p);

/* Keys the runners pass to dena_desktop_key: 'A'..'Z' and '0'..'9' as
 * ASCII, the rest below. */
enum {
  DENA_DESKTOP_KEY_UP = 0x100,
  DENA_DESKTOP_KEY_DOWN,
  DENA_DESKTOP_KEY_LEFT,
  DENA_DESKTOP_KEY_RIGHT,
  DENA_DESKTOP_KEY_ENTER,
  DENA_DESKTOP_KEY_RSHIFT,
  DENA_DESKTOP_KEY_BACKSPACE,
  DENA_DESKTOP_KEY_ESCAPE,
  DENA_DESKTOP_KEY_SPACE,
  DENA_DESKTOP_KEY_TAB,
};
/* Main thread: a key went down or up. Returns true when a game took it
 * (it must not reach Flutter); false when no game is playing or the key is
 * not bound. */
bool dena_desktop_key(int key, bool down);

/* Main thread: the texture the runner registered for the game picture
 * (Dart shows it with Texture(textureId: dena_desktop_texture())). */
void dena_desktop_set_texture(int64_t id);
/* The display refresh changed (Linux: the window moved to a monitor). */
void dena_desktop_set_refresh(int refresh_mhz);

/* Raster thread, Linux (FlPixelBufferTexture): the newest frame as RGBA
 * bytes, valid until the next call; false before the first frame. */
bool dena_desktop_frame_rgba(const uint8_t **rgba, uint32_t *width, uint32_t *height);
/* Raster thread, Windows (GpuSurfaceTexture): the newest frame's D3D11
 * shared handle (B8G8R8A8, top row first), NULL before the first frame. */
void *dena_desktop_frame_d3d(uint32_t *width, uint32_t *height);

/* ---- dart:ffi (main isolate) ---- */

/* The game texture id, -1 when the runner registered none. */
int64_t dena_desktop_texture(void);
/* The storage root (desktop-shell.md, Storage): Bios/, Screenshots/ and
 * cores/ live under it. UTF-8. Before the first game. */
void dena_desktop_set_root(const char *path);
/* Gamepads connected now (desktop-shell.md, Controllers). */
int32_t dena_desktop_gamepads(void);
/* The runner's metrics JSON (latency-spike.md fields). Static storage,
 * valid until the next call. */
const char *dena_desktop_metrics(void);
/* Latency log (desktop-shell.md, Latency): while a game runs, one metrics
 * JSON line per second is appended to path; "" or NULL stops. */
void dena_desktop_latency_log(const char *path);

#ifdef __cplusplus
}
#endif
#endif
