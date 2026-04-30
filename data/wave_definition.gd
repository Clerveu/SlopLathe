class_name WaveDefinition
extends Resource
## Defines a group of enemies that spawn together at a trigger point.

## Trigger dispatch axis. For "background_position" (scroll-position trigger),
## trigger_value is reinterpreted as a pixel X inside the scrolling background's
## texture — fire occurs each time distance_traveled crosses that pixel as the
## background cycles. Width-invariant: the texture width is read live from
## background.texture.get_width(), so zones with different backgrounds author
## triggers against their own texture's coordinate space.
@export var trigger_type: String = "distance"      ## "distance", "time", "arena_time", "background_position"
@export var trigger_value: float = 0.0             ## distance_traveled / run_time / arena_time seconds / texture-space pixel X
@export var entries: Array = []                    ## [{enemy_id: String, count: int, spawn_offset: Vector2, spawn_position_absolute: Vector2 (optional — overrides offset + default X=340)}]
@export var spawn_side: String = ""                ## Override zone default ("" = use zone's)

## Marks wave entities as load-bearing for the clear condition. When every entity
## spawned from any is_boss_wave wave is dead AND the arena is active, the run
## ends with "cleared". Entities inherit is_aggroed = true on spawn so they
## engage under own move_speed rather than waiting for scroll-based drift.
@export var is_boss_wave: bool = false

## Background-position trigger controls. Unused for distance/time/arena_time types.
@export var skip_first_cycles: int = 0             ## Suppress fires while the scroll-cycle index is below this (e.g. 1 = don't fire on the first pass)
@export var repeats: bool = false                  ## If true, wave re-fires each scroll cycle instead of being one-shot
@export var stop_when_arena_active: bool = false   ## If true, skip firing when in_boss_arena = true

## Force is_aggroed = true on spawn — new entities walk to nearest hero under own
## move_speed instead of scroll-drifting. Separate from is_boss_wave (which also
## force-aggroes but additionally participates in the clear condition).
@export var aggro_on_spawn: bool = false

## Re-fire interval (seconds of trigger-axis time) for distance / time / arena_time
## triggered waves. After the initial trigger fires, the wave fires again every
## `repeat_interval` seconds of its own axis. 0 = one-shot (existing behavior,
## backward-compatible). Distinct from `repeats` (background_position cycle-based
## re-fire) — both can be set independently.
@export var repeat_interval: float = 0.0

## HP-scaled floor for repeat_interval. When > 0, the effective interval is
## lerp(min_repeat_interval, repeat_interval, boss_hp_percent) — full boss HP →
## interval is `repeat_interval`, dead boss → interval is `min_repeat_interval`.
## Boss HP read from the first alive `is_boss` entity in `_boss_wave_entities`.
## 0 = no scaling. Pairs with `requires_boss_alive` (which gates spawning entirely
## once the boss is dead) so the floor only applies during the fight.
@export var min_repeat_interval: float = 0.0

## When > 0, suppress wave fire if the count of alive entities previously spawned
## from this wave >= max_alive. Used for slot-limited add waves (one wave per
## ranged scout slot, max_alive=1 keeps that slot to a single occupant). 0 = no
## cap. Combat manager tracks `_wave_entities[wave_index]` for the count.
@export var max_alive: int = 0

## Gate spawning on the boss being alive. When true, the wave only fires if at
## least one entity in `_boss_wave_entities` has `is_boss == true` AND `is_alive`.
## Used for boss-summoned add waves so adds stop spawning once the boss falls.
@export var requires_boss_alive: bool = false
