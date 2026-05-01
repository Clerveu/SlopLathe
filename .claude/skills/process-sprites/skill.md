---
name: process-sprites
description: Extract sprite rows from source sheets and build Godot SpriteFrames .tres files. Use when importing character animations or VFX layers.
disable-model-invocation: true
argument-hint: [character or effect name] [animation-name]
---

# Process Sprites

Import sprites for **$ARGUMENTS**.

## Paths (update on first use)

If any path below says `UPDATE_ME`, ask the user for the correct path, then immediately Edit this skill file to fill it in before proceeding.

- **Source asset directory:** `UPDATE_ME` (where raw sprite sheets live — e.g., `M:\my_assets`)
- **Character output:** `assets/sprites/` (extracted PNGs and .tres files)
- **Effect output:** `assets/effects/` (extracted effect PNGs and .tres files)

## Step 0: Read the source metadata (MANDATORY)

Before extracting, determine:
- **Frame size** — check source docs, readme, or measure the sheet. Characters are often 32x32, effects 64x64. NEVER assume.
- **Frame duration** — typically 100ms (10fps) or 83ms (12fps). Sets the `speed` value in the .tres.

## Step 1: Identify the asset type

**Animation strip** (most assets): horizontal row of frames in a multi-row directional sheet. Each row is one direction.

**Directional grid** (some projectiles): NxN grid of static sprites, one per direction. NOT animation frames.

To distinguish: check dimensions against frame size. If both `width/frame_w` and `height/frame_h` are small (2-4), it's a grid. If one is large (10+), it's a strip.

## Step 2: Extract

```
python tools/extract_sprite_row.py <source> <output> [options]
```

- `--frame-size N` — square frames (default 32)
- `--frame-width W` / `--frame-height H` — non-square frames
- `--row N` — directional row (default 0 = east-facing)

Standard 4-row layout: Row 0 = East, Row 1 = West, Row 2 = South, Row 3 = North.

For directional grids, crop individual cells with PIL instead.

## Step 3: Verify extraction

Check: dimensions match `frame_width × frame_count` by `frame_height`. If the tool warns about uneven division, frame size is wrong.

## Step 4: Build or update the .tres

SpriteFrames `.tres` files are text-based. Key values:
- `region = Rect2(x, 0, frame_width, frame_height)` — atlas regions must match actual frame dimensions
- `speed` — FPS from source metadata (100ms = 10.0, 83ms = 12.0)
- `loop` — true for idle/walk/looping VFX, false for one-shot attacks/die

**Adding to an existing .tres:** Read the file, then Edit to add the new `[ext_resource]`, `[sub_resource]` AtlasTexture entries, and animation definition. Update `load_steps`. Do NOT regenerate the entire file.

**Creating a new .tres:** Write the complete file with all atlas sub-resources and animation definitions.

## Step 5: Shadows (when source ships them)

If the source pack includes shadow sprites (ground-plane silhouettes), extract them to a `shadow/` subdir under the character folder.

Use `tools/build_shadow_tres.py <entity_name>` to auto-generate the shadow .tres from the main .tres. The tool reads the main frames, checks for matching shadow PNGs, and emits a parallel tres.

**Note:** `build_shadow_tres.py` looks for entity folders in `assets/sprites/{heroes,enemies,creatures,summons}/`. If your project uses different categories, update the `find_category()` function in the script.
