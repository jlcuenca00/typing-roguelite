extends "res://tests/crowd_combat.gd"


func _find(id: String) -> Dictionary:
	for upgrade in game.upgrade_definitions:
		if String(upgrade["id"]) == id:
			return upgrade
	return {}


func _attack(weapon_id: String) -> Dictionary:
	var trigger := "correct_key" if weapon_id == "smg" else "word_complete"
	for attack in game.combat.build_attacks(trigger):
		if String(attack["weapon_id"]) == weapon_id:
			return attack
	return {}


func _run() -> void:
	seed(49)
	game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	_reset()
	for upgrade in game.upgrade_definitions:
		if upgrade.has("ranks"):
			_check(upgrade["ranks"].size() == int(upgrade["max_picks"]), "Rank count must match pick cap")
	# Offer previews and application resolve the same rank, with no data mutation.
	var original := _find("smg_damage").duplicate(true)
	for factor in [1.5, 1.65, 1.8]:
		var preview: Dictionary = game._upgrade_for_next_rank(_find("smg_damage"))
		_check(is_equal_approx(float(preview["factor"]), factor), "Wrong next-rank preview")
		_check(game._upgrade_for_next_rank(preview) == preview, "Resolving an offer must be idempotent")
		var previous := float(_attack("smg")["damage"])
		_take("smg_damage")
		_check(is_equal_approx(float(_attack("smg")["damage"]), previous * factor), "Rank preview/application mismatch")
	_check(_find("smg_damage") == original, "Rank resolution mutated upgrade definitions")
	_check(not game._upgrade_is_available(_find("smg_damage")), "Maxed upgrade must disappear")
	# Coverage ranks grow faster instead of repeating their first increment.
	for id in ["smg_pierce", "smg_multishot"]:
		for pick in range(int(_find(id)["max_picks"])):
			_take(id)
	_check(int(_attack("smg")["pierce"]) == 9, "SMG pierce ranks must total nine extra targets")
	_check(int(_attack("smg")["projectile_count"]) == 4, "Split Feed ranks must total four bullets")
	_take("unlock_shotgun")
	for pick in range(3):
		_take("shotgun_pellet")
	_check(int(_attack("shotgun")["projectile_count"]) == 17, "Shotgun ranks must total seventeen pellets")
	_take("unlock_arc_coil")
	for pick in range(3):
		_take("arc_chain")
	_check(int(_attack("arc_coil")["chain_count"]) == 13, "Arc ranks must reach thirteen targets")
	_check(is_equal_approx(float(_attack("arc_coil")["chain_range"]), 200), "Arc jump range bonuses")
	_take("unlock_pistol")
	for pick in range(3):
		_take("pistol_explosion")
	_check(is_equal_approx(float(_attack("pistol")["explosion_ratio"]), 2.9), "Explosion rank damage")
	_check(is_equal_approx(float(_attack("pistol")["explosion_radius"]), 104), "Explosion rank radius")
	# Stronger late ranks still use normal hit protection and phase gates.
	for id in ["pistol_damage", "global_damage"]:
		for pick in range(int(_find(id)["max_picks"])):
			_take(id)
	var boss := _enemy(Vector2(80, 0), 1000, "overseer")
	game._emit_combat_trigger("word_complete")
	game._update_bullets(0.2)
	game._process_pending_reactions()
	var index: int = game._get_enemy_index_by_uid(boss)
	_check(index >= 0 and bool(game.enemies[index].get("boss_shielded", false)), "Late build must retain boss lock")
	_check(_hp(boss) >= 660, "Late splash must not skip boss phase")
	# Clear a real wave through the normal finish/continue paths at reduced HP.
	_reset()
	game.current_wave = 4
	game.hp = 27.0
	game.pending_level_ups = 0
	game._finish_wave()
	_check(game.hp == 27.0, "Wave clear must not grant healing")
	game._start_next_wave()
	_check(game.hp == 27.0, "Starting a wave must not grant healing")
	game.set_process(false)
	game._apply_upgrade(game._upgrade_for_next_rank(_find("smg_damage")))
	_check(game.hp == 27.0, "Offensive ranks must not grant healing")
	game.combat.equip_loadout("starter")
	_check(is_equal_approx(float(_attack("smg")["damage"]), 5.5), "Rank modifiers must reset with run")
	print("Upgrade rank checks: ", checks, "; failures: ", failures)
	game.free()
	quit(1 if failures > 0 else 0)
