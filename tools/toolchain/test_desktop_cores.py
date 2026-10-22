#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Dry-run tests for the desktop core builds (docs/dev/desktop-cores.md).

Runs cores/build-desktop.sh --dry-run for both targets: no toolchain, network
or checkout is needed, and nothing is built or changed.
"""

import os
import shutil
import subprocess
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BASH = shutil.which("bash")

# Library each core script must produce on the desktop targets.
LIBS = {
    "fceumm": "fceumm_libretro",
    "mgba": "mgba_libretro",
    "fake08": "fake08_libretro",
    "bsnes": "bsnes_libretro",
    "beetle_psx": "mednafen_psx_hw_libretro",
    "beetle_saturn": "mednafen_saturn_libretro",
    "melonds": "melonds_libretro",
    "mupen64plus": "mupen64plus_libretro",
    "flycast": "flycast_libretro",
    "ppsspp": "ppsspp_libretro",
}


def run(*args):
    env = dict(os.environ, DENA_DRY_RUN="0")
    env.pop("FLATPAK_ID", None)
    return subprocess.run([BASH, *args], cwd=ROOT, env=env, capture_output=True,
                          text=True, timeout=120)


@unittest.skipUnless(BASH, "needs bash")
class DesktopCoresDryRun(unittest.TestCase):
    def check_target(self, target, ext, extra=()):
        p = run("cores/build-desktop.sh", "--dry-run", *extra, target)
        self.assertEqual(p.returncode, 0, p.stderr)
        for core, lib in LIBS.items():
            with self.subTest(core=core):
                self.assertIn(f"=== {core} ({target})", p.stdout)
                self.assertIn(f"built {ROOT}/cores/build/{target}/{lib}.{ext}", p.stdout)
        self.assertIn(f"dry run: {len(LIBS)} cores for {target}", p.stdout)
        self.assertFalse(os.path.exists(os.path.join(ROOT, "cores/build/obj/flycast-" + target)))
        return p.stdout

    def test_win64_uses_mingw(self):
        out = self.check_target("win64", "dll")
        self.assertIn("x86_64-w64-mingw32-g", out)
        self.assertIn("x86_64-w64-mingw32.cmake", out)
        self.assertIn("platform=win", out)
        self.assertIn("WITH_DYNAREC=x86_64", out)   # N64 dynarec
        self.assertIn("JIT_ARCH=x64", out)           # DS JIT
        self.assertIn("HAVE_HW=1", out)              # Beetle PSX HW
        self.assertIn("-DUSE_FFMPEG=OFF", out)       # PPSSPP on MinGW

    def test_linux_runs_inside_the_flatpak_sdk(self):
        out = self.check_target("linux-x86_64", "so")
        self.assertIn("flatpak run", out)
        with open(os.path.join(ROOT, "cores/desktop-runtime.txt")) as f:
            sdk = [l.split("=", 1)[1].strip() for l in f if l.startswith("sdk=")][0]
        self.assertIn(sdk, out)
        self.assertIn("platform=unix", out)
        self.assertNotIn("mingw", out)

    def test_linux_native(self):
        out = self.check_target("linux-x86_64", "so", ("--native",))
        self.assertNotIn("flatpak run", out)

    def test_target_flag_matches_positional(self):
        a = run("cores/fceumm/build.sh", "--dry-run", "--target", "win64")
        b = run("cores/fceumm/build.sh", "--dry-run", "win64")
        self.assertEqual(a.returncode, 0, a.stderr)
        self.assertEqual(a.stdout, b.stdout)

    def test_pcsx_rearmed_is_arm_only(self):
        p = run("cores/pcsx_rearmed/build.sh", "--dry-run", "win64")
        self.assertEqual(p.returncode, 3)
        self.assertIn("Beetle PSX HW", p.stderr)

    def test_unknown_target(self):
        p = run("cores/build-desktop.sh", "--dry-run", "win32")
        self.assertEqual(p.returncode, 2)


if __name__ == "__main__":
    unittest.main()
