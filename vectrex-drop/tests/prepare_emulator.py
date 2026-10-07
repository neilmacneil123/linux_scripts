"""Normalize an upstream duplicate-static typo in generated copies only."""
from pathlib import Path

for name in ("e6809", "vecx"):
    source = Path(f"tools/vecx/{name}.c").read_text()
    source = source.replace("static einline", "einline")
    if name == "vecx":
        source = source.replace(
            "icycles = e6809_sstep (via_ifr & 0x80, 0);",
            "icycles = e6809_sstep (via_ifr & 0x80, 0); emulated_cycles += icycles;",
        )
    Path(f"build/{name}.inc").write_text(source)
