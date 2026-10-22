# Spec: RetroAchievements

Status: implemented (Android). Linux handhelds get it once their launcher
links the achievements library (`host/achievements`); the app hides the
feature wherever the native client is missing.

## Behaviour

**Account (Settings → Achievements → RetroAchievements).** Username and
password sign in through rcheevos (`login2`). Only the returned token is kept,
in `<dataDir>/retroachievements.json` with the hardcore choice; the password
is never stored. The token signs in again on the first game or game page of a
launch. A token the server rejects signs the user out; a network failure keeps
the account and retries next time. Sign out forgets the token.

**Hardcore mode** (on by default, like the site). Applies to the next game; it
can't change mid-session. In a hardcore session:
- the auto-save state is not resumed (the battery save still loads);
- the pause sheet has Save but no Load, Rewind or Cheats;
- the runner itself refuses state loads and rewind and clears cheats once the
  game is confirmed (`Runner::set_hardcore`), so no other path gets round it.
Fast-forward stays allowed (RetroAchievements allows it).

**Session.** After the core starts, the app passes the ROM path and the
system's RetroAchievements console id; rcheevos hashes the file and loads the
game's set. Toasts at the top of the game:
- "N of M achievements unlocked · Hardcore" when the game is identified;
- "This game file isn't recognised" when the hash is unknown;
- each unlock with its badge, title and points;
- mastery; offline / back online (unlocks queue in rcheevos and retry).
The pause sheet shows "N of M achievements" when a set loaded; it opens the
list (unlocked first, measured progress such as 3/10 for locked ones).

**Game page.** The game sheet has Achievements for systems with
RetroAchievements support (NES, SNES, GB, GBC, GBA, N64, DS, PSX, PSP; not
PICO-8). It hashes the file, fetches `achievementsets` and the user's hardcore
and softcore unlocks, and lists badge, title, description, points and unlock
state. Errors: not signed in (Sign in button), offline (Try again), unknown
file.

## Design

```
Dart RetroAchievements ── dart:ffi ── host/achievements (rc_client) ── Runner frame hook
   │ HTTP (dart:io)                         │ events as JSON
   └── retroachievements.org ◄──────────────┘
```

- One process-wide `rc_client`. Its `server_call` queues requests; Dart takes
  them (`dena_ra_take_request`), sends them with `HttpClient` and hands back
  status and body (`dena_ra_respond`). Results come back as JSON events
  (`dena_ra_take_event`). Dart polls every 100 ms only while something is
  pending (login, fetch, session, request in flight).
- Strings go in as NUL-separated fields in one native buffer; no `package:ffi`.
- Memory: the host now keeps the core's `RETRO_ENVIRONMENT_SET_MEMORY_MAPS`
  (`dena_core_memory_map`); `rc_libretro_memory_init` builds the address map
  from it or from `retro_get_memory_data`. Background memory reads are off, so
  memory is only read in `rc_client_do_frame` on the emulator thread.
- `Runner::set_frame_hook` calls `dena_ra_frame` after every played frame
  (rewound frames are not evaluated); the Android shell also mirrors
  `dena_ra_hardcore_active()` into `Runner::set_hardcore`.
- A paused session keeps rcheevos' queue moving with `rc_client_idle`
  (`dena_ra_pump` when no frame ran for a second).
- Game identification and game-page hashing run on their own threads (large
  disc images).
- The session ends (`rc_client_unload_game`, memory map dropped) before the
  core stops.
- User-Agent: `Dena.emu/<version> (<os>) rcheevos/<x.y>`.

## Edge cases

- Zipped ROMs that the importer kept as `.zip`: rcheevos hashes the archive
  only for systems where that is the rule, so most show as unrecognised.
- A game that loses its connection mid-session: unlocks are retried by
  rcheevos; the toast says so.
- Unloading while a mastery event is pending crashed rcheevos 12.5
  (NULL game); patched locally, see `host/third_party/rcheevos/README.md`.

## Not yet

Leaderboards, rich presence display, challenge/progress indicators, subsets
on the game page, unofficial achievements, and RetroAchievements' list of
approved emulators (until Dena.emu is on it, the server may treat hardcore
unlocks from it as softcore).

## Tests

- `host/achievements/achievements_tests.cpp` (CTest `achievements`): fake
  server; wrong then right password; game page list with unlocks; hardcore
  session on the testcore that unlocks an achievement when RAM changes;
  session end clears hardcore.
- `app/test/achievements/achievements_test.dart`: token-only storage, rejected
  token, HTTP hand-off and User-Agent, game page list, settings sign-in and
  hardcore switch, hardcore session (no resume, no Load/Rewind/Cheats, toast,
  list, end before stop).
