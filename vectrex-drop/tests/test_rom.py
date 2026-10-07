"""Tests execute the assembled 6809 ROM, not a Python port of the game.

Full-system tests run the Vectrex BIOS, VIA timers, analog vector generator,
and controller interface. Logic tests call cartridge routines on the same CPU.
"""
import ctypes
import os
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
SYM = {name: int(value[1:], 16) for name, _, value in
       (line.split() for line in Path("build/vector-drop.sym").read_text().splitlines())}
ROM = Path("build/vector-drop.bin").read_bytes()
BIOS = os.environ.get("VECTREX_BIOS", "tools/vecx/rom.dat").encode()
EMU = ctypes.CDLL(str(ROOT / "build/vecx-test.so"))
EMU.emu_cycles.restype = ctypes.c_ulonglong


def read(name, offset=0):
    return EMU.emu_read(SYM[name] + offset)


def write(name, value, offset=0):
    EMU.emu_write(SYM[name] + offset, value & 255)


def word(name):
    return read(name) * 256 + read(name, 1)


def setword(name, value):
    write(name, value >> 8)
    write(name, value, 1)


def board():
    return [read("board", i) for i in range(200)]


def setboard(cells):
    assert len(cells) == 200
    for i, value in enumerate(cells):
        write("board", value, i)


def call(name, a=0, b=0):
    result = EMU.emu_call(SYM[name], a & 255, b & 255)
    if result:
        raise AssertionError(f"{name} failed to return; PC={EMU.emu_pc():04x}")
    if EMU.emu_sp() != 0xCBEA:
        raise AssertionError(f"{name} left the stack unbalanced")
    return EMU.emu_a()


def shape(kind, rotation):
    start = SYM["Shapes"] + kind * 32 + rotation * 8
    data = ROM[start:start + 8]
    return list(zip(data[::2], data[1::2]))


class LogicTests(unittest.TestCase):
    def setUp(self):
        self.assertEqual(EMU.emu_load(BIOS, b"build/vector-drop.bin"), 0)
        write("rng", 0xA7)
        call("NewGame")
        write("buttons", 0)
        EMU.emu_write(SYM["Joy_X"], 0)
        EMU.emu_write(SYM["Joy_Y"], 0)

    def test_cartridge_header_and_memory_budget(self):
        self.assertTrue(ROM.startswith(b"g GCE 2026\x80"))
        self.assertLessEqual(len(ROM), 32768)
        self.assertLess(SYM["ram_end"], 0xCB00)
        self.assertEqual(read("state"), 1)
        self.assertEqual(sum(board()), 0)

    def test_all_shapes_have_four_connected_cells(self):
        for kind in range(7):
            for rot in range(4):
                cells = set(shape(kind, rot))
                self.assertEqual(len(cells), 4)
                reached = {next(iter(cells))}
                for _ in range(4):
                    reached |= {c for c in cells if any(
                        abs(c[0]-v[0]) + abs(c[1]-v[1]) == 1 for v in reached)}
                self.assertEqual(reached, cells)

    def test_seven_piece_bags(self):
        write("bag_count", 0)
        for _ in range(40):
            self.assertEqual(sorted(call("PickPiece") for _ in range(7)), list(range(7)))

    def test_collision_against_independent_grid_oracle(self):
        rng = random.Random(911)
        for _ in range(2000):
            cells = [int(rng.random() < 0.12) for _ in range(200)]
            setboard(cells)
            kind, rot = rng.randrange(7), rng.randrange(4)
            x, y = rng.randrange(-4, 13), rng.randrange(-4, 23)
            for name, value in (("piece", kind), ("rotation", rot), ("piece_x", x), ("piece_y", y)):
                write(name, value)
            expected = any(not (0 <= x+dx < 10 and 0 <= y+dy < 20)
                           or cells[(y+dy)*10+x+dx] for dx, dy in shape(kind, rot))
            self.assertEqual(bool(call("Collides")), expected, (kind, rot, x, y))
            self.assertEqual(board(), cells)

    def test_clockwise_and_counterclockwise(self):
        write("piece", 2)
        for n in range(1, 5):
            call("Rotate", 1)
            self.assertEqual(read("rotation"), n % 4)
        call("Rotate", 3)
        self.assertEqual(read("rotation"), 3)

    def test_wall_and_floor_kicks(self):
        write("piece", 0)
        write("rotation", 1)
        write("piece_x", -2)
        self.assertEqual(call("Collides"), 0)
        call("Rotate", 1)
        self.assertEqual(read("rotation"), 2)
        self.assertEqual(read("piece_x"), 0)
        write("rotation", 0)
        write("piece_x", 3)
        write("piece_y", 18)
        call("Rotate", 1)
        self.assertEqual(read("rotation"), 1)
        self.assertEqual(read("piece_y"), 16)
        self.assertEqual(call("Collides"), 0)

    def test_obstructed_rotation_restores_position(self):
        write("piece", 2)
        write("piece_y", 5)
        cells = [1] * 200
        for dx, dy in shape(2, 0):
            cells[(5+dy)*10+3+dx] = 0
        setboard(cells)
        call("Rotate", 1)
        self.assertEqual((read("piece_x"), read("piece_y"), read("rotation")), (3, 5, 0))

    def test_hard_drop_locks_and_scores(self):
        write("piece", 1)  # square falls 18 rows
        write("buttons", 8)
        call("Update")
        expected = [0] * 200
        for row in (18, 19):
            for col in (4, 5):
                expected[row*10+col] = 1
        self.assertEqual(board(), expected)
        self.assertEqual(word("score"), 36)
        self.assertEqual(read("piece_y"), 0)

    def test_gravity_and_soft_drop(self):
        write("piece", 1)
        write("buttons", 0)
        EMU.emu_write(SYM["Joy_X"], 0)
        EMU.emu_write(SYM["Joy_Y"], 0)
        for _ in range(34):
            call("Update")
        self.assertEqual(read("piece_y"), 0)
        call("Update")
        self.assertEqual(read("piece_y"), 1)
        self.assertEqual(word("score"), 0)
        EMU.emu_write(SYM["Joy_Y"], 255)
        for _ in range(3):
            call("Update")
        self.assertEqual(read("piece_y"), 2)
        self.assertEqual(word("score"), 1)

    def test_one_to_four_line_clears_and_row_collapse(self):
        for count, points in enumerate((100, 300, 500, 800), 1):
            call("NewGame")
            cells = [0] * 200
            cells[2] = 1
            cells[10*8+4] = 1
            cells[200-10*count:] = [1] * (10*count)
            setboard(cells)
            call("ClearLines")
            expected = [0] * 200
            expected[count*10+2] = 1
            expected[(8+count)*10+4] = 1
            self.assertEqual(board(), expected)
            self.assertEqual(word("lines"), count)
            self.assertEqual(word("score"), points)

    def test_nonadjacent_line_clears(self):
        cells = [0] * 200
        cells[160:170] = [1] * 10
        cells[190:200] = [1] * 10
        cells[171] = 1
        setboard(cells)
        call("ClearLines")
        self.assertEqual(word("lines"), 2)
        self.assertEqual(sum(board()), 1)
        self.assertEqual(read("board", 181), 1)

    def test_top_row_clear(self):
        cells = [1] * 10 + [0] * 190
        setboard(cells)
        call("ClearLines")
        self.assertEqual(sum(board()), 0)
        self.assertEqual(word("score"), 100)

    def test_level_speed_and_score_multiplier(self):
        setword("lines", 9)
        cells = [0] * 190 + [1] * 10
        setboard(cells)
        call("ClearLines")
        self.assertEqual((word("lines"), read("level"), read("fall_period")), (10, 1, 32))
        setboard(cells)
        call("ClearLines")
        self.assertEqual(word("score"), 300)

    def test_level_and_line_caps(self):
        for old in (89, 99, 255, 265, 511, 998, 999):
            setword("lines", old)
            setboard([0]*190 + [1]*10)
            call("ClearLines")
            self.assertEqual(read("level"), 9)
            self.assertEqual(read("fall_period"), 8)
            self.assertEqual(word("lines"), min(old+1, 999))

    def test_score_saturates(self):
        setword("score", 65530)
        call("AddScore", 0, 100)
        self.assertEqual(word("score"), 65535)

    def test_decimal_display(self):
        for value in (0, 1, 9, 10, 99, 999, 10000, 65535):
            call("Decimal", value >> 8, value)
            self.assertEqual(bytes(read("number_text", n) for n in range(6)),
                             f"{value:05d}".encode() + b"\x80")

    def test_spawn_collision_game_over_and_restart(self):
        setboard([1]*20 + [0]*180)
        call("Spawn")
        self.assertEqual(read("state"), 3)
        write("buttons", 8)
        call("Update")
        self.assertEqual(read("state"), 1)
        self.assertEqual(sum(board()), 0)
        self.assertEqual(word("score"), 0)

    def test_pause_freezes_game(self):
        write("buttons", 1)
        call("Update")
        self.assertEqual(read("state"), 2)
        write("buttons", 0)
        before = (read("piece_y"), read("fall_timer"))
        for _ in range(100):
            call("Update")
        self.assertEqual((read("piece_y"), read("fall_timer")), before)
        write("buttons", 1)
        call("Update")
        self.assertEqual(read("state"), 1)

    def test_horizontal_repeat_and_boundaries(self):
        write("piece", 1)
        write("buttons", 0)
        EMU.emu_write(SYM["Joy_X"], 255)
        EMU.emu_write(SYM["Joy_Y"], 0)
        call("Update")
        self.assertEqual(read("piece_x"), 2)
        for _ in range(11):
            call("Update")
        self.assertEqual(read("piece_x"), 2)
        call("Update")
        self.assertEqual(read("piece_x"), 1)
        for _ in range(40):
            call("Update")
        self.assertEqual(read("piece_x"), 255)  # local O cells begin at +1
        self.assertEqual(call("Collides"), 0)

    def test_random_play_does_not_corrupt_ram(self):
        rng = random.Random(7809)
        for addr in range(SYM["ram_end"], 0xCB80):
            EMU.emu_write(addr, 0xA5)
        EMU.emu_write(SYM["Joy_Y"], 0)
        for _ in range(2500):
            if read("state") == 3:
                call("NewGame")
            EMU.emu_write(SYM["Joy_X"], rng.choice([0, 1, 255]))
            write("buttons", rng.choice([0, 0, 2, 4, 8]))
            call("Update")
            self.assertTrue(all(v in (0, 1) for v in board()))
            if read("state") == 1:
                self.assertEqual(call("Collides"), 0)
        self.assertTrue(all(EMU.emu_read(a) == 0xA5 for a in range(SYM["ram_end"], 0xCB80)))


class SystemTests(unittest.TestCase):
    def setUp(self):
        self.assertEqual(EMU.emu_load(BIOS, b"build/vector-drop.bin"), 0)
        EMU.emu_run(30_000_000)  # actual BIOS cold-start/title sequence
        self.assertEqual(read("state"), 0)
        self.assertGreater(word("frame_count"), 20)

    def press(self, mask):
        EMU.emu_input(mask, 128, 128)
        EMU.emu_run(150_000)
        EMU.emu_input(0, 128, 128)
        EMU.emu_run(150_000)

    def test_bios_boot_start_pause_rotate_drop_restart(self):
        self.press(8)
        self.assertEqual(read("state"), 1)
        self.press(4)
        self.assertEqual(read("rotation"), 1)
        self.press(2)
        self.assertEqual(read("rotation"), 0)
        self.press(1)
        self.assertEqual(read("state"), 2)
        y = read("piece_y")
        EMU.emu_run(1_500_000)
        self.assertEqual(read("piece_y"), y)
        self.press(1)
        self.assertEqual(read("state"), 1)
        self.press(8)
        self.assertEqual(sum(board()), 4)
        # Hold button 4: it must remain edge-triggered, not drop every frame.
        EMU.emu_input(8, 128, 128)
        EMU.emu_run(800_000)
        self.assertEqual(sum(board()), 8)
        EMU.emu_input(0, 128, 128)
        EMU.emu_run(100_000)
        for _ in range(20):
            if read("state") == 3:
                break
            self.press(8)
        self.assertEqual(read("state"), 3)
        self.press(8)
        self.assertEqual(read("state"), 1)
        self.assertEqual(sum(board()), 0)

    def test_joystick_hardware_path_and_vector_output(self):
        self.press(8)
        before = read("piece_x")
        EMU.emu_input(0, 255, 128)
        EMU.emu_run(150_000)
        self.assertGreater(read("piece_x"), before)
        EMU.emu_input(0, 128, 0)
        EMU.emu_run(600_000)
        self.assertGreater(read("piece_y"), 2)
        EMU.emu_input(0, 128, 128)
        self.press(8)
        self.assertGreater(EMU.emu_vectors(b"build/gameplay.csv"), 100)
        self.assertTrue(0xCBA0 < EMU.emu_sp() <= 0xCBEA)


if __name__ == "__main__":
    unittest.main(verbosity=2)
