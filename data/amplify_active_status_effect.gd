class_name AmplifyActiveStatusEffect
extends Resource
## Self-resolving pool effect: scans all entities of `target_faction` (relative to
## source) and amplifies their active `status_id` instance in place — multiplying
## remaining duration and tick rate. The amplified state is detectable via
## ActiveStatus.is_enhanced(), which gates the application lockout in apply_status
## (no new stacks/refresh while enhanced) and the tick-rate auto-restore in tick()
## (reverts to _applied_tick_interval when time_remaining decays back below
## _applied_duration). Permanent statuses (duration < 0) are skipped.
##
## Generic shape: future "Surge" / "Ice Age" / etc. abilities reuse this with
## different status_ids and multipliers. First consumer: Wizard Conflagration
## (Pyromancer capstone — double Burn duration + tick rate on all enemies).

@export var status_id: String = ""
@export var duration_multiplier: float = 1.0   ## time_remaining *= this (2.0 = double duration)
@export var tick_rate_multiplier: float = 1.0   ## tick_interval /= this (2.0 = double rate = halve interval)
@export var target_faction: String = "enemy"    ## "enemy" or "ally" relative to source
