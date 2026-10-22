# The desktop host library for Windows and Linux PCs (x86_64):
# dena_host.dll (MinGW-w64) / libdena_host.so, loaded by the Flutter runners
# in app/windows and app/linux. Spec: docs/specs/desktop-shell.md
#
#   Linux:   cmake -S host/desktop -B build/desktop-linux -G Ninja -DCMAKE_BUILD_TYPE=Release
#   Windows: cmake -S host/desktop -B build/desktop-win64 -G Ninja -DCMAKE_BUILD_TYPE=Release \
#              -DCMAKE_TOOLCHAIN_FILE=host/desktop/cmake/mingw-w64-x86_64.cmake
cmake_minimum_required(VERSION 3.20)
project(dena_desktop C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
  add_compile_options(-Wall -Wextra $<$<COMPILE_LANGUAGE:C>:-Werror=implicit-function-declaration>)
endif()

set(_host ${CMAKE_CURRENT_SOURCE_DIR}/..)
set(_linux ${CMAKE_CURRENT_SOURCE_DIR}/../../shells/linux)

# SDL3 (zlib licence), static inside the library. A system or vcpkg SDL3 is
# used when found; otherwise the pinned release is built. Only gamepads,
# sensors, haptics and audio: Flutter owns the window.
set(DENA_SDL3_URL
  "https://github.com/libsdl-org/SDL/releases/download/release-3.2.24/SDL3-3.2.24.tar.gz"
  CACHE STRING "SDL3 source archive (a file:// URL works offline)")
set(DENA_SDL3_SHA256 81cc0fc17e5bf2c1754eeca9af9c47a76789ac5efdd165b3b91cbbe4b90bfb76)
option(DENA_SYSTEM_SDL3 "Use an installed SDL3 instead of the pinned release" OFF)
if(DENA_SYSTEM_SDL3)
  find_package(SDL3 REQUIRED CONFIG)
  set(DENA_SDL3_TARGET SDL3::SDL3)
else()
  include(FetchContent)
  set(SDL_SHARED OFF CACHE BOOL "" FORCE)
  set(SDL_STATIC ON CACHE BOOL "" FORCE)
  set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
  set(SDL_VIDEO OFF CACHE BOOL "" FORCE)
  set(SDL_RENDER OFF CACHE BOOL "" FORCE)
  set(SDL_GPU OFF CACHE BOOL "" FORCE)
  set(SDL_CAMERA OFF CACHE BOOL "" FORCE)
  set(SDL_DIALOG OFF CACHE BOOL "" FORCE)
  set(SDL_TRAY OFF CACHE BOOL "" FORCE)
  set(SDL_INSTALL OFF CACHE BOOL "" FORCE)
  set(SDL_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(SDL_UNIX_CONSOLE_BUILD ON CACHE BOOL "" FORCE)  # no X11/Wayland needed
  FetchContent_Declare(SDL3 URL ${DENA_SDL3_URL} URL_HASH SHA256=${DENA_SDL3_SHA256}
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  FetchContent_MakeAvailable(SDL3)
  set(DENA_SDL3_TARGET SDL3::SDL3-static)
endif()

# rcheevos (MIT), as in the other shells (achievements.md).
file(GLOB_RECURSE _rcheevos_sources CONFIGURE_DEPENDS ${_host}/third_party/rcheevos/src/*.c)
add_library(dena_rcheevos STATIC ${_rcheevos_sources})
target_include_directories(dena_rcheevos
  PUBLIC ${_host}/third_party/rcheevos/include
  PRIVATE ${_host}/third_party/rcheevos/src ${_host}/third_party/libretro)
target_compile_definitions(dena_rcheevos PUBLIC RC_CLIENT_SUPPORTS_HASH RC_HASH_NO_ENCRYPTED)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
  target_compile_options(dena_rcheevos PRIVATE -w)  # third-party code, unmodified
endif()

# The parts that need no SDL, GL or window, for the host tests.
add_library(dena_desktop_map STATIC src/desktop_map.cpp ${_linux}/src/std_codec.c)
target_include_directories(dena_desktop_map PUBLIC src include ${_linux}/include)

add_library(dena_host_lib SHARED
  src/desktop.cpp src/desktop_platform.cpp src/gl_desktop.cpp src/sdl_input.cpp
  src/d3d_frames.cpp
  ${_host}/runner/runner.cpp
  ${_host}/src/host.c ${_host}/src/frame.c ${_host}/src/replay.c ${_host}/src/audio.c
  ${_host}/src/session.c ${_host}/src/rewind.c ${_host}/src/link.c
  ${_host}/achievements/achievements.cpp
  ${_linux}/src/launcher/game_bridge.cpp ${_linux}/src/launcher/frame_mailbox.cpp)
target_include_directories(dena_host_lib PRIVATE
  include src ${_host}/include ${_host}/runner ${_host}/third_party/libretro
  ${_host}/achievements ${_host}/third_party/rcheevos/src ${_linux}/src/launcher)
target_link_libraries(dena_host_lib PRIVATE dena_desktop_map dena_rcheevos ${DENA_SDL3_TARGET})
set_target_properties(dena_host_lib PROPERTIES OUTPUT_NAME dena_host)
if(WIN32)
  # dena_host.dll: no "lib" prefix; the GNU runtime is linked in so the DLL
  # needs nothing beside it. Every non-static symbol is exported (MinGW's
  # default, forced because achievements.h marks dena_ra_* dllexport), which
  # dart:ffi needs for dena_ra_*, dena_link_*, dena_ram_* and dena_touch_*.
  set_target_properties(dena_host_lib PROPERTIES PREFIX "")
  target_link_options(dena_host_lib PRIVATE -static -Wl,--export-all-symbols -Wl,--exclude-libs,ALL)
  target_link_libraries(dena_host_lib PRIVATE opengl32 gdi32 user32 d3d11 dxgi winmm ws2_32)
else()
  find_library(DENA_EGL_LIB EGL REQUIRED)
  find_package(Threads REQUIRED)
  # SDL and rcheevos stay private; dena_* is what Dart looks up.
  target_link_options(dena_host_lib PRIVATE -Wl,--exclude-libs,ALL)
  target_link_libraries(dena_host_lib PRIVATE ${DENA_EGL_LIB} Threads::Threads ${CMAKE_DL_LIBS})
endif()

# Our deterministic core, for the tests (as in host/CMakeLists.txt).
add_library(dena_desktop_testcore MODULE ${_host}/testcore/testcore.c)
target_include_directories(dena_desktop_testcore PRIVATE ${_host}/third_party/libretro)
set_target_properties(dena_desktop_testcore PROPERTIES PREFIX "" OUTPUT_NAME testcore_libretro)

include(CTest)
if(BUILD_TESTING)
  add_executable(desktop_map_tests tests/desktop_map_tests.cpp)
  target_link_libraries(desktop_map_tests PRIVATE dena_desktop_map)
  add_test(NAME desktop_map COMMAND desktop_map_tests)

  # The whole library through its C interface, headless: a testcore game
  # started by a Pigeon message shows frames on the texture.
  add_executable(desktop_host_tests tests/desktop_host_tests.cpp)
  target_include_directories(desktop_host_tests PRIVATE include ${_linux}/include)
  target_link_libraries(desktop_host_tests PRIVATE dena_desktop_map)
  if(NOT WIN32)
    target_link_libraries(desktop_host_tests PRIVATE ${CMAKE_DL_LIBS})
  endif()
  if(MINGW)
    target_link_options(desktop_map_tests PRIVATE -static)
    target_link_options(desktop_host_tests PRIVATE -static)
  endif()
  file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/desktop_root)
  add_test(NAME desktop_host COMMAND desktop_host_tests $<TARGET_FILE:dena_host_lib>
    $<TARGET_FILE:dena_desktop_testcore> ${CMAKE_CURRENT_BINARY_DIR}/desktop_root)
  set_tests_properties(desktop_host PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 60)
endif()
