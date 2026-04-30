class_name TransferStatusToNeighborsEffect
extends Resource
## Effect sub-resource: read `status`'s current stacks on the effect target,
## then apply the same status (at floor(target_stacks × stack_factor)) to the
## N nearest same-faction entities around the target (excluding the target
## itself). Skipped cleanly when the target has no stacks to transfer or no
## living same-faction neighbors exist.
##
## Designed for death-triggered propagation: typically dispatched from an
## on_death trigger listener whose condition set already filters to victims
## carrying `status`. By the time dispatch runs, the target may be
## `is_alive = false`; the stack-count read goes through the still-intact
## StatusEffectComponent, and the neighbor search walks the spatial grid pool
## with per-candidate `is_alive` filtering (the grid rebuilds at frame start,
## so same-frame deaths are still present and must be filtered manually).
##
## The apply call threads the dispatching source (the talent owner) through as
## the status applier so status_modifier_injections keyed to that source snap
## onto the transferred instance — Corrode transferred by the WD carries
## Rotting Touch's Magical shred and Decay's threshold boost.
##
## First consumer: Witch Doctor Infectious (Afflictor T1).

@export var status: StatusEffectDefinition  ## Status whose stacks are read from target and propagated
@export var neighbor_count: int = 2         ## Up to this many nearest same-faction entities receive the transfer
@export var stack_factor: float = 0.5       ## Transferred stacks = int(target_stacks × stack_factor); skipped if 0
