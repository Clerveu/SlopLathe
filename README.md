# SlopLathe

A data-driven 2D game engine kit for Godot 4.6. Born from the unholy union of one man's autobattler obsession and several hundred hours of arguing with an AI about whether `ClassDefinition` should be called `UnitDefinition`.

Everything is a Resource. Abilities, statuses, effects, triggers, modifiers — all data definitions interpreted by generic systems. You describe *what* you want in factory functions; the engine figures out the rest. 37 effect types, 29 condition types, 6 entity components, and a damage pipeline with more steps than your morning coffee routine.

**It's not a game. It's the plumbing.** You bring the game. The plumbing brings: entities that fight, get buffed, get debuffed, shoot projectiles, summon friends, knock each other around, chain-heal, echo-cast, and die in a variety of entertaining configurations — all without writing a single `if entity_id == "my_specific_guy"` branch.

## Install

1. Clone this repo
2. Open in [Godot 4.6](https://godotengine.org/download)
3. That's it. There is no step 3.

## Getting Started

1. Read `CLAUDE.md` — it's short, it's the rules, it's important
2. Look at `data/examples/` — three working factories showing the patterns
3. Read `docs/content_guide.md` when you want to build something
4. Read `docs/traps.md` before you modify anything that sounds important
5. Use `/design` to spec new systems, `/implement` to build them
6. Make a game

## What's In The Box

| Thing | Count | What It Does |
|---|---|---|
| Effect types | 37 | Every way one entity can ruin another entity's day (or improve it) |
| Trigger conditions | 22 | Every reason an effect should or shouldn't fire |
| Ability conditions | 7 | Every reason an ability should or shouldn't cast |
| Entity components | 6 | Health, modifiers, abilities, statuses, triggers, AI |
| Systems | 13 | Damage calc, projectiles, displacement, movement, VFX, particles, spatial grid, ground zones, ... |
| Skills | 5 | /design, /implement, /palette-swap, /process-sprites, /tile |
| Python tools | 3 | Sprite extraction, palette swapping, shadow .tres generation |
| Opinions about architecture | Mass-casualty |

## What's NOT In The Box

- Game content (that's your job)
- Art assets (also your job)
- A scrolling background system (too game-specific, build your own)
- An item/equipment system (modifiers do the same thing with less drama)
- A replay system (cool but you don't need it yet)
- Menus, UI screens, talent trees (build to taste)

## Requirements

- [Godot 4.6](https://godotengine.org/download) (GL Compatibility renderer)
- [Claude Code](https://claude.ai/claude-code) or Claude Pro (for the skills)
- Python 3 + Pillow (`pip install Pillow`) for sprite tools
- A game idea
- Mass quantities of persistence

## License

Do whatever you want with it. It's a gift.
