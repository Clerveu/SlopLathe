class_name ChainControlTransferEffect
extends Resource
## Effect sub-resource: re-apply `status` to the nearest uncontrolled same-faction
## neighbor within `radius` of the effect target at `duration_factor` of the CC's
## base_duration. "Uncontrolled" = no "CC"-tagged active status on the candidate.
## The bearer (effect target) is explicitly excluded — spec prohibits re-CC'ing
## the original target.
##
## Dispatched from chain_control_tracker_{root,stun,fear}'s on_expire_effects.
## Each tracker carries its matching CC definition so transferred instances
## preserve type identity (Stun transfers as Stun, Root as Root, Fear as Fear).
##
## The apply call uses suppress_triggers=true so the transferred CC does NOT
## emit on_status_applied — downstream expire-chain listeners (Iron Grip,
## Silence of the Grave, Chain Control itself) do NOT re-arm on the receiving
## enemy. Chain terminates cleanly after one hop per original WD application.
##
## Duration math: passing base_duration × duration_factor as duration_override
## lets apply_status re-apply source-side duration bonuses (Faithful Rites,
## Swollen Stacks), producing exactly 50% of whatever the original CC's applied
## duration was under the same source.
##
## First consumer: Witch Doctor Chain Control (Puppeteer T2).

@export var status: StatusEffectDefinition  ## CC definition to re-apply on the uncontrolled neighbor
@export var radius: float = 30.0            ## Neighbor search radius (px)
@export var duration_factor: float = 0.5    ## Multiplier on status.base_duration for the transferred instance
