"""Create a conventional 8 KiB cartridge image without changing code offsets."""
from pathlib import Path
import sys

source, destination = map(Path, sys.argv[1:])
data = source.read_bytes()
if not data.startswith(b"g GCE ") or len(data) > 8192:
    raise SystemExit("Invalid header or game larger than the 8 KiB cartridge target")
destination.write_bytes(data.ljust(8192, b"\xff"))
