---
name: tile
description: Stitch tileset and prop PNGs from asset packs into a single master tileset PNG. Use for LDtk, Tiled, or any atlas-based level editor.
disable-model-invocation: true
argument-hint: <pack1> <pack2> ...
---

# Tile

Build a master tileset from **$ARGUMENTS**.

## Paths (update on first use)

If any path below says `UPDATE_ME`, ask the user for the correct path, then immediately Edit this skill file to fill it in before proceeding.

- **Source asset directory:** `UPDATE_ME` (where raw tileset packs live — e.g., `M:\my_tilesets`)
- **Output directory:** `UPDATE_ME` (where master tilesets go — e.g., `assets/tilesets/`)

**Never overwrite an existing file.** Before running ffmpeg, `ls` the output directory. If the filename exists, pick a different name. Existing tilesets may be actively referenced.

## Step 1: Locate packs

Match each requested pack name to a directory under the source asset path. Use glob to find them.

Check for addon/exclusive content folders alongside the main packs — these extend the base pack with additional tilesets/props.

## Step 2: Collect PNGs

From each pack, collect:
- **Tileset PNGs** — files in `Tileset/` dirs or with "tileset"/"tiles" in the name
- **Prop PNGs** — files in `Props/` dirs or with "prop" in the name

Exclude: shadow layers, animation sheets, character sprites, mockup images.

## Step 3: Get dimensions

```
ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 <file>
```

Record width and height for each collected PNG.

## Step 4: Plan the layout

Goal: **as square as possible**, tilesets on top, props on bottom.

For each group:
1. Sort tallest-first
2. Target row width = `sqrt(total_area)` rounded up to nearest multiple of 8
3. Place left-to-right, new row when next image exceeds target width
4. Track `(x, y, width, height)` per image
5. Pad row height to tallest in row

Final canvas: `max_row_width × total_height`, both rounded to multiples of 8.

## Step 5: Stitch with ffmpeg

Single ffmpeg command with overlay filters:

```
ffmpeg \
  -f lavfi -i "color=c=0x00000000:s=<W>x<H>:d=1,format=rgba" \
  -i <img1> -i <img2> ... \
  -filter_complex "[0][1]overlay=<x1>:<y1>[t1]; [t1][2]overlay=<x2>:<y2>[t2]; ..." \
  -frames:v 1 -update 1 "<output_path>"
```

When paths contain special characters, copy to `/tmp/` first.

## Step 6: Verify

Run ffprobe on output to confirm dimensions. Report final size to user.
