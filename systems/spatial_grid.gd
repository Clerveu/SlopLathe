class_name SpatialGrid
extends RefCounted
## Fixed-cell spatial partitioning for fast proximity queries.
## Entities register by faction. Queries return candidates in nearby cells.
## Rebuilt every frame — simple, immune to teleport/tween edge cases.
##
## Grid covers 0-352 X (11 cols * 32px) and 0-224 Y (7 rows * 32px),
## spanning the full viewport plus spawn margin.

const CELL_SIZE := 32.0
const COLS := 11  ## ceil(352 / 32)
const ROWS := 7   ## ceil(224 / 32)
const TOTAL_CELLS := COLS * ROWS  ## 77

## Faction indices (match Entity.Faction enum: HERO=0, ENEMY=1)
const HERO := 0
const ENEMY := 1

## Per-faction cell storage: flat array indexed by cell_y * COLS + cell_x
var _cells: Array = [[], []]  ## [hero_cells, enemy_cells]
## Track which cells were written to, so clear only touches occupied cells
var _dirty: Array = [[], []]  ## [dirty_hero_keys, dirty_enemy_keys]
## Alive entity lists built during rebuild (replaces per-frame .filter() calls)
var _all: Array = [[], []]    ## [all_heroes, all_enemies]


func _init() -> void:
	for f in 2:
		var cells: Array = []
		cells.resize(TOTAL_CELLS)
		for i in TOTAL_CELLS:
			cells[i] = []
		_cells[f] = cells
		_dirty[f] = []
		_all[f] = []


func rebuild(heroes: Array, enemies: Array) -> void:
	## Clear previous frame, re-insert all alive entities.
	## Called once per frame before any movement or combat logic.
	_clear_dirty(HERO)
	_clear_dirty(ENEMY)
	# New arrays — NOT .clear(), because combat_manager.heroes/enemies may reference
	# the old _all arrays (from get_all()). Clearing in-place would empty the
	# input we're about to iterate.
	_all[HERO] = []
	_all[ENEMY] = []

	for e in heroes:
		if is_instance_valid(e) and e.is_alive and not e.is_untargetable:
			_all[HERO].append(e)
			_insert(e, HERO)

	for e in enemies:
		if is_instance_valid(e) and e.is_alive and not e.is_untargetable:
			_all[ENEMY].append(e)
			_insert(e, ENEMY)


func get_all(faction: int) -> Array:
	## Returns the alive-entity list for a faction. No allocation — returns the
	## internal array built during rebuild(). Do NOT modify the returned array.
	return _all[faction]


func get_nearby(pos: Vector2, faction: int) -> Array:
	## Returns all entities of the given faction in the cell containing pos
	## plus its 8 neighbors. Callers do final distance checks.
	## Filters `is_instance_valid(e)` per-iteration so same-tick queries after
	## an entity queue_free'd between the last rebuild and this call skip
	## stale cell references — the engine processes queue_free at end-of-frame
	## but the grid carries the reference until the next rebuild.
	var results: Array = []
	var cx := _col(pos.x)
	var cy := _row(pos.y)
	var cells: Array = _cells[faction]

	for dy in range(-1, 2):
		var ny := cy + dy
		if ny < 0 or ny >= ROWS:
			continue
		for dx in range(-1, 2):
			var nx := cx + dx
			if nx < 0 or nx >= COLS:
				continue
			var cell: Array = cells[ny * COLS + nx]
			for e in cell:
				if not is_instance_valid(e):
					continue
				results.append(e)
	return results


func get_nearby_in_range(pos: Vector2, faction: int, range_sq: float) -> Array:
	## Returns entities within squared distance of pos. Checks enough neighbor
	## rings to cover the range. For ranges <= CELL_SIZE, checks 3x3 (1 ring).
	## Filters `is_instance_valid(e)` per-iteration — see get_nearby for
	## rationale (same-tick stale-reference guard).
	var results: Array = []
	var cx := _col(pos.x)
	var cy := _row(pos.y)
	var cells: Array = _cells[faction]
	# How many cell rings to check (1 ring = 3x3, 2 rings = 5x5)
	var rings := 1 + int(sqrt(range_sq) / CELL_SIZE)

	for dy in range(-rings, rings + 1):
		var ny := cy + dy
		if ny < 0 or ny >= ROWS:
			continue
		for dx in range(-rings, rings + 1):
			var nx := cx + dx
			if nx < 0 or nx >= COLS:
				continue
			var cell: Array = cells[ny * COLS + nx]
			for e in cell:
				if not is_instance_valid(e):
					continue
				if pos.distance_squared_to(e.position) <= range_sq:
					results.append(e)
	return results


func find_nearest(pos: Vector2, faction: int) -> Node2D:
	## Returns the nearest alive entity of the given faction, or null.
	## Starts with 3x3 neighborhood, expands if empty.
	var best: Node2D = null
	var best_dist_sq := INF
	var cx := _col(pos.x)
	var cy := _row(pos.y)
	var cells: Array = _cells[faction]

	# Search expanding rings until we find something or exhaust the grid
	var max_ring := maxi(maxi(cx, COLS - 1 - cx), maxi(cy, ROWS - 1 - cy))
	for ring in range(0, max_ring + 1):
		var found_in_ring := false
		for dy in range(-ring, ring + 1):
			var ny := cy + dy
			if ny < 0 or ny >= ROWS:
				continue
			for dx in range(-ring, ring + 1):
				# Only check the border of this ring (skip interior — already checked)
				if ring > 0 and abs(dx) < ring and abs(dy) < ring:
					continue
				var nx := cx + dx
				if nx < 0 or nx >= COLS:
					continue
				var cell: Array = cells[ny * COLS + nx]
				for e in cell:
					if not is_instance_valid(e):
						continue
					var d_sq := pos.distance_squared_to(e.position)
					if d_sq < best_dist_sq:
						best_dist_sq = d_sq
						best = e
						found_in_ring = true
		# If we found something, check one more ring to ensure it's truly nearest
		# (entity in adjacent cell could be closer than one in same cell)
		if found_in_ring and ring > 0:
			break
	return best


func find_nearest_n(pos: Vector2, faction: int, count: int, range_sq: float) -> Array:
	## Returns up to count nearest entities within range, sorted nearest-first.
	## count <= 0 means unlimited (all in range).
	var candidates := get_nearby_in_range(pos, faction, range_sq)
	candidates.sort_custom(func(a, b):
		return pos.distance_squared_to(a.position) < pos.distance_squared_to(b.position))
	if count > 0 and candidates.size() > count:
		return candidates.slice(0, count)
	return candidates


func find_furthest(pos: Vector2, faction: int) -> Node2D:
	## Returns the furthest alive entity of the given faction, or null.
	## Must check all entities (no spatial shortcut for furthest). Filters
	## `is_instance_valid(e)` — same rationale as get_nearby.
	var best: Node2D = null
	var best_dist_sq := -1.0
	for e in _all[faction]:
		if not is_instance_valid(e):
			continue
		var d_sq := pos.distance_squared_to(e.position)
		if d_sq > best_dist_sq:
			best_dist_sq = d_sq
			best = e
	return best


# --- Internal ---

func _insert(entity: Node2D, faction: int) -> void:
	var key := _cell_key(entity.position)
	_cells[faction][key].append(entity)
	_dirty[faction].append(key)


func _clear_dirty(faction: int) -> void:
	var cells: Array = _cells[faction]
	var dirty: Array = _dirty[faction]
	for key in dirty:
		cells[key].clear()
	dirty.clear()


func _cell_key(pos: Vector2) -> int:
	var cx := _col(pos.x)
	var cy := _row(pos.y)
	return cy * COLS + cx


func _col(x: float) -> int:
	return clampi(int(x / CELL_SIZE), 0, COLS - 1)


func _row(y: float) -> int:
	return clampi(int(y / CELL_SIZE), 0, ROWS - 1)
