extends "res://tests/crowd_combat.gd"


func _plan(kinds: Array) -> void:
	_reset()
	game.wave_spawn_plan.clear()
	for kind in kinds:
		var spec: Dictionary = game.enemy_definitions[String(kind)].duplicate(true)
		spec["enemy_id"] = kind
		spec["xp_value"] = 0
		game.wave_spawn_plan.append(spec)
	game.wave_spawned_count = 0
	game.wave_resolved_count = 0
	game.horde_positions.clear()
	game.horde_slot = 0
	game.horde_pulse_index = 0
	game.spawn_timer = 0.0
	game.wave_spawning = true


func _side(position: Vector2, size: Vector2) -> int:
	if position.y < 0: return 0
	if position.x > size.x: return 1
	if position.y > size.y: return 2
	if position.x < 0: return 3
	return -1


func _run() -> void:
	seed(71)
	game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	center = game.get_viewport_rect().size * 0.5
	var size: Vector2 = game.get_viewport_rect().size
	var formation = load("res://scripts/combat/horde_formation.gd")
	var seeded_rng := RandomNumberGenerator.new()
	for test_seed in range(100):
		seeded_rng.seed = test_seed
		for fronts in [1, 2]:
			var points: Array[Vector2] = formation.entry_positions(120, size, seeded_rng, fronts)
			_check(points.size() == 120, "Formation count")
			var sides := {}
			for point in points:
				var edge := _side(point, size)
				_check(edge >= 0, "Formation must enter from outside the arena")
				sides[edge] = true
			_check(sides.size() == fronts, "Formation front count")
			if fronts == 2:
				var edges: Array = sides.keys()
				_check(absi(int(edges[0]) - int(edges[1])) == 2, "Two-front formations must be opposite")
	# A single director update must release a whole packed front, not 1-3 bodies.
	var kinds: Array = []
	kinds.resize(500)
	kinds.fill("basic")
	_plan(kinds)
	game.current_wave = 9
	game.rng.seed = 11
	game._update_horde_spawning(0.0)
	_check(game.enemies.size() == 100, "Wave 9 must launch a 100-body horde in one update")
	var side := _side(game.enemies[0]["position"], size)
	for enemy in game.enemies:
		_check(_side(enemy["position"], size) == side, "Pack members must share an entry front")
		_check(is_equal_approx(float(enemy["speed"]), game.horde_speed), "Basic pack movement must stay coherent")
		var close_neighbor := false
		for neighbor in game.enemies:
			if enemy["uid"] != neighbor["uid"] and Vector2(enemy["position"]).distance_to(neighbor["position"]) < 31.0:
				close_neighbor = true
				break
		_check(close_neighbor, "Pack members must have nearby reaction targets")
	game._update_horde_spawning(0.5)
	_check(game.enemies.size() == 100, "No enemy trickle between pulses")
	game._update_horde_spawning(game.spawn_timer + 0.01)
	_check(game.enemies.size() == 200, "Second pulse")
	game._update_horde_spawning(game.spawn_timer + 0.01)
	var third_sides := {}
	for i in range(200, 300):
		third_sides[_side(game.enemies[i]["position"], size)] = true
	_check(third_sides.size() == 2, "Third late pulse must use two fronts")
	game._update_horde_spawning(game.spawn_timer + 0.01)
	_check(game.enemies.size() == 336 and game.horde_slot == 36, "Active cap must retain the rest of a formation")
	var pulse: int = game.horde_pulse_index
	for i in range(10):
		game._kill_enemy(0, game.enemies[0]["position"])
	game._update_horde_spawning(0.13)
	_check(game.enemies.size() == 336 and game.horde_slot == 46, "Held pack resumes without losing slots")
	_check(game.horde_pulse_index == pulse, "Capacity retry must not start another pulse")
	# Gates remain correct inside a large pulse.
	_plan(["jammer", "jammer", "basic"])
	game._update_horde_spawning(0.0)
	_check(game.wave_spawned_count == 2 and game.horde_slot == 2, "Priority gate holds remaining pack")
	var priority_index := -1
	for i in range(game.enemies.size()):
		if bool(game.enemies[i].get("priority", false)): priority_index = i
	game._kill_enemy(priority_index, game.enemies[priority_index]["position"])
	game._update_horde_spawning(0.13)
	_check(game.wave_spawned_count == 3 and not game.wave_spawning, "Priority-held pack resumes")
	_plan(["basic", "overseer"])
	game._update_horde_spawning(0.0)
	_check(game.wave_spawned_count == 1, "Boss cannot enter with horde still alive")
	game._kill_enemy(0, game.enemies[0]["position"])
	game.pending_reactions.append({})
	game._update_horde_spawning(0.13)
	_check(game.wave_spawned_count == 1, "Boss waits for queued damage")
	game.pending_reactions.clear()
	game._update_horde_spawning(0.13)
	_check(game.wave_spawned_count == 2 and bool(game.enemies[0]["boss"]), "Boss enters after horde resolves")
	# A reaction can kill a real cluster in one event.
	_reset()
	var first_uid := -1
	for x in range(5):
		for y in range(5):
			var uid := _enemy(Vector2(120 + x * 18, y * 18 - 36), 30)
			if x == 2 and y == 2: first_uid = uid
	var target: Dictionary = game.enemies[game._get_enemy_index_by_uid(first_uid)]
	target["statuses"] = {"freeze": {"remaining": 2.0}}
	game._queue_matching_reactions(target, ["blast"], target["position"])
	game._process_pending_reactions()
	_check(game.enemies.is_empty(), "Shatter should clear the 25-body cluster")
	# More damage choices and their effect on real attack descriptors.
	_reset()
	for id in ["smg_payload", "smg_damage", "global_damage"]:
		_take(id)
	var attack: Dictionary = game.combat.build_attacks("correct_key")[0]
	_check(is_equal_approx(float(attack["damage"]), 14.625), "Flat payload must scale with weapon and global damage")
	_reset()
	for id in ["global_damage", "smg_damage", "smg_payload"]:
		_take(id)
	attack = game.combat.build_attacks("correct_key")[0]
	_check(is_equal_approx(float(attack["damage"]), 14.625), "Modifier order must not depend on pick order")
	for sample in range(100):
		var choices: Array = game._roll_upgrade_choices(3)
		var categories := {}
		var initials := {}
		for choice in choices:
			categories[choice["category"]] = true
			var initial := String(choice["command"]).left(1)
			_check(not initials.has(initial), "Choice command ambiguity")
			initials[initial] = true
		_check(categories.has("damage") and categories.has("crowd"), "Choices need both damage and crowd coverage")
	# New prerequisites and reaction radius compose with the existing system.
	var wide: Dictionary = {}
	var bloom: Dictionary = {}
	for upgrade in game.upgrade_definitions:
		if upgrade["id"] == "pistol_radius": wide = upgrade
		if upgrade["id"] == "reaction_radius": bloom = upgrade
	_check(not game._upgrade_is_available(wide) and not game._upgrade_is_available(bloom), "No dead prerequisite choices")
	_take("unlock_pistol")
	_take("pistol_echo")
	_enemy(Vector2(100, 0))
	_enemy(Vector2(0, 100))
	game._emit_combat_trigger("word_complete")
	_check(game.bullets.size() == 2 and game.bullets[0]["target_uid"] != game.bullets[1]["target_uid"], "Echo Chamber splits pistol targets")
	_take("pistol_explosion")
	_take("pistol_radius")
	_take("cryo_rounds")
	_take("reaction_radius")
	var reactions: Array = game.combat.resolve_reactions({"freeze": {}}, ["blast"])
	_check(is_equal_approx(float(reactions[0]["area_radius"]), 98.4), "Reaction Bloom radius")
	game.combat.equip_loadout("starter")
	reactions = game.combat.resolve_reactions({"freeze": {}}, ["blast"])
	_check(is_equal_approx(float(reactions[0]["area_radius"]), 82.0), "Reaction radius resets with run")
	print("Horde pulse checks: ", checks, "; failures: ", failures)
	game.free()
	quit(1 if failures > 0 else 0)
