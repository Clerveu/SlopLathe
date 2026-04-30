class_name DamageCalculator
extends RefCounted
## Stateless utility. Takes source, target, ability, effect → returns HitData.
## 8-step pipeline: base → conversion → offensive mods → dodge → block → resist → vuln → crit.

const RESIST_K := 100.0  ## Tuning constant for resistance formula


static func calculate_damage(source: Node2D, target: Node2D,
		ability: AbilityDefinition, effect: DealDamageEffect,
		rng: RandomNumberGenerator = null,
		power_multiplier: float = 1.0,
		echo_source: EchoSourceConfig = null,
		contributors: Array = []) -> HitData:
	var src_mods: ModifierComponent = source.modifier_component
	var tgt_mods: ModifierComponent = target.modifier_component

	# Step 1: Base hit — base_damage * (1 + attribute * coefficient)
	var attr_value := src_mods.sum_modifiers(effect.scaling_attribute, "add")
	var raw := effect.base_damage * (1.0 + attr_value * effect.scaling_coefficient)

	# Step 1.5: Missing-HP damage scaling (intrinsic to effect, first consumer: Ranger Executioner)
	if effect.missing_hp_damage_scaling > 0.0:
		var missing_frac: float = 1.0 - (target.health.current_hp / target.health.max_hp)
		raw *= 1.0 + missing_frac * effect.missing_hp_damage_scaling

	# Step 2: Conversion (once only, True damage immune)
	var original_type := effect.damage_type
	var damage_type := _apply_conversion(source, original_type)

	# Step 3: Offensive modifiers (additive within category)
	# Per synergy vocabulary: bonuses to both original and converted type apply
	# "All" bonus applies to every damage type (e.g. Berserk's +20% damage)
	# Per-tag ability bonus sums (e.g. "+20% AOE damage", "+10% Spell damage")
	# fold in additively alongside type / All. Skipped when ability is null
	# (DOT ticks, status-driven raw damage carry no ability context).
	var damage_bonus := src_mods.sum_modifiers(damage_type, "bonus")
	if damage_type != original_type:
		damage_bonus += src_mods.sum_modifiers(original_type, "bonus")
	damage_bonus += src_mods.sum_modifiers("All", "bonus")
	if ability != null:
		for tag in ability.tags:
			damage_bonus += src_mods.sum_modifiers(tag, "bonus")
	raw *= (1.0 + damage_bonus)

	# Step 4: Dodge check
	var dex := tgt_mods.sum_modifiers("Dex", "add")
	var dodge_chance := AttributeDerivation.derive_dodge_chance(dex)
	if dodge_chance > 0.0 and (rng.randf() if rng else randf()) < dodge_chance:
		var dodge_hit := HitData.create(0.0, damage_type, source, target, ability)
		dodge_hit.original_damage_type = original_type
		dodge_hit.is_dodged = true
		dodge_hit.is_echo = (echo_source != null)
		if not contributors.is_empty():
			for c in contributors:
				if c is Dictionary:
					dodge_hit.contributors.append(c)
		EventBus.on_dodge.emit(source, target, dodge_hit)
		return dodge_hit

	# Step 5: Block check (partial mitigation).
	# Block chance rolls off Stam (defensive stat). Mitigation strength rolls off
	# Str (offensive force) — Stam = how often you block, Str = how hard the block
	# absorbs. The two axes are intentionally on different stats so a build can
	# invest in chance without inherently buying mitigation and vice versa.
	var is_blocked := false
	var block_mitigated := 0.0
	var stam_val := tgt_mods.sum_modifiers("Stam", "add")
	var block_chance := AttributeDerivation.derive_block_chance(stam_val)
	if block_chance > 0.0 and (rng.randf() if rng else randf()) < block_chance:
		is_blocked = true
		var str_val := tgt_mods.sum_modifiers("Str", "add")
		var block_percent := AttributeDerivation.derive_block_mitigation(str_val)
		block_mitigated = raw * block_percent
		raw -= block_mitigated

	# Step 6: Resistance (per damage type — "armor" is just Physical resist)
	# Pierce is percentage-based: 0.25 = ignore 25% of target's resistance
	var resist := tgt_mods.sum_modifiers(damage_type, "resist")
	var pierce := src_mods.sum_modifiers(damage_type, "pierce")
	var effective_resist := maxf(0.0, resist * (1.0 - pierce))
	raw *= (1.0 - effective_resist / (effective_resist + RESIST_K))

	# Step 6.5: Damage taken modifiers (status effects, abilities — additive then multiplied)
	# Target-side per-tag damage_taken folds in alongside type / All so item
	# defenses keyed by ability tag work symmetrically with the offensive sweep
	# in Step 3 ("-20% damage from Spells" → modifier keyed by tag "Spell").
	var pre_dr := raw  # Pre-DR snapshot for dr_mitigated tracking (Fortified Guard, etc.)
	var damage_taken := tgt_mods.sum_modifiers(damage_type, "damage_taken")
	damage_taken += tgt_mods.sum_modifiers("All", "damage_taken")
	if ability != null:
		for tag in ability.tags:
			damage_taken += tgt_mods.sum_modifiers(tag, "damage_taken")
	if damage_taken != 0.0:
		raw *= maxf(0.0, 1.0 + damage_taken)
	var dr_mitigated := pre_dr - raw  # Positive = damage was reduced (DR), negative = amplified

	# Step 7: Vulnerability (additive — per-type + "All", same pattern as damage_taken)
	# Target-side per-tag vulnerability folds in for tag-keyed amp items.
	var vulnerability := tgt_mods.sum_modifiers(damage_type, "vulnerability")
	vulnerability += tgt_mods.sum_modifiers("All", "vulnerability")
	if ability != null:
		for tag in ability.tags:
			vulnerability += tgt_mods.sum_modifiers(tag, "vulnerability")
	raw *= (1.0 + vulnerability)

	# Step 7.5: Echo power scaling (applied before crit so crits scale the echoed base)
	if power_multiplier != 1.0:
		raw = raw * power_multiplier

	# Step 8: Crit — skipped entirely when echo_source.suppress_crit is set
	# (Ranger Echo Shot / Fusillade: "echoes cannot crit, preserving the no free
	# proc velocity principle"). Echo sources without suppress_crit still roll.
	var is_crit := false
	if not (echo_source != null and echo_source.suppress_crit):
		var src_dex := src_mods.sum_modifiers("Dex", "add")
		var crit_chance := AttributeDerivation.derive_crit_chance(src_dex)
		# Flat crit chance bonuses from modifiers (e.g. Focus stacks)
		crit_chance += src_mods.sum_modifiers("crit_chance", "add")
		if crit_chance > 0.0 and (rng.randf() if rng else randf()) < crit_chance:
			is_crit = true
			var src_str := src_mods.sum_modifiers("Str", "add")
			var crit_damage := AttributeDerivation.derive_crit_damage(src_str)
			raw *= (1.0 + crit_damage)

	# Step 9: Post-pipeline flat bonus (e.g. banked damage from Crown Shot paint).
	# Added raw, post-crit — the bonus is expected to already be a final damage
	# number (it was accumulated from prior post-pipeline amounts) and shouldn't
	# be double-multiplied by crit / vuln / resist.
	if effect.flat_bonus_damage > 0.0:
		raw += effect.flat_bonus_damage

	# Build HitData
	var hit := HitData.create(maxf(raw, 0.0), damage_type, source, target, ability)
	hit.original_damage_type = original_type
	hit.is_crit = is_crit
	hit.is_blocked = is_blocked
	hit.block_mitigated = block_mitigated
	hit.dr_mitigated = dr_mitigated
	hit.is_echo = (echo_source != null)
	if not contributors.is_empty():
		for c in contributors:
			if c is Dictionary:
				hit.contributors.append(c)

	# Fire block event after HitData is constructed
	if is_blocked:
		EventBus.on_block.emit(source, target, hit, block_mitigated)

	return hit


static func calculate_healing(source: Node2D, target: Node2D,
		effect: HealEffect, rng: RandomNumberGenerator = null,
		power_multiplier: float = 1.0) -> float:
	## 5-step healing pipeline: base → healing bonus → healing received → crit → Curse.
	var src_mods: ModifierComponent = source.modifier_component
	var tgt_mods: ModifierComponent = target.modifier_component

	# Step 1: Base heal — attribute-scaled or percent-max-HP
	var raw: float
	if effect.percent_max_hp > 0.0:
		raw = target.health.max_hp * effect.percent_max_hp
	else:
		var attr_value := src_mods.sum_modifiers(effect.scaling_attribute, "add")
		raw = effect.base_healing * (1.0 + attr_value * effect.scaling_coefficient)

	# Step 2: Healing bonus (additive, from source)
	var healing_bonus := src_mods.sum_modifiers("Heal", "bonus")
	# Conditional amplifier: extra healing when target has an active HoT.
	# First consumer: Cleric Deepening Faith (+20% heal on HoT targets).
	if target.status_effect_component.has_active_hot():
		healing_bonus += src_mods.sum_modifiers("Heal", "hot_target_bonus")
	raw *= (1.0 + healing_bonus)

	# Step 3: Healing received (additive, from target)
	var healing_received := tgt_mods.sum_modifiers("Heal", "received_bonus")
	raw *= (1.0 + healing_received)

	# Step 3.5: Echo power scaling (applied before crit so crit heals scale the echoed base)
	if power_multiplier != 1.0:
		raw = raw * power_multiplier

	# Step 4: Crit heal — chance off Int (not Dex), multiplier off Str.
	# Chance-on-Int keeps healers' crit coverage on their primary scaling stat so
	# they aren't forced into a Dex tax. Crit damage stays on Str to preserve the
	# "force of the hit" identity Str carries on the damage side.
	var src_int := src_mods.sum_modifiers("Int", "add")
	var crit_chance := AttributeDerivation.derive_crit_chance(src_int)
	if crit_chance > 0.0 and (rng.randf() if rng else randf()) < crit_chance:
		var src_str := src_mods.sum_modifiers("Str", "add")
		var crit_damage := AttributeDerivation.derive_crit_damage(src_str)
		raw *= (1.0 + crit_damage)

	# Step 5: Curse check handled by EffectDispatcher (checks after heal amount is computed,
	# routes to calculate_curse_damage() if target has a Curse status).

	return maxf(raw, 0.0)


static func calculate_curse_damage(source: Node2D, target: Node2D,
		heal_amount: float) -> HitData:
	## Curse inversion: healing amount enters damage pipeline as typed damage.
	## Applies resistance + vulnerability only. No crit, no block, no dodge.
	var tgt_mods: ModifierComponent = target.modifier_component

	# Read curse damage type from the active Curse status
	var curse_def: StatusEffectDefinition = target.status_effect_component.get_definition("curse")
	var curse_type: String = curse_def.curse_damage_type if curse_def and curse_def.curse_damage_type != "" else "Shadow"

	var raw: float = heal_amount

	# Resistance (same formula as damage pipeline Step 6)
	var resist: float = tgt_mods.sum_modifiers(curse_type, "resist")
	var effective_resist: float = maxf(0.0, resist)  # No pierce on curse damage
	raw *= (1.0 - effective_resist / (effective_resist + RESIST_K))

	# Vulnerability (same as damage pipeline Step 7 — per-type + "All")
	var vulnerability: float = tgt_mods.sum_modifiers(curse_type, "vulnerability")
	vulnerability += tgt_mods.sum_modifiers("All", "vulnerability")
	raw *= (1.0 + vulnerability)

	# No crit, no block, no dodge — create HitData directly
	var hit := HitData.create(maxf(raw, 0.0), curse_type, source, target, null)
	hit.original_damage_type = curse_type
	return hit


static func _apply_conversion(source: Node2D, original_type: String) -> String:
	if original_type == "True":
		return original_type
	var src_mods: ModifierComponent = source.modifier_component
	var conversion := src_mods.get_first_conversion(original_type)
	if conversion:
		EventBus.on_conversion.emit(source, original_type, conversion.target_type)
		return conversion.target_type
	return original_type
