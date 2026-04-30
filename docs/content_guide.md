# Content Guide

Pattern pointers for creating game content. Read the referenced example files — they ARE the documentation for each pattern's shape.

## Units & Enemies

Same pattern, different Resource type. Factory function builds and returns the definition.

| What | Resource | Example | Register with |
|---|---|---|---|
| Player unit | `UnitDefinition` | `data/examples/example_melee_unit.gd` | `UnitRegistry.register_unit(id, def)` |
| Enemy | `EnemyDefinition` | `data/examples/example_ranged_enemy.gd` | `UnitRegistry.register_enemy(id, def)` |

**Spawn at runtime:** `combat_manager.spawn_unit(def, faction, pos, stats, threat)` or `combat_manager.spawn_enemy_entity(def, pos)`.

**Key fields on both:** `auto_attack` (AbilityDefinition), `skills` (Array[SkillDefinition]), `sprite_sheet`, `hit_frame`, `combat_role` ("MELEE"/"RANGED"), `engage_distance`, `move_speed`.

**Enemy extras:** `aggro_range` (0 = always aware), `is_elite`/`is_boss`, `spawn_intro` (ChoreographyDefinition), `apply_statuses`, `on_death_effects`, `detonate_range`.

## Abilities

An `AbilityDefinition` is a targeting rule + an effects array + cooldown/priority/conditions. See `example_melee_unit.gd:25-45` for AA, `:48-73` for a skill.

**Key fields:** `ability_id`, `tags` (for damage pipeline tag sweeps), `targeting` (TargetingRule), `effects` (Array of effect Resources), `cooldown_base`, `priority` (higher = checked first), `conditions` (Array of condition Resources), `hit_targeting` (optional wider area for damage resolution).

**Wrap in SkillDefinition** for the skill slot system: `skill.ability = your_ability`, `skill.unlock_level = N`.

## Statuses

`StatusEffectDefinition` — see `example_melee_unit.gd:55-64` for a simple buff.

**Key fields:** `status_id`, `is_positive`, `max_stacks`, `base_duration`, `modifiers` (Array[ModifierDefinition] — registered per-stack), `tick_interval` + `tick_effects`, `on_apply_effects`, `on_expire_effects`, `on_hit_received_effects`, `on_hit_dealt_effects`, `trigger_listeners`, `disables_actions`/`disables_movement`.

Applied via `ApplyStatusEffectData` effect in an ability's effects array.

## Zones & Waves

`ZoneDefinition` + `WaveDefinition` — see `data/examples/example_zone.gd`.

**Zone:** `enemy_roster` (weighted random spawns), `waves` (authored triggers), spawn timing params, `ground_y_range`.

**Wave triggers:** `"time"` (fires at N seconds), `"distance"` (fires at N distance). Each wave has `entries` array of `{enemy_id, count, spawn_offset}`. `aggro_on_spawn`, `repeat_interval`, `max_alive` for gating.

**Start a run:** `main.start_run(zone_def)`.

## Upgrades / Talents

`TalentDefinition` bundles modifiers + trigger listeners + ability modifications + statuses. `TalentTreeDefinition` collects them with validation.

**Apply to entity:** `combat_manager.apply_upgrades(entity, tree, picks)`. Handles the three-phase registration (modifiers before setup for stat derivation, triggers + statuses after, ability modifications last with replacement-before-additive ordering).

## Choreography

Multi-phase ability sequences — see `data/choreography_definition.gd`, `choreography_phase.gd`, `choreography_branch.gd`. Set `ability.choreography` to use.

Each phase: animation + effects (on entry or at hit_frame) + optional displacement + entity flags (untargetable/invulnerable) + exit condition ("anim_finished"/"wait"/"displacement_complete") + conditional branching.

## Extending the Engine

**New effect type:**
1. Create `data/my_effect.gd` — Resource with `class_name` and `@export` fields
2. Add one `elif effect is MyEffect:` branch in `systems/effect_dispatcher.gd:execute_effect()`

**New condition type (ability gating):**
1. Create `data/condition_my_thing.gd` — Resource with fields
2. Add branch in `entities/components/ability_component.gd:_check_conditions()`

**New trigger condition (event filtering):**
1. Create `data/trigger_condition_my_thing.gd` — Resource with fields
2. Add branch in `entities/components/trigger_component.gd:_check_trigger_conditions()`

**New targeting type:**
1. Add branch in `entities/components/behavior_component.gd:resolve_targets_with_rule()`

---

## Effect Catalogue

All live in `data/`. Each is a Resource subclass dispatched by `systems/effect_dispatcher.gd`.

| Effect | Purpose |
|---|---|
| `DealDamageEffect` | Attribute-scaled damage through full pipeline |
| `HealEffect` | Attribute-scaled healing (curse-aware) |
| `ApplyStatusEffectData` | Apply status with stacks/duration (`apply_to_self` for self-buffs) |
| `ApplyShieldEffect` | Attribute-scaled shield |
| `ApplyModifierEffectData` | Direct modifier with duration |
| `CleanseEffect` | Remove statuses by count/polarity/id |
| `SpawnProjectilesEffect` | Fire projectiles (radial/aimed/at_targets patterns) |
| `SummonEffect` | Spawn entity from UnitDefinition template |
| `DisplacementEffect` | Knockback/pull/charge/teleport with arrival effects |
| `AreaDamageEffect` | AOE damage around target position |
| `GroundZoneEffect` | Persistent ticking area at a position |
| `ConsumeStacksEffect` | Eat stacks, fire per_stack_effects per consumed |
| `ExecuteEffect` | Instakill (raw HP drain, no pipeline) |
| `ResurrectEffect` | Revive a corpse at HP% |
| `RefundCooldownEffect` | Shave seconds off cooldown (named ability or all slots) |
| `GrantAbilityChargeEffect` | Free-cast charges that bypass cooldown/conditions |
| `ExtendStatusDurationEffect` | Add seconds to an active status |
| `SetMaxStacksEffect` | Set status to max stacks (conditional on talent pick) |
| `RefreshHotsEffect` | Reset all HoT timers on target |
| `AmplifyActiveStatusEffect` | Multiply duration + tick rate of active status |
| `DeathAreaDamageEffect` | Flat AOE on death (no attribute scaling) |
| `ExtendActiveCooldownsEffect` | Multiply live cooldown_remaining |
| `HealChainEffect` | Multi-hop chain heal with delay between hops |
| `OverflowChainEffect` | Chain overkill damage to nearest enemy |
| `DamageByAmountEffect` | Trigger-only: % of event damage as new hit |
| `HealByAmountEffect` | Trigger-only: % of event heal amount |
| `FactionCleanseEffect` | Mass cleanse across faction |
| `SpreadStatusEffect` | Contagion: spread status to neighbors |
| `TransferStatusToNeighborsEffect` | Move status instances to nearby entities |
| `SnapshotAmplifyStatusesEffect` | Freeze + amplify all debuffs at a moment |
| `RedistributeCleansedStatusEffect` | Re-apply cleansed stacks to nearby enemies |
| `ApplyCleanseImmunityEffect` | Per-status-id reapplication immunity |
| `RefreshStatusInRadiusEffect` | Refresh a status on entities in radius |
| `SpawnBankedShotEffect` | Fire damage from accumulated bank on status |
| `PurgeWithRetaliationEffect` | Cleanse + counter-damage |
| `DispatchAbilityModificationsEffect` | Invoke ability mods without the base ability |
| `ChainControlTransferEffect` | Transfer CC with potency decay |

## Condition Catalogue

**Ability conditions** (gate casting) — live in `data/`, evaluated by `ability_component.gd`:

| Condition | Gates on |
|---|---|
| `ConditionHpThreshold` | Self/any_ally/any_enemy HP above/below % |
| `ConditionEntityCount` | Min N entities of faction in optional range |
| `ConditionStackCount` | Status stacks in [min, max] range |
| `ConditionSummonCount` | Living summons of type in [min, max] |
| `ConditionTakingDamage` | Hit received within time window |
| `ConditionTargetingCount` | Min enemies targeting this entity |
| `ConditionCorpseExists` | Faction corpse available |

**Trigger conditions** (filter events) — live in `data/`, evaluated by `trigger_component.gd`:

| Condition | Filters on |
|---|---|
| `TriggerConditionSourceIsSelf` | Event source == bearer |
| `TriggerConditionTargetIsSelf` | Event target == bearer |
| `TriggerConditionEventEntityFaction` | Source/target faction relative to bearer |
| `TriggerConditionStatusId` | Event status_id matches (negate-able) |
| `TriggerConditionAbilityId` | Hit ability_id matches |
| `TriggerConditionAbilityHasTag` | Hit ability has tag (negate-able) |
| `TriggerConditionHpThreshold` | Bearer HP above/below % |
| `TriggerConditionNotCrit` | Hit is not a crit |
| `TriggerConditionAttributionTag` | Attribution string matches (negate-able) |
| `TriggerConditionBearerHasStatus` | Bearer has/lacks a status (negate-able) |
| `TriggerConditionSourceIsSummon` | Source is bearer's summon |
| `TriggerConditionTargetIsSummon` | Target is a summon |
| `TriggerConditionTargetHasPositiveStatus` | Target has any buff |
| `TriggerConditionTargetHasNegativeStatus` | Target has any debuff |
| `TriggerConditionTargetHasStatus` | Target has specific status |
| `TriggerConditionTargetStatusAtMaxStacks` | Target's status at max |
| `TriggerConditionTargetHitByTag` | Target hit by tagged ability within window |
| `TriggerConditionTargetHotCount` | Target has ≥ N HoTs |
| `TriggerConditionTargetMatchesPriorityTier` | Target matches priority tier (negate-able) |
| `TriggerConditionHitExceedsMaxHpPercent` | Hit exceeds % of target max HP |
| `TriggerConditionHitIsEcho` | Hit is/isn't an echo replay (negate-able) |
| `TriggerConditionApplierIsSelf` | Cleansed status was applied by bearer |
