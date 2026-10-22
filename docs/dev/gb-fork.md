# Dena.emu GB fork

Dena.emu GB (github.com/Denarmo/Dena.emu-GB) is a fork of Dena.emu with the
full history. It plays only Game Boy, Game Boy Color, Game Boy Advance and DS
games, uses the Pocket LCD look, and lays a dot matrix LCD filter over every
game. It keeps the game library and the settings for playing games.

## What the fork removes

| Removed | Paths |
| --- | --- |
| PICO-8 runtime, Carts tab, Dena Explore | `app/lib/src/carts`, `app/lib/src/library/carts_tab.dart`, `cores/fake08` |
| Built-in apps (music, video), XMB media | `app/lib/src/apps`, `app/lib/src/media` |
| Web file manager | `app/lib/src/webfiles` |
| RomM | `app/lib/src/romm` |
| Cloud sync and its backend, Google sign-in and the background sync worker in the Android shell | `app/lib/src/premium`, `backend/`, `shells/android/**/{GoogleAuth,SyncWorker,AuthApi.g}.kt`, `shells/android/pigeons/auth_api.dart`, `docs/specs/premium.md` |
| Latency spike screen | `app/lib/src/spike`, `app/integration_test/spike_test.dart` |
| Cores other than mGBA and melonDS | `cores/{beetle_psx,beetle_saturn,bsnes,fceumm,flycast,mupen64plus,pcsx_rearmed,ppsspp}` |

The matching tests under `app/test/` are removed with them. The removed
systems stay in the `GameSystem` enum so database ids and upstream code keep
compiling; `supportedSystems` in `app/lib/src/library/import_rules.dart`
decides what is imported and shown.

`os/` and `shells/linux/` are kept unchanged for now. They still name the
removed cores, so the handheld image is not built from this fork yet.

## Fork-only files

These differ from upstream on purpose. Keep the fork's side when they conflict.

- `app/lib/main.dart`, `app/lib/src/app.dart`, `app/lib/src/shell/app_shell.dart`
- `app/lib/src/session/session_screen.dart` (`coreLibraries`)
- `app/lib/src/library/import_rules.dart`, `app/lib/src/library/importer.dart`
- `app/android/app/build.gradle.kts` (`applicationId app.dena.emu.gb`),
  `app/android/app/src/main/AndroidManifest.xml` (launcher label "DenaGB", short so home screens never cut it to "Dena.emu…"), `app/pubspec.yaml`
- Play links and game shortcuts use `denagb://play/<sha1>` (`GameShortcuts.kt`
  `PlayLink`, the app manifest, shortcuts.md) so they never open the main app's
  chooser when both apps are installed
- `shells/android/android/build.gradle.kts` (core list),
  `shells/android/.../CoreAssets.kt`, `host/CMakeLists.txt` (core tests)
- Pocket LCD theme and widgets, and the dot matrix presets (added later)
- This file, `tools/fork/` and the fork note at the top of `CLAUDE.md`
- No Google sign-in or background sync: `DenaAndroidPlugin.kt`,
  `shells/android/lib/dena_android.dart`, `consumer-rules.pro`, the app
  manifest (no backup rules), `README.md`, and no paid tier in `CLAUDE.md`

## Merging upstream fixes

One-time setup in a clone of the fork:

```sh
git remote add upstream https://github.com/Denarmo/Dena.emu.git
```

Each merge, on a branch:

```sh
git fetch upstream main
git checkout -b merge-upstream origin/main
git merge upstream/main
tools/fork/redelete.sh      # re-deletes paths the fork removed
# fix the remaining conflicts by hand, mostly in the fork-only files above
cd app && flutter analyze && flutter test
```

Most conflicts are "modify/delete": upstream changed a file the fork removed.
`tools/fork/redelete.sh` resolves those by deleting the file again. If
upstream adds a new file inside a removed folder, the script deletes that too.
Upstream features for removed systems or services need nothing more. Fixes
in shared code (library, session, shaders, skins, input, host) merge as usual.

Merge, don't rebase or cherry-pick, so later merges only see new upstream
commits.

## Public repository

The fork is published as a separate public repository holding one fresh
commit per release, never this repository's history (which carries the main
app's full history and pull request refs). To update it, export the tree of
`main` with `tools/fork/public-snapshot.sh` and push that commit. Releases are
made there; this repository stays private.
