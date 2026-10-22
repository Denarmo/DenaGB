# Spec: Gamepads

Status: draft (Milestone 2, package 7)

## Purpose

Play with up to four controllers at once, pause safely when one disconnects,
and open the pause menu from any controller. Builds on the Milestone 1 input
path: Android key and motion events are read in the Activity before Flutter
and sent to native as RetroPad masks (latency-spike.md, Input).

## Player slots

- Ports 1–4 map to libretro ports 0–3. Each Android input device (by
  `InputDevice.getId()`; the built-in keyboard and any keyboard count as one
  device each) gets its own pad state.
- **Assignment:** the first device that presses a mapped button takes the
  lowest free port. A device keeps its port until it disconnects or the
  session ends. A fifth device is ignored.
- Ports are shown in the pause sheet's controller row ("P1 Xbox Wireless
  Controller", "P2 —"). Moving a device to another port from that row comes
  with the full pause menu (pause-menu.md).

## Disconnect

- When a device holding a port disconnects during a session, its buttons are
  released, the port is freed, and the game pauses with the pause sheet open
  and a snackbar "Controller 2 disconnected". Touch controls (skins) reappear
  once skins land (skins.md).
- A device that reconnects is treated as new (first press takes a port).

## Menu chord

- Start + Select held together on any assigned device opens the pause sheet
  (Back still works). The chord's buttons are released in the core first, so
  the game does not see a lingering press.

## Not in this package

Per-game and per-controller remapping, button glyphs and rumble follow in a
second gamepads package with the settings screens; the positional mapping
(PadMapper) stays the default.

## Native and platform API

- `nativeSetButtons(port, mask, eventTime)` is unchanged; Kotlin now calls it
  for ports 0–3.
- Pigeon `GameEventsApi` (FlutterApi, Kotlin → Dart):
  `onMenuRequested()`, `onControllerDisconnected(port, name)`,
  `onPlayersChanged(names)` (four entries, empty for a free port).

## Acceptance tests

- JVM (Kotlin): `PlayerSlots` assigns ports in order of first press, ignores a
  fifth device, frees a port on disconnect and reports it, and reuses the
  lowest free port; the chord is detected from any assigned device and clears
  its buttons.
- Dart: a disconnect event opens the pause sheet and shows the snackbar; the
  menu event opens it; the controller row lists the players (goldens at the
  matrix sizes).
