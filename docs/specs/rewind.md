# Spec: Rewind

Status: draft (Milestone 3, package 1)

## Behaviour

- While a game runs with rewind on, the host captures a save state every
  `interval` frames (default 2) into a ring buffer with a memory budget
  (default 32 MB on phones; the handhelds will use 8 MB).
- **Rewind** plays backwards while a gamepad's **L2** is held (systems without an
  L2 button), or from the pause-menu tile until the player taps the screen
  ("Rewinding · tap to stop"). Skins can hold it through `dena_rewind_hold`.
- Each step restores the previous capture and shows its frame, stepping every
  `interval` frames so playback runs at roughly real speed. Audio is muted.
- Releasing continues from that point; captures made after it are dropped.
- When the buffer is empty the game stays paused on the oldest point.
- Loading a save state, resetting or changing disc clears the buffer.
- Rewind is off when the core can't serialize (state size 0) or when one
  state is larger than half the budget (PPSSPP, ~40 MB; 128 MB before boot):
  capturing it every few frames stalls the game. With rewind off, a held L2
  is an ordinary button.
- Later: a setting turns rewind off (it costs CPU on slow handhelds).

## Storage format (host, `dena/rewind.h`)

- The newest state is kept in full. Each older capture is stored as the XOR of
  it and the next newer state, run-length encoded: repeated
  `(zero_run varint, literal_len varint, literal bytes)`. Most bytes are equal
  between adjacent frames, so entries are small.
- Stepping back XORs the newest entry into the current state, which yields
  the previous state exactly.
- The oldest entries are evicted to stay within the budget. A change in state
  size clears the buffer.

## API

```c
dena_rewind *dena_rewind_create(size_t budget_bytes);
void dena_rewind_destroy(dena_rewind *rw);
int dena_rewind_push(dena_rewind *rw, const void *state, size_t size); /* 0 or -1 (out of memory) */
int dena_rewind_step_back(dena_rewind *rw, void *out, size_t size);    /* 0, DENA_NO_DATA when empty */
size_t dena_rewind_count(const dena_rewind *rw);   /* steps available */
size_t dena_rewind_bytes(const dena_rewind *rw);   /* memory in use */
void dena_rewind_clear(dena_rewind *rw);
```

## Acceptance tests

- Codec: random and mostly-equal buffers encode and decode exactly.
- Ring: push N states, step back N-1 times and get each state byte for byte;
  the budget evicts the oldest; a size change clears.
- With the test core: run 120 frames capturing each frame, record frame hashes,
  step back 30 times, load and run one frame: the hash matches the recorded one.
