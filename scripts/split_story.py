#!/usr/bin/env python3
"""Split story/zork1.z5 into 16 KiB MMC1 PRG banks under build/story_banks/."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
src = ROOT / "story" / "zork1.z5"
out = ROOT / "build" / "story_banks"
bank = 16384

if not src.is_file():
    sys.exit("missing %s" % src)

story = src.read_bytes()
out.mkdir(parents=True, exist_ok=True)
n = (len(story) + bank - 1) // bank
padded = story + bytes([255]) * (n * bank - len(story))
for i in range(n):
    (out / ("story%d.bin" % i)).write_bytes(padded[i * bank : (i + 1) * bank])
print("story banks", n)
