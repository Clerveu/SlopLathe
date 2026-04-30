# Architecture

## Data Flow

An ability cast flows through the system like this:

```
BehaviorComponent.tick() picks highest-priority ready ability
  → resolve targets via TargetingRule + SpatialGrid
  → entity._on_ability_requested(ability, targets)
    → echo scheduling (captures before effects fire)
    → animation state machine (attack anim plays)
    → _on_frame_changed fires at hit_frame
      → _execute_pending_effects()
        → EffectDispatcher.execute_effects(ability.effects, source, targets, ...)
          → per-effect dispatch: DealDamageEffect → DamageCalculator
                                 ApplyStatusEffectData → StatusEffectComponent
                                 SpawnProjectilesEffect → ProjectileManager
                                 etc.
        → ability_modification groups dispatch (same pipeline)
```

Status tick effects follow the same tail: `StatusEffectComponent.tick()` → `EffectDispatcher.execute_effect()`.

Trigger listeners: `EventBus signal` → `TriggerComponent._on_<event>()` → evaluate conditions → `EffectDispatcher.execute_effect()`.

## Simulation Tick Order

`combat_manager._advance_simulation(delta)` runs each physics frame:

1. `run_time += delta`
2. Filter dead entities from master lists
3. `spatial_grid.rebuild(heroes, enemies)`
4. Party wipe check
5. `movement_system.update()` — movement, engagement, facing
6. Proximity detonation check
7. **Component ticks (status → ability → behavior)** — this order is load-bearing: status expiry and modifier changes must be visible to conditions and AI decisions in the same frame
8. `_tick_ground_zones(delta)` — persistent area effects
9. `_check_wave_spawns()` — authored wave triggers
10. `_check_summon_expiries()` — duration-based summon death
11. `_tick_heal_chains()` — deferred chain heals
12. `_tick_echoes()` — deferred echo replays
13. Timer-based random spawns (interval shrinks over run_time)

## Entity Lifecycle

**Spawn:** `combat_manager.spawn_unit()` or `spawn_enemy_entity()` → instantiate `entity.tscn` → seed base stats as modifiers → inject `combat_manager` + `spatial_grid` refs → call `setup_from_unit_def()` or `setup_from_enemy_def()` → position → connect `died` signal → append to `heroes`/`enemies` list.

**Alive:** Ticked each frame via component ticks. SpatialGrid registers targetable entities. BehaviorComponent drives ability/AA decisions. MovementSystem handles positioning.

**Death:** `_on_entity_died()` → cleanup movement/VFX/slots → emit proximity_exit → cleanup triggers → fire on_death_effects → emit EventBus on_death/on_kill → handle summon death cascade → notify allies → corpse tracking (if `persist_as_corpse`).

**Corpse:** Entity stays in scene with `is_alive = false`. Not in `heroes`/`enemies` lists, not in spatial grid. Available for `revive_entity()`.

## Modifier System

`ModifierDefinition` has three fields that matter: `target_tag`, `operation`, `value`.

`ModifierComponent.sum_modifiers(tag, operation)` returns the sum of all matching modifiers. This is the universal stat query — DamageCalculator, BehaviorComponent, MovementSystem, and StatusEffectComponent all read through it.

Common operations: `"add"` (flat), `"bonus"` (percentage), `"resist"`, `"pierce"`, `"vulnerability"`, `"damage_taken"`, `"negate"` (immunity flag), `"cooldown_reduce"`.

Modifiers come from: base stats (seeded at spawn), upgrades/talents, status effects (per-stack scaling), and direct application via `ApplyModifierEffectData`.

## Damage Pipeline

`DamageCalculator.calculate_damage()` — 9 steps:
1. Base: `attribute_value × scaling_coefficient`
2. Missing HP scaling (optional per-effect)
3. Conversion (damage type swap)
4. Offensive modifiers (`bonus` by damage type + ability tags + "All")
5. Dodge (Dex-derived chance)
6. Block (Stam-derived chance, Str-derived mitigation)
7. Resistance + pierce
8. Vulnerability + damage_taken modifiers
9. Crit (Dex-derived chance, Str-derived damage)

`calculate_healing()` — 5 steps: base → healing bonus → healing received → crit → curse inversion.

## Attribute System

`systems/attribute_derivation.gd` ships with Str/Dex/Int/Stam/Cha as working examples. Replace the constants and derivation functions for your game's attributes. The DamageCalculator and entity setup read these derivations — trace the call sites to see where each attribute feeds.
