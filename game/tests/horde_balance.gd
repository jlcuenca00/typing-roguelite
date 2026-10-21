extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1


func _run() -> void:
	var game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	var expected_xp := [8, 12, 18, 28, 42, 68, 100, 160, 280, 440]
	var totals := []
	for wave in range(1, 11):
		var body_total := 0
		for seed_value in range(100):
			game.rng.seed = seed_value
			game._prepare_wave_spawn_plan(wave)
			var threat := 0
			var xp := 0
			var elites := 0
			for spec in game.wave_spawn_plan:
				threat += int(spec["threat_cost"])
				xp += int(spec["xp_value"])
				elites += int(bool(spec["elite"]))
				_check(int(spec["xp_value"]) >= 0, "Negative enemy XP")
			_check(threat == game._wave_threat_budget(wave), "Wave threat mismatch")
			_check(xp == expected_xp[wave - 1], "Perfect-clear XP changed")
			_check(elites == game._elite_count_for_wave(wave), "Elite count changed")
			if wave == 10:
				_check(bool(game.wave_spawn_plan.back().get("boss", false)), "Boss must be last")
			body_total += game.wave_spawn_plan.size()
		totals.append(float(body_total) / 100.0)
	# Exercise actual spawns at different waves and elapsed times, including boss.
	for enemy_id in game.enemy_definitions:
		var definition: Dictionary = game.enemy_definitions[enemy_id]
		var expected_hp := float(definition["base_hp"]) * float(definition["hp_multiplier"])
		for wave in [1, 7, 10]:
			for elapsed_time in [0.0, 600.0]:
				game.enemies.clear()
				game.current_wave = wave
				game.elapsed = elapsed_time
				if enemy_id == "swarmer":
					game._spawn_summoned_swarmers(Vector2.ZERO, 1)
				else:
					var spec := definition.duplicate(true)
					spec["enemy_id"] = enemy_id
					spec["xp_value"] = 2
					game.wave_spawn_plan.assign([spec])
					game.wave_spawned_count = 0
					game._spawn_enemy()
				_check(is_equal_approx(float(game.enemies[0]["max_hp"]), expected_hp), "HP inflation: " + enemy_id)
				if enemy_id == "swarmer":
					_check(game.enemies[0]["xp_value"] == 0, "Summons grant XP")
	# Elite modifier remains separate from fixed archetype HP.
	var elite: Dictionary = game.enemy_definitions["brute"].duplicate(true)
	elite["elite"] = true
	elite["enemy_id"] = "brute"
	game.enemies.clear()
	game.wave_spawn_plan.assign([elite])
	game.wave_spawned_count = 0
	game._spawn_enemy()
	_check(is_equal_approx(float(game.enemies[0]["max_hp"]), 44.0 * 2.35 * 1.55), "Elite HP modifier lost")
	# Dev clear must award assigned XP for both live and unspawned enemies.
	game.enemies.clear()
	game.particles.clear()
	game.current_wave = 6
	game._prepare_wave_spawn_plan(6)
	game._spawn_enemy()
	game.wave_spawned_count = 1
	game.xp_total = 0
	game._dev_perfect_clear_wave()
	_check(game.xp_total == 68, "Dev clear bypasses wave XP budget")
	for wave in range(1, 11):
		for sample in range(200):
			var batch: int = game._spawn_batch_for_wave(wave)
			_check(batch >= (2 if wave >= 9 else 1), "Batch too small")
			_check(batch <= (3 if wave >= 9 else 2 if wave >= 5 else 1), "Batch too large")
	print("Mean planned bodies per wave (100 seeds): ", totals)
	print("Horde balance failures: ", failures)
	game.free()
	quit(1 if failures > 0 else 0)
