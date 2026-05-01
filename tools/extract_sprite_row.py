"""Extract a single row from a Minifantasy sprite sheet.

Usage:
    python tools/extract_sprite_row.py <source_png> <output_png> [--row N] [--frame-width W] [--frame-height H] [--frame-size N]

Extracts one horizontal row of frames from a multi-row sprite sheet.
Default: row 0 (SE = facing right), 32x32 frames.

Frame dimensions:
    --frame-size N     Square frames (NxN). Default 32.
    --frame-width W    Frame width (overrides --frame-size for width).
    --frame-height H   Frame height (overrides --frame-size for height).

Examples:
    # Character animation — SE row (row 0, default 32x32)
    python tools/extract_sprite_row.py source/BattleCry.png assets/sprites/barbarian/battlecry.png

    # Non-square frames — 80x64 fire torrent effect
    python tools/extract_sprite_row.py source/Fire_Torrent_Effect.png assets/effects/fire_torrent/effect.png --frame-width 80 --frame-height 64

    # Back VFX layer — NE row (row 2 = back of SE-facing character)
    python tools/extract_sprite_row.py source/EffectBackLayer.png assets/effects/battlecry/battlecry_back.png --row 2
"""

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("PIL not found. Install with: pip install Pillow")
    sys.exit(1)


def extract(source: str, output: str, row: int = 0,
            frame_width: int = 32, frame_height: int = 32) -> None:
    src_path = Path(source)
    if not src_path.exists():
        print(f"Source not found: {src_path}")
        sys.exit(1)

    img = Image.open(src_path)
    w, h = img.size
    frame_count = w // frame_width
    row_count = h // frame_height

    if w % frame_width != 0:
        print(f"Warning: sheet width {w} not evenly divisible by frame width {frame_width}")
    if h % frame_height != 0:
        print(f"Warning: sheet height {h} not evenly divisible by frame height {frame_height}")

    if row >= row_count:
        print(f"Row {row} out of range (sheet has {row_count} rows)")
        sys.exit(1)

    cropped = img.crop((0, row * frame_height, w, (row + 1) * frame_height))

    out_path = Path(output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    cropped.save(out_path)

    print(f"{out_path} — {frame_count} frames ({frame_width}x{frame_height}) from row {row}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python tools/extract_sprite_row.py <source> <output> [--row N] [--frame-width W] [--frame-height H] [--frame-size N]")
        sys.exit(1)

    source = sys.argv[1]
    output = sys.argv[2]
    row = 0
    frame_width = 32
    frame_height = 32

    i = 3
    while i < len(sys.argv):
        if sys.argv[i] == "--row":
            i += 1
            row = int(sys.argv[i])
        elif sys.argv[i] == "--frame-size":
            i += 1
            frame_width = int(sys.argv[i])
            frame_height = frame_width
        elif sys.argv[i] == "--frame-width":
            i += 1
            frame_width = int(sys.argv[i])
        elif sys.argv[i] == "--frame-height":
            i += 1
            frame_height = int(sys.argv[i])
        i += 1

    extract(source, output, row, frame_width, frame_height)
