# Traps

Cross-file interactions that aren't visible from reading any single file. If you're modifying the files listed, read the relevant section first.

## Component Tick Order (combat_manager.gd + all components)

Status → ability cooldowns → behavior. This order is load-bearing: status expiry/modifier changes must be visible to ability conditions and AI decisions in the same frame. Reordering breaks abilities that gate on status state.

## Hit-Frame Dispatch (entity.gd + ability_component.gd)

`_ability_anim_active` prevents auto-attacks from corrupting `_pending_ability` / `_pending_targets` mid-ability-animation. Without it, BehaviorComponent's per-frame AA timer silently overwrites ability state during long animations. Also suppresses movement during ability animations (ranged entities hold position instead of retreating).

`_execute_pending_effects()` always re-resolves targets via `hit_targeting` when set — trigger targeting determines "should this fire?", hit_targeting determines "who gets hit?".

## Choreography Re-assertion (entity.gd + displacement_system.gd)

`is_channeling` is RE-ASSERTED at the start of every `_enter_choreography_phase`. DisplacementSystem's `_on_arrival` clears `is_channeling` as its completion signal, but subsequent phases still need it active. Only `_end_choreography` clears it for real. Any choreography with phases after a displacement phase relies on this.

Choreography targets are deliberately NOT carried from cast-time. Phase-level `retarget` resolves fresh targets per-phase.

## Echo Scheduling (entity.gd + combat_manager.gd)

Echo capture happens in `_on_ability_requested` BEFORE any effect dispatch. Pre-dispatch capture is load-bearing: a cast that applies echo (e.g., a buff granting echo to allies) must NOT self-echo, because the caster's echo state is read before the buff's effects fire.

## Death Event Ordering (combat_manager.gd + health_component.gd)

`on_death` fires BEFORE corpse append and BEFORE the heroes array is filtered. When an on_death trigger listener fires, the dying entity is: still in `heroes`, NOT yet in `corpses`, `is_alive = false`, `is_corpse = false`.

`revive_entity`'s `heroes.has()` guard prevents double-entry when a mid-dispatch revive hits an entity that was never removed from heroes.

Death prevention check fires BEFORE `died` signal — prevention effects apply while entity is still alive.

## Status Lifecycle (status_effect_component.gd + trigger_component.gd)

- `on_apply_effects` fire on FIRST application only, not stack refresh
- `on_expire_effects` fire on natural expiry only (duration runs out), NOT on death
- `notify_hit_dealt` only fires for ability-driven hits (`hit_data.ability != null`) to prevent recursion from proc damage
- Reflected hits (`is_reflected`) and echo hits (`is_echo`) skip `notify_hit_received` — recursion/proc-velocity guards
- Status trigger listeners register on first apply, unregister on ALL removal paths

## EffectDispatcher Dead Target Handling (effect_dispatcher.gd + entity.gd)

`execute_effects()` filters dead targets at the per-target iteration boundary. But whole-array effects (OverflowChainEffect, DisplacementEffect, SpawnProjectilesEffect) receive the unfiltered array. OverflowChainEffect DEPENDS on receiving dead targets (iterates `t.health.is_dead` to find overkill). Don't pre-filter before `execute_effects()`.

## Trigger Scope (trigger_component.gd)

EventBus hit signals (`on_hit_dealt`, `on_hit_received`) emit ONCE and ALL registered listeners on every entity see them. The trigger pipeline does NOT auto-scope by event side. Without an explicit `TriggerConditionTargetIsSelf` (receive-side) or `TriggerConditionSourceIsSelf` (deal-side), a listener will fire from the wrong perspective.

## VFX Frame Minimum (entity.gd)

`vfx_frame` minimum is 1, not 0. Godot's `frame_changed` signal is unreliable at frame 0 (doesn't fire when new animation starts at same frame index as previous).

## Summon Faction (combat_manager.gd)

Summons append to `heroes` regardless of summoner faction — the faction field on the entity itself determines targeting. Untargetable summons are excluded from spatial grid but still ticked via the `heroes` master list.

## Modifier Source Convention

Upgrades/talents use `source_name = "talent_<id>"`. Items (if you build an equipment system) should use `source_name = "item_<id>"`. Two distinct prefix spaces means removal-by-source can't accidentally clobber across systems.
