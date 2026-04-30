class_name EchoSourceConfig
extends Resource
## Per-source configuration for the echo replay primitive. Every echo source in
## the game (Cleric Salvation, future Wizard Spell Echo / Arcane Ascension, any
## echo-related talent / status / ability) declares itself through one of these.
## The engine treats all echo sources identically at the scheduling layer;
## variation lives entirely in field values.
##
## Two registration pathways read this Resource:
##   - Status-driven: StatusEffectDefinition.echo_source — active while a status
##     with this field set is on the bearer (Salvation's "echo" status).
##   - Modifier-driven: TalentDefinition.echo_sources — registered onto
##     ModifierComponent._echo_sources at entity setup, permanent for the run.
##
## Capture happens in entity._on_ability_requested before any path routing,
## so a cast that APPLIES echo (Salvation) does not self-echo.

@export var source_id: String = ""           ## Identifier for on_echo payload + trigger filters + telemetry. Also keys the per-bearer cadence counter when cadence_every_n > 0.
@export var delay: float = 1.0               ## Default seconds between original cast dispatch and echo replay
@export var power_multiplier: float = 1.0    ## 1.0 = full power; 0.6 = Spell Echo / Arcane Ascension
@export var proc_chance: float = 1.0         ## 1.0 = always, <1.0 = roll per trigger (Spell Echo)
@export var consumes_source: bool = true     ## true = source status is consumed on use (Salvation)
@export var capture_targets: bool = false    ## Default false = re-resolve at replay time (decision #65)
@export var allow_auto_attacks: bool = false ## Default false — AAs excluded by design
@export var allow_channels: bool = false     ## Default false — channels excluded by design
@export var allow_skills: bool = true        ## Default true — skills (non-AA, non-Channel) allowed (Salvation). Set false for AA-only echoes (Ranger Echo Shot).
@export var recursion_cap: int = 1           ## Max replay depth; currently enforced as "1 = no recursion"
@export var cadence_every_n: int = 0         ## 0 = echo every eligible cast (default, Salvation). N>0 = echo every Nth eligible cast (per-bearer counter keyed by source_id). First consumer: Ranger Echo Shot (every 3rd AA).
@export var suppress_crit: bool = false      ## true = echoed hits skip crit roll ("no free proc velocity"). First consumer: Ranger Echo Shot. Applies via HitData.is_echo + DamageCalculator.
@export var ability_tag_whitelist: Array[String] = []  ## Empty = any tag. Non-empty = ability must carry at least one listed tag for the echo to fire (entity._echo_source_eligible). First consumer: items keyed to "Projectile" / "Spell" categories.
@export var ability_tag_blacklist: Array[String] = []  ## Empty = no exclusions. Non-empty = ability must carry NONE of the listed tags. Composes with the whitelist (both must pass). Same eligibility check site as the existing AA / Channel / Skill bool gates.
