class_name AttributeDerivation
extends RefCounted
## Stateless utility. Raw attribute values in, derived combat stats out.
## All tuning constants in one place for easy balancing.

# ── Stamina (Stam) ──
const HP_PER_STAM := 25.0
const STATUS_RESIST_PER_STAM := 0.005        ## 0.5% per point
const REGEN_PER_STAM := 0.1                  ## HP/sec
const SHIELD_EFF_PER_STAM := 0.01            ## 1% per point
const BLOCK_CHANCE_PER_STAM := 0.005         ## 0.5% per point
const BLOCK_CAP := 0.50                      ## 50% max block chance

# ── Strength (Str) ──
const CRIT_DAMAGE_PER_STR := 0.02            ## 2% per point
const BLOCK_MIT_PER_STR := 0.03              ## 3% mitigation per point
const BLOCK_MIT_CAP := 0.75                  ## 75% max block mitigation

# ── Intelligence (Int) ──
## CDR is modifier-only; CDR_CAP clamps the sum of `("All", "cooldown_reduce")` modifiers.
const CDR_CAP := 0.50                        ## 50% max cooldown reduction
const POTENCY_PER_INT := 0.01                ## 1% per point
const DURATION_PER_INT := 0.05               ## 0.05s per point

# ── Dexterity (Dex) ──
const CRIT_CHANCE_PER_DEX := 0.005           ## 0.5% per point
const CRIT_CAP := 0.75                       ## 75% max crit chance
const DODGE_PER_DEX := 0.005                 ## 0.5% per point
const DODGE_CAP := 0.50                      ## 50% max dodge
const BASE_MOVE_SPEED := 25.0                ## Pixels/sec at 0 Dex
const MSPD_PER_DEX := 0.01                   ## 1% per point

# ── Charisma (Cha) ──
const CC_DURATION_PER_CHA := 0.03            ## 0.03s per point
const SUMMON_STR_PER_CHA := 0.01             ## 1% per point
const BASE_AURA_RANGE := 40.0               ## Pixels
const AURA_RANGE_PER_CHA := 0.01             ## 1% per point
const PROC_MOD_PER_CHA := 0.003              ## 0.3% per point


# ── Stamina derivations ──

static func derive_max_hp(stam: float) -> float:
	return stam * HP_PER_STAM

static func derive_status_resistance(stam: float) -> float:
	return stam * STATUS_RESIST_PER_STAM

static func derive_hp_regen(stam: float) -> float:
	return stam * REGEN_PER_STAM

static func derive_shield_effectiveness(stam: float) -> float:
	return stam * SHIELD_EFF_PER_STAM

static func derive_block_chance(stam: float) -> float:
	return clampf(stam * BLOCK_CHANCE_PER_STAM, 0.0, BLOCK_CAP)


# ── Strength derivations ──

static func derive_crit_damage(str_val: float) -> float:
	return str_val * CRIT_DAMAGE_PER_STR

static func derive_block_mitigation(str_val: float) -> float:
	return clampf(str_val * BLOCK_MIT_PER_STR, 0.0, BLOCK_MIT_CAP)


# ── Intelligence derivations ──

static func derive_buff_potency(int_val: float) -> float:
	return int_val * POTENCY_PER_INT

static func derive_duration_modifier(int_val: float) -> float:
	return int_val * DURATION_PER_INT


# ── Dexterity derivations ──

static func derive_crit_chance(dex: float) -> float:
	return clampf(dex * CRIT_CHANCE_PER_DEX, 0.0, CRIT_CAP)

static func derive_dodge_chance(dex: float) -> float:
	return clampf(dex * DODGE_PER_DEX, 0.0, DODGE_CAP)

static func derive_move_speed(dex: float) -> float:
	return BASE_MOVE_SPEED * (1.0 + dex * MSPD_PER_DEX)


# ── Charisma derivations ──

static func derive_cc_duration(cha: float) -> float:
	return cha * CC_DURATION_PER_CHA

static func derive_summon_strength(cha: float) -> float:
	return cha * SUMMON_STR_PER_CHA

static func derive_aura_range(cha: float) -> float:
	return BASE_AURA_RANGE * (1.0 + cha * AURA_RANGE_PER_CHA)

static func derive_proc_chance_modifier(cha: float) -> float:
	return cha * PROC_MOD_PER_CHA
