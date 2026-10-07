# Validation results

Validated in the cloud Linux environment on 2026-10-07.

## Cartridge and build

- Native Motorola 6809 assembly, built with pinned LWASM 4.21.
- 8,192-byte unbanked cartridge image, padded with `FF` after the game data.
- SHA-256: `80977e8bf5c5e26fae60bd6de0ece7def87ffa60a89703945b2f49d90ddc40f4`.
- A fresh bootstrap in a separate temporary directory produced a byte-identical
  cartridge (`cmp` passed), verifying the pinned tool installation and build.
- The existing firewall script was left unchanged; the game is in its own subdirectory.
- No system BIOS or third-party tools are included in the downloadable archive.

## Executed checks

`make test`: **22 tests passed**, no skips.

The tests use the real assembled instructions on vecx's 6809 CPU. Full-system
tests boot the cartridge through the Vectrex BIOS and exercise the VIA/controller
and analog-vector emulation. They cover start, joystick movement, both rotation
buttons, soft/hard drop, pause/resume, held-button edges, game over, and restart.

Logic checks cover seven-piece bags, all shapes, 2,000 randomized collision
cases, kicks and rejected rotations, gravity timing, scoring and saturation,
1–4 line clears, nonadjacent/top-row clears, row compaction, decimal display,
level caps, and memory guards during 2,500 randomized input steps.

The test adapter normalizes an upstream duplicate `static` qualifier in generated
copies, adds a cycle counter, and exposes CPU state for logic tests. It does not
replace gameplay routines or BIOS/vector behavior. Audio output is stubbed.

## Rendering

Measured at the emulator's 1.5 MHz Vectrex clock over three-second intervals with
`python3 tests/capture.py`:

| Fixture | Occupied cells | Game frames per second |
| --- | ---: | ---: |
| Empty board | 0 | 45.3 |
| Representative stack | 36 | 33.3 |
| Fragmented checkerboard stress fixture | 80 | 14.0 |

`build/gameplay.svg` and `build/gameplay.png` capture actual emulated vectors from
a reproducible seeded-board fixture. They are not a concept rendering or a
screen from a real console. The PNG adds a small illustrative glow. The capture
combines three display samples while the falling piece remains stationary.

Performance depends on the number of separate occupied runs, not just the number
of blocks. Crowded, fragmented boards may flicker and slow frame-based gravity.
The game intentionally combines adjacent settled cells into row outlines and
uses shorter vector timers for small boxes to reduce drawing cost.

## Not verified

- A physical Vectrex, its analog calibration/brightness, or any particular
  flash/multicart model.
- Interactive play in Vide or ParaJVE; these are loading options, not tested
  emulator claims.
- Real CRT flicker, long-session player comfort, or captured audio playback.
- Cloud environment publication or restoration in a new task.

This is a playable prototype with emulator validation, not a claim of complete
hardware qualification or modern competitive Tetris rules compatibility.
