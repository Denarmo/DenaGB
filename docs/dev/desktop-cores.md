# Desktop cores (Windows and SteamOS)

How the libretro cores for the Windows and SteamOS versions are built. Plan:
the desktop port plan, section 2. Per the project rules these builds run on
DENA-PC in WSL2 Debian during the combined desktop test pass, never in the
cloud; cloud threads only check the scripts (`--dry-run`, shellcheck) and may
smoke-build one small core.

## Targets

| Target | Output | Toolchain |
| --- | --- | --- |
| `win64` | `cores/build/win64/<core>_libretro.dll` | MinGW-w64 cross compiler, posix threads (`x86_64-w64-mingw32-gcc-posix`), runtime linked statically |
| `linux-x86_64` | `cores/build/linux-x86_64/<core>_libretro.so` | gcc inside the freedesktop Flatpak SDK (`cores/desktop-runtime.txt`, now 26.08) |

Linux cores are built inside the same SDK the SteamOS Flatpak runs on, so they
link against that runtime's glibc and libraries and run on SteamOS and any
other distro with the Flatpak. The Flatpak manifest must use the `runtime=`
line of `cores/desktop-runtime.txt`.

## Cores per target

| System | Core (script) | win64 | linux-x86_64 | Notes |
| --- | --- | --- | --- | --- |
| NES | FCEUmm (`fceumm`) | yes | yes | |
| SNES | bsnes (`bsnes`) | yes | yes | |
| GB/GBC/GBA | mGBA (`mgba`) | yes | yes | link cable hooks as on Android |
| PICO-8 | fake-08 (`fake08`) | yes | yes | same fixups as on Android |
| PlayStation | Beetle PSX HW (`beetle_psx`) | yes | yes | `HAVE_HW=1`: OpenGL + Vulkan, Lightrec x86_64 dynarec. PCSX ReARMed stays ARM only and refuses desktop targets |
| Saturn | Beetle Saturn (`beetle_saturn`) | yes | yes | new core, software renderer |
| DS | melonDS (`melonds`) | yes | yes | x86_64 JIT, desktop OpenGL renderer |
| N64 | Mupen64Plus-Next (`mupen64plus`) | yes | yes | x86_64 dynarec (needs `nasm`), GLideN64 on desktop OpenGL |
| Dreamcast | Flycast (`flycast`) | yes | yes | new core, x86_64 dynarec, OpenGL + Vulkan |
| PSP | PPSSPP (`ppsspp`) | yes, no FFmpeg | yes | x86_64 JIT. win64 builds without FFmpeg: PPSSPP's prebuilt FFmpeg does not link with MinGW, so PSP video cutscenes stay black on Windows until that is solved |

Not here: LRPS2 and Dolphin (later threads), 3DS (waits for the owner's legal
sign-off). Every core's licence row is in `docs/licenses.md`; all builds use
the same pinned commits as the other targets.

## Setup on DENA-PC (WSL2 Debian, once)

```sh
sudo apt install build-essential cmake nasm ccache git mingw-w64 flatpak
sudo update-alternatives --set x86_64-w64-mingw32-gcc /usr/bin/x86_64-w64-mingw32-gcc-posix
sudo update-alternatives --set x86_64-w64-mingw32-g++ /usr/bin/x86_64-w64-mingw32-g++-posix
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub org.freedesktop.Sdk/x86_64/26.08
```

The scripts pick the `-posix` compilers by name, so the alternatives step is
only for builds outside these scripts. The SDK brings its own gcc, cmake,
nasm, git and ccache.

Build from the Linux file system (for example `~/src/Dena.emu`, a worktree
per thread), not from `/mnt/c`: builds on the Windows drive are many times
slower.

## Building

```sh
cores/build-desktop.sh win64                  # all cores, MinGW cross build
cores/build-desktop.sh linux-x86_64           # all cores, inside the Flatpak SDK
cores/build-desktop.sh linux-x86_64 --native  # host gcc, quick checks only
cores/build-desktop.sh win64 flycast melonds  # just these cores
cores/build-desktop.sh --dry-run win64        # print every command, change nothing
cores/flycast/build.sh --target win64         # one core directly
```

`build-desktop.sh` builds every core even when one fails and lists the
failures at the end. Each per-core script also takes `--dry-run` and
`--target <t>` (or the target as the first argument, like the other targets).

## ccache

Every desktop compile goes through `ccache` when it is installed (set
`DENA_CCACHE=0` to turn it off). The cache is `$CCACHE_DIR` or
`~/.cache/ccache`; the Flatpak build mounts the same directory into the SDK, so
both targets and repeated passes share it. A good size for all ten cores and
both targets: `ccache -M 20G`. Objects stay under `cores/build/obj/<core>-<target>`
(a copy of the tracked sources per target), so unchanged cores also skip make's
work entirely.

## Checks the scripts do

- The checkout is the pinned commit (or tag) from `docs/licenses.md`.
- After the build the library is stripped. A win64 DLL that still imports the
  MinGW runtime (`libgcc_s`, `libstdc++`, `libwinpthread`, `libgomp`) fails the
  build: the Windows app ships each core as one DLL. Linux builds print the
  `.so`'s `NEEDED` libraries, which should all be in the freedesktop runtime.

## Files

- `cores/desktop.sh`: shared helpers (target parsing, dry run, toolchains,
  ccache, library check), sourced by the core scripts.
- `cores/libretro-make.sh`: Makefile cores; desktop variables `X64_MAKE`,
  `WIN64_MAKE`, `LINUX64_MAKE`, `DESKTOP_SKIP`.
- `tools/toolchain/x86_64-w64-mingw32.cmake`: CMake toolchain for the CMake
  cores (mGBA, Flycast, PPSSPP).
- `cores/desktop-runtime.txt`: the Flatpak SDK and runtime.
- `tools/toolchain/test_desktop_cores.py`: dry-run test for every core and
  target (runs with `tools/ci/local.sh rig`).
