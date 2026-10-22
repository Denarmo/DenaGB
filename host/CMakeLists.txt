cmake_minimum_required(VERSION 3.20)
project(dena_host C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
  add_compile_options(-Wall -Wextra $<$<COMPILE_LANGUAGE:C>:-Werror=implicit-function-declaration>)
endif()

find_package(Threads REQUIRED)
add_library(dena_host STATIC src/host.c src/frame.c src/replay.c src/audio.c src/session.c src/rewind.c src/link.c)
target_include_directories(dena_host
  PUBLIC include
  PRIVATE third_party/libretro)
target_link_libraries(dena_host PUBLIC Threads::Threads)
if(NOT WIN32)
  target_link_libraries(dena_host PUBLIC ${CMAKE_DL_LIBS})
endif()


# Shader presets (docs/specs/shaders.md): the parser builds everywhere; the
# GLES 3 chain only where EGL and GLES 3 headers and libraries are found.
add_library(dena_shader_preset STATIC render/src/shader_preset.cpp)
target_include_directories(dena_shader_preset PUBLIC render/include)
find_path(DENA_GLES3_INCLUDE GLES3/gl3.h)
find_library(DENA_EGL_LIB EGL)
find_library(DENA_GLES_LIB NAMES GLESv3 GLESv2)
if(DENA_GLES3_INCLUDE AND DENA_EGL_LIB AND DENA_GLES_LIB)
  add_library(dena_shader_chain STATIC render/src/shader_chain.cpp)
  target_include_directories(dena_shader_chain PUBLIC ${DENA_GLES3_INCLUDE})
  target_link_libraries(dena_shader_chain PUBLIC dena_shader_preset ${DENA_GLES_LIB})
endif()

# The play loop shared by the shells (docs/specs/shared-runner.md).
add_library(dena_runner STATIC runner/runner.cpp)
target_include_directories(dena_runner PUBLIC runner)
target_link_libraries(dena_runner PUBLIC dena_host Threads::Threads)

# RetroAchievements (docs/specs/achievements.md): rcheevos (MIT) and our client.
file(GLOB_RECURSE DENA_RCHEEVOS_SOURCES CONFIGURE_DEPENDS third_party/rcheevos/src/*.c)
add_library(rcheevos STATIC ${DENA_RCHEEVOS_SOURCES})
target_include_directories(rcheevos
  PUBLIC third_party/rcheevos/include
  PRIVATE third_party/rcheevos/src third_party/libretro)
target_compile_definitions(rcheevos PUBLIC RC_CLIENT_SUPPORTS_HASH RC_HASH_NO_ENCRYPTED)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
  target_compile_options(rcheevos PRIVATE -w)  # third-party code, unmodified
endif()
add_library(dena_achievements STATIC achievements/achievements.cpp)
target_include_directories(dena_achievements PUBLIC achievements
  PRIVATE third_party/rcheevos/src third_party/libretro)
target_link_libraries(dena_achievements PUBLIC dena_host rcheevos Threads::Threads)

add_executable(dena-harness src/harness_main.c)
target_link_libraries(dena-harness PRIVATE dena_host)

# Our own deterministic core, so the harness is testable without ROMs.
add_library(dena_testcore MODULE testcore/testcore.c)
target_include_directories(dena_testcore PRIVATE third_party/libretro)
set_target_properties(dena_testcore PROPERTIES PREFIX "")
if(APPLE)
  # CMake defaults MODULE libraries to .so on macOS; cores ship as .dylib.
  set_target_properties(dena_testcore PROPERTIES SUFFIX ".dylib")
endif()

include(CTest)
if(BUILD_TESTING)
  add_executable(host_unit_tests tests/unit_tests.c)
  target_link_libraries(host_unit_tests PRIVATE dena_host)
  add_test(NAME unit COMMAND host_unit_tests)

  add_executable(session_tests tests/session_tests.c)
  target_link_libraries(session_tests PRIVATE dena_host)
  add_test(NAME session COMMAND session_tests $<TARGET_FILE:dena_testcore>
    ${CMAKE_CURRENT_BINARY_DIR})
  set_tests_properties(session PROPERTIES FIXTURES_SETUP thumb)

  set(DENA_SHADERS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/shaders)
  file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/shader_tmp)
  add_executable(shader_preset_tests render/tests/shader_preset_tests.cpp)
  target_link_libraries(shader_preset_tests PRIVATE dena_shader_preset)
  add_test(NAME shader_preset COMMAND shader_preset_tests
    ${CMAKE_CURRENT_BINARY_DIR}/shader_tmp ${DENA_SHADERS_DIR})
  if(TARGET dena_shader_chain)
    add_executable(shader_chain_tests render/tests/shader_chain_tests.cpp)
    target_link_libraries(shader_chain_tests PRIVATE dena_shader_chain ${DENA_EGL_LIB})
    add_test(NAME shader_chain COMMAND shader_chain_tests
      ${CMAKE_CURRENT_BINARY_DIR}/shader_tmp ${DENA_SHADERS_DIR})
    # No GPU context on this machine: reported as skipped, not passed.
    set_tests_properties(shader_chain PROPERTIES SKIP_RETURN_CODE 77)
  endif()

  add_executable(link_tests tests/link_tests.c)
  target_link_libraries(link_tests PRIVATE dena_host)
  add_test(NAME link COMMAND link_tests)
  set_tests_properties(link PROPERTIES SKIP_RETURN_CODE 77)

  add_executable(rewind_tests tests/rewind_tests.c)
  target_link_libraries(rewind_tests PRIVATE dena_host)
  add_test(NAME rewind COMMAND rewind_tests $<TARGET_FILE:dena_testcore>)

  file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/runner_tmp)
  add_executable(runner_tests runner/runner_tests.cpp)
  target_link_libraries(runner_tests PRIVATE dena_runner)
  if(MINGW)  # whichever libstdc++/winpthread DLL is first on PATH may not match
    target_link_options(runner_tests PRIVATE -static)
  endif()
  add_test(NAME runner COMMAND runner_tests $<TARGET_FILE:dena_testcore>
    ${CMAKE_CURRENT_BINARY_DIR}/runner_tmp)

  file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/ra_tmp)
  add_executable(achievements_tests achievements/achievements_tests.cpp)
  target_link_libraries(achievements_tests PRIVATE dena_achievements)
  if(MINGW)
    target_link_options(achievements_tests PRIVATE -static)
  endif()
  add_test(NAME achievements COMMAND achievements_tests $<TARGET_FILE:dena_testcore>
    ${CMAKE_CURRENT_BINARY_DIR}/ra_tmp)

  add_executable(hw_tests tests/hw_tests.c)
  target_link_libraries(hw_tests PRIVATE dena_host)
  target_include_directories(hw_tests PRIVATE third_party/libretro)
  add_test(NAME hw COMMAND hw_tests $<TARGET_FILE:dena_testcore>)

  set(HARNESS $<TARGET_FILE:dena-harness>)
  set(TESTCORE $<TARGET_FILE:dena_testcore>)
  set(REPLAYS ${CMAKE_CURRENT_SOURCE_DIR}/tests/replays)

  add_test(NAME golden_testcore
    COMMAND ${HARNESS} golden ${CMAKE_CURRENT_SOURCE_DIR}/tests/golden/testcore.txt
      --cores-dir $<TARGET_FILE_DIR:dena_testcore> --replays-dir ${REPLAYS})
  # A NEW or SKIP result must not pass silently for the testcore.
  set_tests_properties(golden_testcore PROPERTIES
    FAIL_REGULAR_EXPRESSION "NEW |SKIP |fail=[1-9]")

  add_test(NAME roundtrip_idle
    COMMAND ${HARNESS} roundtrip --core ${TESTCORE} --frames 120 --strict-state)
  add_test(NAME roundtrip_with_input
    COMMAND ${HARNESS} roundtrip --core ${TESTCORE} --frames 120 --strict-state
      --replay ${REPLAYS}/testcore-walk.dreplay)

  # Determinism and input sensitivity are checked by a CMake script that runs
  # the harness several times and compares output lines.
  add_test(NAME replay_determinism
    COMMAND ${CMAKE_COMMAND} -DHARNESS=${HARNESS} -DCORE=${TESTCORE}
      -DREPLAY=${REPLAYS}/testcore-walk.dreplay
      -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/determinism.cmake)

  add_test(NAME bad_replay_is_usage_error
    COMMAND ${HARNESS} run --core ${TESTCORE} --frames 1
      --replay ${REPLAYS}/bad.dreplay)
  set_tests_properties(bad_replay_is_usage_error PROPERTIES WILL_FAIL TRUE)

  # Real-core tests run when a core directory is given, e.g.
  #   cmake -DDENA_CORES_DIR=<dir containing mgba_libretro.*>
  set(DENA_CORES_DIR "" CACHE PATH "Directory with built libretro cores")
  set(LATENCY_ROM_DIR ${CMAKE_CURRENT_SOURCE_DIR}/tests/roms/latency)
  if(DENA_CORES_DIR)
    add_test(NAME golden_gba
      COMMAND ${HARNESS} golden ${CMAKE_CURRENT_SOURCE_DIR}/tests/golden/gba.txt
        --cores-dir ${DENA_CORES_DIR} --roms-dir ${LATENCY_ROM_DIR} --replays-dir ${REPLAYS})
    set_tests_properties(golden_gba PROPERTIES
      FAIL_REGULAR_EXPRESSION "NEW |SKIP |fail=[1-9]")
    file(GLOB _mgba ${DENA_CORES_DIR}/mgba_libretro.*)
    # Link cable (docs/specs/link-cable.md): two linked cores, one per process.
    set(LINK_ROM_DIR ${CMAKE_CURRENT_SOURCE_DIR}/tests/roms/link)
    add_executable(link_core_tests tests/link_core_tests.c)
    target_link_libraries(link_core_tests PRIVATE dena_host)
    add_test(NAME link_gb COMMAND link_core_tests ${_mgba}
      ${LINK_ROM_DIR}/link_master.gb ${LINK_ROM_DIR}/link_slave.gb 99AABB 112233)
    add_test(NAME link_gba COMMAND link_core_tests ${_mgba}
      ${LINK_ROM_DIR}/link_parent.gba ${LINK_ROM_DIR}/link_child.gba 99AABB 112233)
    set_tests_properties(link_gb link_gba PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 60)
    add_test(NAME roundtrip_gba
      COMMAND ${HARNESS} roundtrip --core ${_mgba} --rom ${LATENCY_ROM_DIR}/latency.gba
        --frames 60 --replay ${REPLAYS}/latency-press.dreplay)
    # Dena.emu GB builds only mGBA and melonDS (docs/dev/gb-fork.md).
    # DS internal resolution (ds.md): melonDS's GLES renderer at 1x-4x on our
    # test ROM, against its software renderer. Needs a GLES build of the core.
    file(GLOB _melonds ${DENA_CORES_DIR}/melonds_libretro.*)
    if(_melonds AND TARGET dena_shader_chain)
      add_executable(ds_gles_tests tests/ds_gles_tests.cpp)
      target_link_libraries(ds_gles_tests PRIVATE dena_host dena_shader_chain ${DENA_EGL_LIB})
      file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/ds_tmp)
      add_test(NAME ds_gles COMMAND ds_gles_tests ${_melonds}
        ${CMAKE_CURRENT_SOURCE_DIR}/tests/roms/nds/test.nds ${CMAKE_CURRENT_BINARY_DIR}/ds_tmp)
      set_tests_properties(ds_gles PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 120)
    endif()
  endif()

  # The committed test ROM must match its generator.
  find_package(Python3 COMPONENTS Interpreter)
  if(Python3_FOUND)
    add_test(NAME png_thumbnail_decodes
      COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/check_png.py
        ${CMAKE_CURRENT_BINARY_DIR}/thumb.png ${CMAKE_CURRENT_BINARY_DIR}/thumb.ppm)
    set_tests_properties(png_thumbnail_decodes PROPERTIES FIXTURES_REQUIRED thumb)
    add_test(NAME latency_rom_up_to_date
      COMMAND ${CMAKE_COMMAND} -DPY=${Python3_EXECUTABLE}
        -DGEN=${LATENCY_ROM_DIR}/make_rom.py -DROM=${LATENCY_ROM_DIR}/latency.gba
        -DOUT=${CMAKE_CURRENT_BINARY_DIR}/latency.gba
        -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/compare_rom.cmake)
    foreach(_sys_rom nes:test.nes snes:test.sfc nds:test.nds)
      string(REPLACE ":" ";" _parts ${_sys_rom})
      list(GET _parts 0 _sys)
      list(GET _parts 1 _rom)
      set(_romdir ${CMAKE_CURRENT_SOURCE_DIR}/tests/roms/${_sys})
      add_test(NAME ${_sys}_rom_up_to_date
        COMMAND ${CMAKE_COMMAND} -DPY=${Python3_EXECUTABLE}
          -DGEN=${_romdir}/make_rom.py -DROM=${_romdir}/${_rom}
          -DOUT=${CMAKE_CURRENT_BINARY_DIR}/${_rom}
          -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/compare_rom.cmake)
    endforeach()
  endif()

  add_test(NAME missing_core_exit_code
    COMMAND ${HARNESS} run --core ${CMAKE_CURRENT_BINARY_DIR}/no_such_core --frames 1)
  set_tests_properties(missing_core_exit_code PROPERTIES WILL_FAIL TRUE)
endif()
