# SPDX-License-Identifier: GPL-3.0-or-later
# CMake toolchain: Windows x86_64 with MinGW-w64 (posix threads), for the
# desktop cores (docs/dev/desktop-cores.md). Debian: apt install mingw-w64.
# cmake -DCMAKE_TOOLCHAIN_FILE=tools/toolchain/x86_64-w64-mingw32.cmake
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR AMD64)

set(_triple x86_64-w64-mingw32)
# Debian ships -win32 and -posix variants; C++ cores need std::thread (posix).
find_program(CMAKE_C_COMPILER NAMES ${_triple}-gcc-posix ${_triple}-gcc REQUIRED)
find_program(CMAKE_CXX_COMPILER NAMES ${_triple}-g++-posix ${_triple}-g++ REQUIRED)
find_program(CMAKE_RC_COMPILER NAMES ${_triple}-windres REQUIRED)
find_program(CMAKE_AR NAMES ${_triple}-gcc-ar-posix ${_triple}-ar REQUIRED)
find_program(CMAKE_RANLIB NAMES ${_triple}-gcc-ranlib-posix ${_triple}-ranlib REQUIRED)

set(CMAKE_FIND_ROOT_PATH /usr/${_triple})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# The DLL must not need the MinGW runtime DLLs (libgcc_s, libstdc++,
# libwinpthread): link them statically. cores/desktop.sh checks the imports.
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-static -static-libgcc -static-libstdc++")
