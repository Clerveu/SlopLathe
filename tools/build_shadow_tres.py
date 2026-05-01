"""Generate a <class>_shadow_frames.tres by reading the corresponding main frames.tres.

Usage: python tools/build_shadow_tres.py <class_name> [skip_anim1 skip_anim2 ...]

Reads assets/sprites/<class>/<class>_frames.tres, builds a shadow counterpart at
assets/sprites/<class>/<class>_shadow_frames.tres pointing at shadow PNGs in
assets/sprites/<class>/shadow/<basename>.png. Skips any anim whose underlying
sheet has no corresponding shadow PNG on disk (or is listed in skip args).
"""
import re
import sys
from pathlib import Path


def parse_main_tres(path: Path):
    text = path.read_text(encoding="utf-8")

    ext_re = re.compile(
        r'\[ext_resource type="Texture2D" uid="([^"]+)" path="res://assets/sprites/[^"]+/([^/."]+)\.png" id="([^"]+)"\]'
    )
    ext_by_id = {}
    for uid, base, rid in ext_re.findall(text):
        ext_by_id[rid] = (uid, base)

    # sub_resource atlases — id -> (ext_id, region_x, region_y, w, h)
    atlas_blocks = re.findall(
        r'\[sub_resource type="AtlasTexture" id="([^"]+)"\]\s*\natlas = ExtResource\("([^"]+)"\)\s*\nregion = Rect2\(([^)]+)\)',
        text,
    )
    atlas_by_id = {}
    for aid, ext_id, region in atlas_blocks:
        x, y, w, h = [int(float(v.strip())) for v in region.split(",")]
        atlas_by_id[aid] = (ext_id, x, y, w, h)

    # animations — parse with a simple walker since they're Godot arrays
    anim_start = text.find("animations = [")
    if anim_start < 0:
        raise RuntimeError(f"animations block not found in {path}")
    anim_block = text[anim_start:]

    # Split into per-animation {...} entries — each animation is one dict
    anims = []
    # Simple regex: each animation dict has "frames": [...], "loop": X, "name": &"X", "speed": X
    anim_re = re.compile(
        r'"frames":\s*\[(.*?)\],\s*"loop":\s*(true|false),\s*"name":\s*&"([^"]+)",\s*"speed":\s*([\d.]+)',
        re.DOTALL,
    )
    for frames_block, loop_str, name, speed in anim_re.findall(anim_block):
        frame_ids = re.findall(r'SubResource\("([^"]+)"\)', frames_block)
        anims.append({
            "name": name,
            "loop": loop_str == "true",
            "speed": float(speed),
            "frame_ids": frame_ids,
        })

    return ext_by_id, atlas_by_id, anims


def find_category(class_name: str) -> str:
    for cat in ("heroes", "enemies", "creatures", "summons"):
        if Path(f"assets/sprites/{cat}/{class_name}").exists():
            return cat
    raise RuntimeError(f"Could not find sprites/<category>/{class_name} in any of heroes/enemies/creatures/summons")


def build(class_name: str, skip: set):
    category = find_category(class_name)
    main_tres = Path(f"assets/sprites/{category}/{class_name}/{class_name}_frames.tres")
    shadow_dir = Path(f"assets/sprites/{category}/{class_name}/shadow")
    out_tres = Path(f"assets/sprites/{category}/{class_name}/{class_name}_shadow_frames.tres")

    if not main_tres.exists():
        print(f"Main tres not found: {main_tres}")
        sys.exit(1)

    ext_by_id, atlas_by_id, anims = parse_main_tres(main_tres)

    # Discover which ext_ids have shadow PNGs available and build shadow_uid map
    shadow_uid_by_basename = {}
    for png_import in shadow_dir.glob("*.png.import"):
        base = png_import.stem.replace(".png", "")
        import_text = png_import.read_text(encoding="utf-8")
        m = re.search(r'uid="([^"]+)"', import_text)
        if m:
            shadow_uid_by_basename[base] = m.group(1)

    # Filter: only animations where ALL frame sheets have a shadow PNG and not in skip
    usable_anims = []
    used_ext_ids = set()
    for anim in anims:
        if anim["name"] in skip:
            continue
        sheets_needed = set()
        for frame_id in anim["frame_ids"]:
            ext_id, _, _, _, _ = atlas_by_id[frame_id]
            sheets_needed.add(ext_id)
        # Check each sheet has a shadow counterpart
        ok = True
        for ext_id in sheets_needed:
            _, base = ext_by_id[ext_id]
            if base not in shadow_uid_by_basename:
                ok = False
                break
        if ok:
            usable_anims.append(anim)
            used_ext_ids.update(sheets_needed)

    # Assign fresh sheet IDs for the shadow tres (dense 0..N)
    shadow_sheet_id = {}  # ext_id (from main) -> new sheet id string
    for i, ext_id in enumerate(sorted(used_ext_ids, key=lambda k: int(re.search(r'\d+', k).group()) if re.search(r'\d+', k) else 0)):
        shadow_sheet_id[ext_id] = f"sheet_{i}"

    # Output
    lines = []
    lines.append(f'[gd_resource type="SpriteFrames" format=3 uid="uid://{_fake_uid(class_name)}"]')
    lines.append("")

    for ext_id in sorted(used_ext_ids, key=lambda k: shadow_sheet_id[k]):
        _, base = ext_by_id[ext_id]
        uid = shadow_uid_by_basename[base]
        sid = shadow_sheet_id[ext_id]
        lines.append(f'[ext_resource type="Texture2D" uid="{uid}" path="res://assets/sprites/{category}/{class_name}/shadow/{base}.png" id="{sid}"]')

    lines.append("")

    # Emit sub_resources — keep only those used by usable anims
    used_atlas_ids = set()
    for anim in usable_anims:
        used_atlas_ids.update(anim["frame_ids"])

    for aid in sorted(used_atlas_ids, key=lambda k: (atlas_by_id[k][0], atlas_by_id[k][1])):
        ext_id, x, y, w, h = atlas_by_id[aid]
        lines.append(f'[sub_resource type="AtlasTexture" id="{aid}"]')
        lines.append(f'atlas = ExtResource("{shadow_sheet_id[ext_id]}")')
        lines.append(f'region = Rect2({x}, {y}, {w}, {h})')
        lines.append("")

    lines.append("[resource]")
    lines.append("animations = [")
    for i, anim in enumerate(usable_anims):
        lines.append("{")
        lines.append('"frames": [')
        for j, fid in enumerate(anim["frame_ids"]):
            lines.append("{")
            lines.append('"duration": 1.0,')
            lines.append(f'"texture": SubResource("{fid}")')
            lines.append("}" + ("," if j < len(anim["frame_ids"]) - 1 else ""))
        lines.append("],")
        lines.append(f'"loop": {"true" if anim["loop"] else "false"},')
        lines.append(f'"name": &"{anim["name"]}",')
        lines.append(f'"speed": {anim["speed"]}')
        lines.append("}" + ("," if i < len(usable_anims) - 1 else ""))
    lines.append("]")
    lines.append("")

    out_tres.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {out_tres}")
    print(f"  Animations: {len(usable_anims)}/{len(anims)} (skipped {len(anims) - len(usable_anims)})")
    skipped_names = [a["name"] for a in anims if a not in usable_anims]
    if skipped_names:
        print(f"  Skipped: {', '.join(skipped_names)}")


def _fake_uid(class_name: str) -> str:
    import hashlib
    h = hashlib.md5(f"shadow_{class_name}".encode()).hexdigest()[:13]
    return "b" + h[:12]


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python tools/build_shadow_tres.py <class_name> [skip_anim ...]")
        sys.exit(1)
    class_name = sys.argv[1]
    skip = set(sys.argv[2:])
    build(class_name, skip)
