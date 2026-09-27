#!/usr/bin/env python3
"""Convert the 72x14 1bpp logo source into $readmemh-compatible bytes.

The textdisp logo renderer indexes each byte as mem_do_b[logo_xoff], where
logo_xoff is zero for the leftmost pixel.  Therefore source pixels are packed
least-significant-bit first: the first pixel in every group of eight is bit 0.
"""

from argparse import ArgumentParser
from pathlib import Path
import sys


WIDTH = 72
HEIGHT = 14


def convert(source: Path) -> list[int]:
    rows = [line.strip() for line in source.read_text(encoding="ascii").splitlines() if line.strip()]
    if len(rows) != HEIGHT or any(set(row) - {"0", "1"} or len(row) > WIDTH for row in rows):
        raise ValueError(
            f"{source} must contain {HEIGHT} rows of at most {WIDTH} binary pixels"
        )

    values = []
    for row in rows:
        # logo.bin currently has 71 pixels per row.  The 72nd rendered pixel
        # is background, matching the rest of the blank right-hand margin.
        row = row.ljust(WIDTH, "0")
        for byte_start in range(0, WIDTH, 8):
            byte = row[byte_start : byte_start + 8]
            values.append(sum((bit == "1") << index for index, bit in enumerate(byte)))
    return values


def main() -> int:
    parser = ArgumentParser(description="Convert a 72x14 0/1 logo to byte-per-line hex")
    parser.add_argument("source", nargs="?", type=Path, default=Path("logo.bin"))
    parser.add_argument("destination", nargs="?", type=Path, default=Path("logo.hex"))
    args = parser.parse_args()

    try:
        values = convert(args.source)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    args.destination.write_text("".join(f"{value:02x}\n" for value in values), encoding="ascii")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
