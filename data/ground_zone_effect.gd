class_name GroundZoneEffect
extends Resource
## Effect sub-resource: spawn a persistent ground zone at a world position.
## The zone ticks periodically, applying effects to entities within its radius.
## Used by Seismic Throw (Tremor zone), Earthsplitter, and future area denial abilities.

@export var zone_id: String = ""                  ## For identification/debugging
@export var radius: float = 20.0                  ## Radius in pixels
@export var duration: float = 4.0                 ## How long the zone persists (seconds)
@export var tick_interval: float = 0.5            ## How often tick_effects fire (seconds)
@export var target_faction: String = "enemy"      ## "enemy" or "ally" — which faction is affected
@export var tick_effects: Array[Resource] = []    ## Effects applied to entities in range each tick
@export var vfx_layers: Array[Resource] = []      ## ParticleVfxLayerConfig / VfxLayerConfig entries spawned on zone birth. Looping presets released on expire.
@export var center_on_source: bool = false                  ## When true, zone spawns at caster position instead of target
@export var debug_color: Color = Color(0, 0, 0, 0)          ## When alpha > 0, GroundZone self-draws a filled ring of this color for the zone's lifetime. Pragmatic visual stand-in when no particle VFX is authored — picked up as a fallback by abilities like Scorched Earth.
