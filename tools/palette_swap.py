"""Hue-range palette swap for pixel art sprite sheets.

Usage:
    # Show all unique colors grouped by hue
    python tools/palette_swap.py analyze <image>

    # Map colors in a hue range to an explicit target palette (by luminance order)
    python tools/palette_swap.py swap <image> --hue-range 170 270 --palette ab6127 ef8e00 ff7400 ffb300 ffd600 -o output.png

Workflow: analyze first to see hue ranges, then swap with a hand-picked palette.

Hue values are 0-360 (red=0, green=120, blue=240). Ranges can wrap around 0
(e.g., --hue-range 340 20 captures red spanning both sides of 0).

Colors with saturation below --min-sat (default 0.08) are treated as neutral
(grays/whites/blacks) and are never swapped.
"""

import sys
import colorsys
from pathlib import Path
from collections import defaultdict

try:
    from PIL import Image
except ImportError:
    print("PIL not found. Install with: pip install Pillow")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def rgb_to_hsv360(r: int, g: int, b: int) -> tuple[float, float, float]:
    """Convert 0-255 RGB to (H 0-360, S 0-1, V 0-1)."""
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    return h * 360, s, v


def luminance(r: int, g: int, b: int) -> float:
    """Perceptual luminance (rec. 709)."""
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def in_hue_range(h: float, lo: float, hi: float) -> bool:
    """Check if hue h is within [lo, hi], supporting wrap-around."""
    if lo <= hi:
        return lo <= h <= hi
    else:  # wraps around 0 (e.g., 340..20)
        return h >= lo or h <= hi


def parse_hex(h: str) -> tuple[int, int, int]:
    """Parse hex color string (with or without #) to (r, g, b)."""
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def get_unique_colors(img: Image.Image):
    """Return dict of {(r,g,b): pixel_count} for all opaque pixels."""
    img = img.convert("RGBA")
    colors = defaultdict(int)
    for r, g, b, a in img.getdata():
        if a < 10:
            continue
        colors[(r, g, b)] += 1
    return colors


def filter_by_hue(colors: dict, hue_lo: float, hue_hi: float,
                  min_sat: float) -> list[tuple[int, int, int]]:
    """Filter color dict to those in hue range with sufficient saturation."""
    result = []
    for (r, g, b) in colors:
        h, s, v = rgb_to_hsv360(r, g, b)
        if s >= min_sat and in_hue_range(h, hue_lo, hue_hi):
            result.append((r, g, b))
    return result


# ---------------------------------------------------------------------------
# analyze
# ---------------------------------------------------------------------------

def cmd_analyze(image_path: str, min_sat: float) -> None:
    """Print all unique colors grouped by hue bucket."""
    img = Image.open(image_path).convert("RGBA")
    colors = get_unique_colors(img)

    buckets = defaultdict(list)
    neutrals = []
    for (r, g, b), count in sorted(colors.items(), key=lambda x: -x[1]):
        h, s, v = rgb_to_hsv360(r, g, b)
        if s < min_sat:
            neutrals.append(((r, g, b), count, h, s, v))
        else:
            bucket = int(h // 30) * 30
            buckets[bucket].append(((r, g, b), count, h, s, v))

    hue_names = {
        0: "Red", 30: "Orange", 60: "Yellow", 90: "Chartreuse",
        120: "Green", 150: "Spring", 180: "Cyan", 210: "Azure",
        240: "Blue", 270: "Violet", 300: "Magenta", 330: "Rose",
    }

    print(f"\n  {image_path}")
    print(f"  {img.size[0]}x{img.size[1]}, {sum(colors.values())} opaque pixels, "
          f"{len(colors)} unique colors\n")

    for bucket in sorted(buckets.keys()):
        entries = buckets[bucket]
        name = hue_names.get(bucket, f"{bucket}°")
        print(f"  {name} ({bucket}°-{bucket+30}°): {len(entries)} colors")
        for (r, g, b), count, h, s, v in sorted(entries, key=lambda x: -luminance(*x[0])):
            print(f"    #{r:02x}{g:02x}{b:02x}  H:{h:5.1f} S:{s:.2f} V:{v:.2f}  ({count}px)")

    if neutrals:
        print(f"\n  Neutral (S < {min_sat}): {len(neutrals)} colors")
        for (r, g, b), count, h, s, v in sorted(neutrals, key=lambda x: -luminance(*x[0])):
            print(f"    #{r:02x}{g:02x}{b:02x}  H:{h:5.1f} S:{s:.2f} V:{v:.2f}  ({count}px)")

    print()


# ---------------------------------------------------------------------------
# swap
# ---------------------------------------------------------------------------

def cmd_swap(image_path: str, hue_lo: float, hue_hi: float,
             palette_hex: list[str], min_sat: float, output: str) -> None:
    """Map source hue range to an explicit list of target colors, luminance-matched."""
    src_img = Image.open(image_path).convert("RGBA")
    src_colors = get_unique_colors(src_img)

    src_in_range = filter_by_hue(src_colors, hue_lo, hue_hi, min_sat)
    src_sorted = sorted(src_in_range, key=lambda c: luminance(*c))
    dst_sorted = sorted([parse_hex(h) for h in palette_hex], key=lambda c: luminance(*c))

    if not src_sorted:
        print(f"  No colors found in source hue range {hue_lo}-{hue_hi}°")
        return
    if not dst_sorted:
        print("  No target palette colors provided")
        return

    print(f"  Source ({len(src_sorted)} colors, by luminance):")
    for r, g, b in src_sorted:
        h, s, v = rgb_to_hsv360(r, g, b)
        print(f"    #{r:02x}{g:02x}{b:02x}  H:{h:5.1f} S:{s:.2f} V:{v:.2f}  lum:{luminance(r,g,b):.0f}")

    print(f"  Target ({len(dst_sorted)} colors, by luminance):")
    for r, g, b in dst_sorted:
        h, s, v = rgb_to_hsv360(r, g, b)
        print(f"    #{r:02x}{g:02x}{b:02x}  H:{h:5.1f} S:{s:.2f} V:{v:.2f}  lum:{luminance(r,g,b):.0f}")

    # If counts match, map 1:1 by luminance rank.
    # If they don't, map each source to nearest-luminance target.
    if len(src_sorted) == len(dst_sorted):
        remap = dict(zip(src_sorted, dst_sorted))
    else:
        remap = {}
        for src_c in src_sorted:
            src_lum = luminance(*src_c)
            best = min(dst_sorted, key=lambda rc: abs(luminance(*rc) - src_lum))
            remap[src_c] = best

    print(f"\n  Mapping:")
    for src_c, dst_c in sorted(remap.items(), key=lambda x: luminance(*x[0])):
        print(f"    #{src_c[0]:02x}{src_c[1]:02x}{src_c[2]:02x} -> #{dst_c[0]:02x}{dst_c[1]:02x}{dst_c[2]:02x}")

    pixels = list(src_img.getdata())
    new_pixels = []
    for r, g, b, a in pixels:
        if (r, g, b) in remap:
            nr, ng, nb = remap[(r, g, b)]
            new_pixels.append((nr, ng, nb, a))
        else:
            new_pixels.append((r, g, b, a))

    out = Image.new("RGBA", src_img.size)
    out.putdata(new_pixels)
    Path(output).parent.mkdir(parents=True, exist_ok=True)
    out.save(output)
    print(f"\n  Remapped {len(remap)} colors")
    print(f"  {output}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        sys.exit(0)

    cmd = args[0]
    opts = {
        "min_sat": 0.08,
        "output": None,
        "hue_range": None,
        "palette": [],
    }
    positional = []

    i = 1
    while i < len(args):
        a = args[i]
        if a == "--hue-range" and i + 2 < len(args):
            opts["hue_range"] = (float(args[i + 1]), float(args[i + 2]))
            i += 3
        elif a == "--min-sat" and i + 1 < len(args):
            opts["min_sat"] = float(args[i + 1])
            i += 2
        elif a == "--palette":
            i += 1
            while i < len(args) and not args[i].startswith("-"):
                opts["palette"].append(args[i])
                i += 1
        elif a in ("-o", "--output") and i + 1 < len(args):
            opts["output"] = args[i + 1]
            i += 2
        else:
            positional.append(a)
            i += 1

    return cmd, positional, opts


if __name__ == "__main__":
    cmd, positional, opts = parse_args()

    if cmd == "analyze":
        if not positional:
            print("Usage: palette_swap.py analyze <image>")
            sys.exit(1)
        cmd_analyze(positional[0], opts["min_sat"])

    elif cmd == "swap":
        if not positional or not opts["hue_range"] or not opts["palette"] or not opts["output"]:
            print("Usage: palette_swap.py swap <image> --hue-range LO HI --palette HEX1 HEX2 ... -o output.png")
            sys.exit(1)
        cmd_swap(positional[0], *opts["hue_range"],
                 opts["palette"], opts["min_sat"], opts["output"])

    else:
        print(f"Unknown command: {cmd}")
        print("Commands: analyze, swap")
        sys.exit(1)
