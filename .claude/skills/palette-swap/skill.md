---
name: palette-swap
description: Swap a hue range in pixel art sprites to a hand-picked target palette. Use when recoloring VFX, creating element variants, or unifying a color scheme.
disable-model-invocation: true
argument-hint: [source image(s)] [description of desired swap]
---

# Palette Swap

Recolor sprites for **$ARGUMENTS**.

## Paths (update on first use)

If any path below says `UPDATE_ME`, ask the user for the correct path, then immediately Edit this skill file to fill it in before proceeding.

- **Project sprites:** `assets/sprites/`
- **Project effects:** `assets/effects/`

## Tool

`python tools/palette_swap.py <command> [options]`

Two commands: `analyze` and `swap`.

## Step 1: Analyze the source

```
python tools/palette_swap.py analyze <image>
```

Prints every unique color grouped by 30° hue bucket, with hex, HSV, and pixel count. Identify the hue range to replace.

If the user hasn't specified a target palette, also analyze reference sprites to find candidate colors.

## Step 2: Pick the target palette

- Match color count to source colors in the hue range (1:1 by luminance rank is cleanest)
- If counts don't match, the tool maps by nearest luminance
- Pull target colors from existing sprites in the same visual family for consistency
- Ensure good luminance spread (dark → bright) to preserve shading

## Step 3: Swap

```
python tools/palette_swap.py swap <image> --hue-range LO HI --palette HEX1 HEX2 HEX3 ... -o <output>
```

- `--hue-range LO HI`: Hue degrees (0-360). Supports wrap (e.g., `340 20` for reds)
- `--palette`: Space-separated hex colors (no `#`). Sorted by luminance internally
- `--min-sat`: Saturation floor (default 0.08). Raise to exclude desaturated colors sharing the hue range
- `-o`: Output path

## Step 4: Review

Read the output PNG to visually verify. Common fixes:
- Washed out → more saturated target colors
- Lost contrast → spread luminance range
- Wrong colors caught → narrow `--hue-range` or raise `--min-sat`

Always write output to a separate file first. Only overwrite the original after confirmation.
