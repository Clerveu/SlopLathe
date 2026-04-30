class_name ResurrectEffect
extends Resource
## Effect that resurrects an ally corpse.
## Default mode: resurrect the nearest same-faction corpse from combat_manager.corpses —
## corpse selection is intrinsic to the effect (same pattern as SummonEffect owning spawn logic).
## target_dying_entity mode: use the dispatch target directly as the revive target.
## Load-bearing for on_death-driven revives (Undying Pact): the dying entity is
## emitted as the event target BEFORE combat_manager appends it to corpses, so
## get_nearest_corpse can't find it yet. target_dying_entity bypasses the corpse
## lookup and uses the in-flight dispatch target, which is still a valid Node2D
## with is_alive=false / is_corpse=false. Filtering to persist_as_corpse entities
## happens in the dispatcher so summons (which don't persist as corpses) can't be
## revived through this path.

@export var hp_percent: float = 0.50  ## Fraction of max_hp to restore (0.0-1.0)
@export var target_dying_entity: bool = false  ## True = revive the dispatch target instead of nearest corpse (for on_death listener dispatch before corpse is appended)
@export var post_revive_status: StatusEffectDefinition = null  ## Applied to the revived entity after the revive completes. First consumer: Witch Doctor Empowered Revive (5s invuln + haste + damage bonus recovery window).
