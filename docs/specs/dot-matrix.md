# Dot matrix LCD (Dena.emu GB)

Every game in Dena.emu GB is drawn through a dot matrix LCD filter, so it
looks like the screen of a handheld: each game pixel is one LCD cell with a
thin gap around it.

## Behaviour

- One shader, `host/shaders/_pocket-lcd/pocket-lcd.glsl` (our own,
  GPL-3.0-or-later), in three presets the app picks per system:

  | System | Preset | Look |
  | --- | --- | --- |
  | Game Boy | `pocket-lcd-dmg` | Green-grey monochrome screen (the LCD palette), light gaps, cells cast a faint shadow down and right |
  | Game Boy Color, Game Boy Advance | `pocket-lcd-color` | Full colour, light reflective gaps |
  | DS | `pocket-lcd-ds` | Full colour, both screens on a finer dark grid |

- On by default: with no saved choice, a game's shader is its system's
  preset (`lcdFilterFor`). The player can still pick another shader per
  system or per game, and Off per game. Picking Off for a whole system goes
  back to the LCD filter.
- At every resolution: the grid follows the game's native pixels
  (shaders.md, Native lines), also at 2x-4x upscale. A gap is never thinner
  than about one screen pixel, so small scales keep every gap.
- Settings > Display:
  - **LCD filter intensity**, 0-100% in steps of 5, default 80%. 0% is the
    plain picture. Stored as `lcd.intensity` in `shaders.json`.
  - **Game Boy screen**: Olive (default), Pocket grey, Backlit amber,
    Inverted. Only the Game Boy preset uses it. Stored as `lcd.palette`.
- Both are shader parameters (`intensity`, `palette`). The session sends
  them with `setShaderParameter` before start; the host keeps them and gives
  them to every shader it loads that declares them. Changes apply at the next
  game start.

## Acceptance tests

- `host/render/tests/shader_preset_tests.cpp`: each preset parses with its
  own parameter values and the 80% default.
- `host/render/tests/shader_chain_tests.cpp` (`test_pocket_lcd`): one band per
  game line for GB at 4.5x and at 4x upscale, GBC, GBA, DS at 1x and 3x; the
  GB preset turns gray green; intensity 0 leaves no grid.
- `app/test/shaders/shader_store_test.dart`: LCD default per system, Off for a
  system goes back to it, intensity and palette saved and clamped.
- `app/test/session_screen_test.dart`: the LCD shader and its parameters are
  set before the core starts.
