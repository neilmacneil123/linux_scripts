# Vector Drop — Vectrex cartridge ROM

An original falling-block puzzle game for the **GCE Vectrex**, written in Motorola
6809 assembly. This is a native cartridge image, not a browser game.

**Ready-to-load ROM:** `rom/vector-drop.bin` (8,192 bytes, unbanked).
Rebuilding produces `build/vector-drop.bin`.

Load the `.bin` as a cartridge in a Vectrex emulator such as vecx, Vide, or ParaJVE.
On real hardware, copy it to a compatible Vectrex flash/multicart using that
cartridge's normal loading procedure. The game uses the console's built-in BIOS;
the downloadable game package contains no system BIOS. Emulator and cartridge
loading menus differ, so use the instructions supplied with your device.

The standard Vectrex BIOS splash and cartridge title run first. At the game's
`READY? / PRESS 4` screen, press controller 1 button 4 to begin.

## Controls

| Controller 1 input | Action |
| --- | --- |
| Joystick left / right | Move; hold for delayed repeat |
| Joystick down | Soft drop, 1 point per row |
| Button 1 | Pause / resume |
| Button 2 | Rotate counterclockwise |
| Button 3 | Rotate clockwise |
| Button 4 | Hard drop, 2 points per row; start / restart on the corresponding screen |

In the tested SDL vecx mapping, arrows control the joystick and **A/S/D/F** map to
buttons **1/2/3/4**. Other emulators may use different keys.

## Rules and display

- 10 columns × 20 rows; all seven tetrominoes drawn from seven-piece bags.
- The sidebar shows **S** (score), **L** (lines), **LV** (level), and the next piece.
- Clear 1/2/3/4 lines for **100/300/500/800 × the current displayed level**.
- Every 10 lines advances the level, up to level 10. Gravity starts at one row
  every 35 game frames and reaches one row every 8 frames. Soft drop uses 3 frames.
- Rotation tries the original position, horizontal kicks of −1/+1/−2/+2 cells,
  then upward kicks of 1/2 cells. This is a simple classic ruleset, not modern SRS.
- A failed downward step locks immediately. There is no hold slot, ghost piece,
  separate lock-delay timer, or persistent high score. Score caps at 65,535 and
  the line counter at 999. Gameplay is silent after the BIOS introduction.
- A blocked spawn ends the game; button 4 starts a fresh board.

The falling piece has separate bright cell outlines. Adjacent settled cells in
each row share a dimmer rectangular outline to reduce vector drawing time.

## Build

On Linux, provide Git, a C compiler, Make, and Python 3, then run:

```sh
sh scripts/bootstrap.sh
make
```

The bootstrap script builds a pinned LWTOOLS 4.21 assembler in `tools/lwtools`.
It does not need root. Downloads use HTTPS Git from GitHub. Running it again reuses
the matching tool checkout and incremental build. Existing mismatched or edited
tool checkouts are preserved and reported rather than overwritten.

With an existing LWASM installation, skip bootstrap and use:

```sh
make LWASM=/path/to/lwasm
```

Build outputs are the padded `.bin`, unpadded `.raw`, assembly listing `.lst`, and
symbol file `.sym` in `build/`. No bank switching or extra cartridge RAM is used.
Game variables occupy `$C880` through `ram_end−1`; the stack starts at `$CBEA`.
The assembler's direct-page assumption is explicitly `$D0` for BIOS/VIA calls.

## Test

```sh
sh scripts/bootstrap.sh --with-tests
make test
```

The test dependency is a pinned checkout of the open-source **vecx** emulator.
The headless adapter compiles its 6809, VIA, and vector-generation code; no SDL
installation is required. Tests execute the assembled ROM, not a rewritten game
model. Logic checks call cartridge routines directly; integration checks boot
the BIOS and inject controller signals through the emulated hardware.

The upstream vecx checkout includes `rom.dat`, used locally by default. To select
your own compatible Vectrex BIOS file:

```sh
VECTREX_BIOS=/path/to/your/rom.dat make test
```

Validation covers 22 tests, including all rotation tables, seven-piece bags,
2,000 randomized collision cases, wall/floor kicks, 1–4 line clears, row collapse,
scoring, level progression, RAM guards during 2,500 randomized input steps,
BIOS boot, physical controller mapping, pause, held-button behavior, game over,
and restart. See `VALIDATION.md` for rendering measurements and limitations.

`tests/prepare_emulator.py` corrects an upstream duplicated `static` qualifier in
**generated copies** under `build/` and adds a cycle counter; upstream files are
unchanged. The headless adapter discards audio output.

## Project layout

- `src/vector-drop.asm`: complete game and cartridge header.
- `scripts/`: pinned tool bootstrap and cartridge padding.
- `tests/`: 6809/full-system test adapter and gameplay checks.
- `build/`: generated cartridge, listings, and validation captures.
- `rom/vector-drop.bin`: checked-in, ready-to-load cartridge.
- `tools/`: local third-party checkouts; excluded from the source archive.

The game lives in `vectrex-drop/` within the `linux_scripts` checkout; the existing
firewall script is unchanged. In this cloud workspace, `/workspace/vectrex-drop`
also links to the game directory. Use the existing checkout; no Git worktree is
needed.

## Credits and license

Game source and project-authored scripts/tests are MIT licensed; see `LICENSE`.
This project is not an official Tetris product and contains no Tetris assets.

Third-party tools retain their own licenses and are fetched separately:

- LWTOOLS by William Astle: <https://www.lwtools.ca/>, pinned mirror
  <https://github.com/stahta01/LWTools>.
- vecx by Valavan Manohararajah, with John Hawthorn and other contributors:
  <https://github.com/jhawthorn/vecx>.
- Vectrex BIOS entry-point documentation consulted in the Vide / Peer Johannsen
  Vectrex headers: <https://github.com/malbanGit/Vide>.
