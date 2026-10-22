# Specs

Every feature gets a spec here before code (CLAUDE.md §7). A spec covers
behaviour, inputs, edge cases and acceptance tests. Status is one of
`draft`, `accepted`, `implemented`.

| Spec | Milestone | Status |
| --- | --- | --- |
| [test-harness.md](test-harness.md) | 0 | implemented |
| [ui-test-harness.md](ui-test-harness.md) | 0 | implemented |
| [rig.md](rig.md) | 0 | implemented (handheld helpers in M4) |
| [ci.md](ci.md) | 0 | implemented |
| [latency-spike.md](latency-spike.md) | 1 | implemented on Android (gate on a phone and H700 waits for rig hardware) |
| [shaders.md](shaders.md) | 3 | implemented on Android (device check waits for rig hardware) |
| [pico8-cart-browser.md](pico8-cart-browser.md) | 3 | implemented behind a flag that stays off until Lexaloffle permits it |
| [theming.md](theming.md) | 2 | implemented |
| [single-card.md](single-card.md) | 4 | implemented for H700 (QEMU boot test; first boot on a device waits for rig hardware) |
| [link-cable.md](link-cable.md) | 3 | implemented (two-device check on real phones pending) |
| [romm.md](romm.md) | 3 | implemented |
| [desktop-shell.md](desktop-shell.md) | desktop | implemented in code (first run on DENA-PC in the combined desktop pass) |

Decisions: [docs/decisions](../decisions).
