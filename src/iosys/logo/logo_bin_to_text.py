#!/usr/bin/env python3
"""Convert a logo .bin file and write a same-name .hex file beside it."""

from argparse import ArgumentParser
from pathlib import Path
import sys

from logo_bin_to_hex import convert


def main() -> int:
    parser = ArgumentParser(description="Convert a logo .bin file to a same-name .hex file")
    parser.add_argument("source", nargs="?", type=Path, default=Path("logo.bin"))
    args = parser.parse_args()

    destination = args.source.with_suffix(".hex")
    try:
        values = convert(args.source)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    destination.write_text("".join(f"{value:02x}\n" for value in values), encoding="ascii")
    print(destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
