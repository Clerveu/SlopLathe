class_name TalentTreeDefinition
extends Resource

@export var talents: Array[TalentDefinition] = []


func get_talent(talent_id: String) -> TalentDefinition:
	for talent in talents:
		if talent.talent_id == talent_id:
			return talent
	return null


func validate_picks(picks: Array[String]) -> bool:
	if picks.size() > 5:
		return false

	var seen: Dictionary = {}
	for pick in picks:
		if seen.has(pick):
			return false
		seen[pick] = true

	var picked_talents: Array[TalentDefinition] = []
	for pick in picks:
		var talent := get_talent(pick)
		if not talent:
			return false
		picked_talents.append(talent)

	var intro_count := 0
	for talent in picked_talents:
		if talent.branch == "intro":
			intro_count += 1
	if intro_count > 1:
		return false

	var has_intro := false
	var has_branch := false
	for talent in picked_talents:
		if talent.branch == "intro":
			has_intro = true
		elif talent.tier >= 1:
			has_branch = true
	if has_branch and not has_intro:
		return false

	for talent in picked_talents:
		if talent.tier <= 0 or talent.branch == "intro":
			continue
		if talent.tier == 4:
			for required_tier in [1, 2, 3]:
				if not _has_pick_in_branch_tier(picked_talents, talent.branch, required_tier):
					return false
		else:
			if talent.tier > 1:
				if not _has_pick_in_branch_tier(picked_talents, talent.branch, talent.tier - 1):
					return false

	return true


func _has_pick_in_branch_tier(picked: Array[TalentDefinition], branch: String,
		tier: int) -> bool:
	for talent in picked:
		if talent.branch == branch and talent.tier == tier:
			return true
	return false
