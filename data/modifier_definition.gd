class_name ModifierDefinition
extends Resource
## Universal modifier shape: modifier(target_tag, operation, value).
## Used by equipment, talents, status effects, run buffs — all the same shape.

@export var target_tag: String = ""        ## What this modifies: "Physical", "Fire", "Str", etc.
@export var operation: String = "add"      ## "add", "bonus", "multiply", "resist", "negate", "pierce",
                                           ## "cooldown_reduce", "duration_modify", "range_modify",
                                           ## "received_bonus", "vulnerability",
                                           ## "ally_debuff_stack_bonus", "ally_debuff_duration_bonus",
                                           ## "ally_debuff_tick_power_bonus" (keyed by polarity "debuff",
                                           ## read bearer-side in StatusEffectComponent.apply_status —
                                           ## each ally source of a debuff on the bearer contributes
                                           ## these into the incoming-debuff amplification. First
                                           ## consumer: Witch Doctor Amplifier — Afflictor T3.)
@export var value: float = 0.0
@export var min_stacks: int = 0            ## When > 0, modifier only active at this stack count; value is flat (not per-stack)
@export var decay: bool = false            ## When true, value scales linearly from full → 0 over status duration
@export var source_name: String = ""       ## For "Show your work" stat display
@export var require_target_priority_tier: Array[String] = []  ## Apply-time filter for status_modifier_injections: when non-empty, the injection
                                                              ## is included on an ActiveStatus only if the bearer matches one of these priority
                                                              ## tiers at apply time. Classification delegates to TargetingRule.entity_matches_priority_tier
                                                              ## (same matcher as "priority_tiered_enemy" targeting). Empty list = unconditional injection
                                                              ## (baseline behavior — Wizard Scorched, Ranger Deep Mark). Only consulted on the injection
                                                              ## path; has no effect on modifiers registered directly on ModifierComponent or carried
                                                              ## on a StatusEffectDefinition. First consumer: Ranger Marked For Death (+25% Physical
                                                              ## vulnerability injected into Mark only when the marked target is a priority target).
