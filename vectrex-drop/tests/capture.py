"""Capture actual emulated vectors and profile reproducible board fixtures.

Run after `make test`. SVG output uses only the Python standard library.
Optional PNG rendering requires Pillow and adds a small illustrative glow.
"""
import csv
from pathlib import Path
from test_rom import EMU, BIOS, SYM, read, word, write, setboard


def boot():
    assert EMU.emu_load(BIOS, b"build/vector-drop.bin") == 0
    EMU.emu_run(30_000_000)
    EMU.emu_input(8, 128, 128)
    EMU.emu_run(150_000)
    EMU.emu_input(0, 128, 128)
    EMU.emu_run(150_000)
    assert read("state") == 1


def representative_board():
    return [int(y >= 14 and x not in (3, 4)
                and (y >= 17 or x < 2 or x > 7))
            for y in range(20) for x in range(10)]


def profile(name, cells):
    boot()
    # Wait for a game-loop boundary before installing the render fixture.
    assert EMU.emu_until(SYM["MainLoop"], 200_000) == 0
    setboard(cells)
    start = word("frame_count")
    EMU.emu_run(4_500_000)
    fps = (word("frame_count") - start) / 3
    print(f"{name}: {fps:.1f} game frames/s ({sum(cells)} occupied cells)")
    return fps


def capture():
    boot()
    assert EMU.emu_until(SYM["MainLoop"], 200_000) == 0
    setboard(representative_board())
    write("piece", 2)
    write("rotation", 0)
    write("piece_x", 3)
    write("piece_y", 4)
    write("fall_timer", 0)
    write("next_piece", 0)
    EMU.emu_run(100_000)  # replace the previous raster/vector display buffers
    segments = set()
    # Accumulate three display samples; no piece moves during this interval.
    for _ in range(3):
        EMU.emu_run(50_000)
        EMU.emu_vectors(b"build/capture-sample.csv")
        segments.update(tuple(map(int, row)) for row in
                        csv.reader(Path("build/capture-sample.csv").open()))
    assert read("piece_y") == 4
    with Path("build/gameplay.csv").open("w") as f:
        csv.writer(f).writerows(sorted(segments))
    svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="660" height="820" viewBox="0 0 660 820">',
           '<title>Vector Drop — vectors captured from the running Vectrex ROM</title>',
           '<rect width="660" height="820" fill="black"/>']
    for x0, y0, x1, y1, c in sorted(segments):
        if c < 128:
            v = min(c * 2, 255)
            svg.append(f'<path d="M{x0/50},{y0/50} L{x1/50},{y1/50}" '
                       f'stroke="rgb({v},{v},{v})" fill="none"/>')
    svg.append('</svg>')
    Path("build/gameplay.svg").write_text('\n'.join(svg))
    try:
        from PIL import Image, ImageDraw, ImageFilter, ImageChops
    except ImportError:
        return
    picture = Image.new("RGB", (660, 820), "black")
    draw = ImageDraw.Draw(picture)
    for x0, y0, x1, y1, c in sorted(segments):
        if c < 128:
            draw.line((x0/50, y0/50, x1/50, y1/50), fill=(min(c*2, 255),)*3)
    picture = ImageChops.add(picture, picture.filter(ImageFilter.GaussianBlur(1)))
    picture.save("build/gameplay.png")


if __name__ == "__main__":
    profile("Empty", [0]*200)
    profile("Representative stack", representative_board())
    profile("Fragmented stress fixture", [int(y >= 4 and (x+y) % 2 == 0)
                                           for y in range(20) for x in range(10)])
    capture()
