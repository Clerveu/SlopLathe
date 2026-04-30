class_name ChoreographyDefinition
extends Resource
## Data-driven multi-phase ability sequence. Replaces bespoke ConcealPhaseConfig
## with a generic system that can express any complexity level:
##   - 1 phase: simple dash-strike
##   - 3 phases: dash → strike → retreat
##   - 5+ phases: Conceal Strike's hide → wait → emerge → branch attack → displacement
##
## Lives on AbilityDefinition.choreography. Executor lives on entity.gd.

@export var phases: Array[ChoreographyPhase] = []

## If true, the entity's X position drifts with background scroll every frame
## during the choreography, and arc/linear displacement inside phases tracks
## scroll in its start+end anchors. Ability choreographies (Conceal Strike,
## dash-strike) leave this false — they're screen-space sequences. Spawn intros
## that emerge from a background feature (water inlet, cave mouth) set it true
## so the entity stays visually pinned to that feature through the whole intro.
@export var scroll_anchor: bool = false
