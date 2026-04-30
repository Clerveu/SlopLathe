# SlopLathe Engine Kit

Data-driven 2D game engine built in Godot 4.6 / GDScript. Everything is a Resource. Abilities, statuses, effects, triggers, modifiers — all data definitions interpreted by generic systems. New game content = new Resource instances in factory functions, not new code paths.

## Architecture Invariant

Four layers, strict dependency direction:

**Data Resources** (`data/`) → **Components** (`entities/components/`) → **Systems** (`systems/`) → **Orchestration** (`scenes/run/combat_manager.gd`)

- Abilities are `AbilityDefinition` Resources with an `effects` array of typed effect Resources
- `EffectDispatcher` routes all 37 effect types through a single dispatch point
- `StatusEffectDefinition` composes modifiers, tick effects, trigger listeners, and lifecycle hooks — all as data
- `ModifierComponent` aggregates stat modifiers via `sum_modifiers(tag, operation)` — the universal stat query
- `TriggerComponent` registers event listeners that fire effects on EventBus signals
- All combat randomness flows through `combat_manager.rng` (seeded, deterministic)

## Critical Rules

1. **New content = new data, never new code paths.** Create Resource instances in factory functions. Register via `UnitRegistry`. If you're adding `if entity_id == "specific_thing"` branches, you're doing it wrong.
2. **New effect type = Resource subclass + one `elif` branch in `effect_dispatcher.gd`.** That's the entire extension surface.
3. **New condition type = Resource subclass + one branch in `ability_component.gd:_check_conditions` or `trigger_component.gd:_check_trigger_conditions`.**
4. **Factories build Resources; `UnitRegistry` stores them.** Call `UnitRegistry.register_unit()` / `register_enemy()` at startup. `combat_manager._build_enemy_roster()` reads from there.
5. **Read the example factories first.** `data/examples/` has working patterns for units, enemies, and zones. Match the shape.

## File Map

| Directory | Contents |
|---|---|
| `autoloads/` | EventBus (signal vocabulary), UnitRegistry (definition storage), GameState (persistent save data) |
| `data/` | All Resource definitions — abilities, statuses, modifiers, effects, conditions, triggers, projectiles, choreography, zones, waves |
| `data/examples/` | Working factory examples — start here for any new content type |
| `entities/` | Entity scene + script (animation state machine, ability pipeline, choreography, echo scheduling) |
| `entities/components/` | HealthComponent, ModifierComponent, AbilityComponent, StatusEffectComponent, TriggerComponent, BehaviorComponent, HPBar |
| `systems/` | Stateless utilities + managers — EffectDispatcher, DamageCalculator, SpatialGrid, ProjectileManager, DisplacementSystem, MovementSystem, VfxManager, ParticleManager, GroundZone, HitData, AttributeDerivation, CombatTracker, DebugDraw |
| `scenes/run/` | CombatManager (simulation orchestrator), CombatFeedbackManager (floating numbers), run scene |
| `scenes/effects/` | VfxEffect (animated sprite one-shot/loop) |

## Documentation

| Doc | When to read |
|---|---|
| [architecture.md](docs/architecture.md) | First session, or when you need to understand how systems connect |
| [content_guide.md](docs/content_guide.md) | When creating new units, enemies, abilities, statuses, zones, or extending the engine with new effect/condition types |
| [traps.md](docs/traps.md) | When modifying entity.gd, combat_manager.gd, status_effect_component.gd, or any cross-system interaction |

## Autoloads

- **EventBus** — 45 signals. All combat events flow through here. TriggerComponent listeners connect to these.
- **UnitRegistry** — `register_unit(id, def)`, `register_enemy(id, def)`, `get_unit_def(id)`, `get_enemy_def(id)`. Populate in a startup script.
- **GameState** — `party`, `cleared_zones`, `current_tier`. Persistent across runs.

## Combat Manager Public API

- `spawn_unit(unit_def, faction, pos, base_stats, threat)` → spawn a player-faction entity
- `spawn_enemy_entity(enemy_def, pos)` → spawn an enemy-faction entity
- `apply_upgrades(entity, tree, picks)` → register modifiers + triggers + ability modifications from a TalentTreeDefinition
- `spawn_summon(summoner, ability, effect)` → spawn summon entities from SummonEffect
- `spawn_ground_zone(effect, source, pos)` → create persistent area effect
- `schedule_echo(source, ability, config, delay, targets)` → queue echo replay
- `revive_entity(corpse, hp_percent, source)` → resurrect a corpse
