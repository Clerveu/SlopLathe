class_name ChoreographyBranch
extends Resource
## Conditional branch within a ChoreographyPhase.
## During a "wait" exit type, branches are evaluated each frame.
## First branch whose condition passes wins. If none pass by timeout, default_next is used.

@export var condition: Resource                        ## Typed condition sub-resource (same pool as ability conditions)
@export var next_phase: int = -1                      ## Phase index to jump to when condition met
