class_name ChoreographyPhase
extends Resource
## One phase of a ChoreographyDefinition sequence.
## Each phase can play an animation, fire effects, execute displacement,
## set entity flags, and branch conditionally to the next phase.

## What happens in this phase
@export var animation: String = ""                    ## Anim to play ("" = hold current frame)
@export var effects: Array[Resource] = []             ## Effect sub-resources to fire
@export var hit_frame: int = -1                       ## Frame to fire effects (-1 = fire on phase entry)
@export var displacement: DisplacementEffect          ## Displacement to execute (null = none)
@export var retarget: TargetingRule                    ## Resolve fresh targets for this phase (null = keep previous)

## Entity state during this phase
@export var set_untargetable: bool = false
@export var set_invulnerable: bool = false

## How this phase ends
@export var exit_type: String = "anim_finished"       ## "anim_finished", "wait", "displacement_complete"
@export var wait_duration: float = 0.0                ## For "wait" exit type (max seconds)

## What comes next
@export var default_next: int = -1                    ## Phase index (-1 = end choreography)
@export var branches: Array[ChoreographyBranch] = []  ## Conditional branching (evaluated during "wait" exit type)
