class_name HealChainEffect
extends Resource
## Schedules a delayed chain of heals, each hop jumping to the nearest injured
## ally within max_range of the previous target. Queued into combat_manager at
## dispatch time; ticked against run_time for deterministic replay.
##
## Each hop is an independent HealEffect (same pipeline as direct heals — crit,
## healing_bonus, healing_received, Curse inversion all apply). Dispatch fires
## on_heal with attribution_tag so trigger listeners (Spirit Link, etc.) can react.

@export var hops: Array[Resource] = []       ## Ordered Array[HealEffect] — one per chain step
@export var chain_delay: float = 0.25        ## Seconds between hops (and between primary cast and hop 0)
@export var max_range: float = 50.0          ## Search radius from previous target for next target
@export var attribution_tag: String = ""     ## on_heal tag; falls back to dispatch attribution when empty
@export var target_vfx_layers: Array = []    ## VfxLayerConfig / ParticleVfxLayerConfig spawned on each hop target
@export var chain_preset: ParticleFxPreset   ## Particle bolt spawned from previous target toward next target, one chain_delay before each heal (null = no chain particles)
