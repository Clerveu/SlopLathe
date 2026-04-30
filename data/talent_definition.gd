class_name TalentDefinition
extends Resource
## A single talent node. Same field pattern as StatusEffectDefinition —
## direct arrays of existing primitives, not a wrapper type.

@export var talent_id: String = ""
@export var talent_name: String = ""
@export var description: String = ""
@export var branch: String = ""              ## "intro", "a", "b"
@export var tier: int = 0                    ## 0 (intro), 1-3 (branch), 4 (capstone)

## What this talent does — same building blocks as items/statuses
@export var modifiers: Array[Resource] = []                  ## ModifierDefinitions (registered at entity setup)
@export var trigger_listeners: Array[Resource] = []          ## TriggerListenerDefinitions (registered at entity setup)
@export var ability_modifications: Array[Resource] = []      ## AbilityModifications (applied to abilities at entity setup)
@export var apply_statuses: Array[Resource] = []             ## ApplyStatusEffectData (applied at entity setup, after components wired)
@export var echo_sources: Array[EchoSourceConfig] = []       ## EchoSourceConfigs registered onto ModifierComponent at entity setup (permanent for the run)
@export var status_modifier_injections: Dictionary = {}       ## status_id (String) -> Array[ModifierDefinition]. At entity setup, each modifier is registered onto ModifierComponent; when the bearer applies that status to anyone, the modifier is snapshotted onto the ActiveStatus and scaled per-stack by _sync_modifiers (same shape as definition modifiers). First consumer: Wizard Scorched (Burn → +3% Fire vulnerability per stack on bearer).

## Capstone-specific
@export var unlocks_skill_id: String = ""    ## ability_id of the ultimate this capstone unlocks
