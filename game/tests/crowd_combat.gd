extends SceneTree

var failures := 0
var checks := 0
var game
var center := Vector2(640, 360)


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		failures += 1


func _reset() -> void:
	game.enemies.clear()
	game.bullets.clear()
	game.pending_reactions.clear()
	game.particles.clear()
	game.lightning_arcs.clear()
	game.locked_target_uid = -1
	game.upgrade_levels.clear()
	game.combat.load_definitions()
	game.hp = game.max_hp
	game.current_wave = 7


func _enemy(offset: Vector2, hp_value: float = 100.0, kind: String = "basic") -> int:
	var spec: Dictionary = game.enemy_definitions[kind].duplicate(true)
	spec["enemy_id"] = kind
	spec["xp_value"] = 1
	game.wave_spawn_plan.assign([spec])
	game.wave_spawned_count = 0
	game._spawn_enemy()
	var enemy: Dictionary = game.enemies.back()
	enemy["position"] = center + offset
	enemy["hp"] = hp_value
	enemy["max_hp"] = hp_value
	return int(enemy["uid"])


func _hp(uid: int) -> float:
	var index: int = game._get_enemy_index_by_uid(uid)
	return float(game.enemies[index]["hp"]) if index >= 0 else 0.0


func _take(id: String) -> void:
	for upgrade in game.upgrade_definitions:
		if String(upgrade["id"]) == id:
			_check(game._upgrade_is_available(upgrade), "Unavailable upgrade: " + id)
			game._apply_upgrade(upgrade)
			game.upgrade_levels[id] = int(game.upgrade_levels.get(id, 0)) + 1
			return
	_check(false, "Missing upgrade: " + id)


func _run() -> void:
	seed(47)
	game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	center = game.get_viewport_rect().size * 0.5
	_reset()
	# Sweep a complete line in one frame: piercing survives kills and array shifts.
	_take("smg_pierce")
	var line: Array[int] = []
	for x in [80, 120, 160, 200]:
		line.append(_enemy(Vector2(x, 0), 5.0))
	game._emit_combat_trigger("correct_key")
	game._update_bullets(0.30)
	_check(game.enemies.size() == 1 and _hp(line[3]) == 5.0, "Piercing must hit exactly three enemies in travel order")
	_check(game.bullets.is_empty(), "Pierce hit budget must expire")
	_reset()
	_take("smg_pierce")
	var durable := _enemy(Vector2(80, 0))
	game._emit_combat_trigger("correct_key")
	game._update_bullets(0.08)
	var first_hp := _hp(durable)
	game._update_bullets(0.001)
	_check(is_equal_approx(_hp(durable), first_hp) and first_hp < 100, "Same bullet must not hit one enemy twice")
	_reset()
	_take("smg_multishot")
	_enemy(Vector2(80, 0))
	_enemy(Vector2(0, 80))
	game._emit_combat_trigger("correct_key")
	_check(game.bullets.size() == 2, "Split Feed must add a projectile")
	_check(game.bullets[0]["target_uid"] != game.bullets[1]["target_uid"], "Split Feed should divide targets")
	_reset()
	var dead_target := _enemy(Vector2(80, 0), 1)
	var live_target := _enemy(Vector2(160, 0))
	game._emit_combat_trigger("correct_key")
	game._kill_enemy(game._get_enemy_index_by_uid(dead_target), center + Vector2(80, 0))
	game._update_bullets(0.25)
	_check(_hp(live_target) < 100, "An in-flight shot should hit a surviving enemy after its target dies")
	_reset()
	_take("unlock_arc_coil")
	var chain_ids: Array[int] = []
	for x in [60, 120, 180, 240, 300, 500]:
		chain_ids.append(_enemy(Vector2(x, 0)))
	var priority := _enemy(Vector2(90, 0), 100, "jammer")
	game._emit_combat_trigger("word_complete")
	for i in range(4):
		_check(is_equal_approx(_hp(chain_ids[i]), 78.0), "Chain hit count/damage")
	_check(_hp(chain_ids[4]) == 100 and _hp(chain_ids[5]) == 100, "Chain must respect count")
	_check(_hp(priority) == 100, "Chain must respect priority immunity")
	_take("arc_chain")
	game._emit_combat_trigger("word_complete")
	_check(_hp(chain_ids[4]) == 78 and _hp(chain_ids[5]) == 100, "Chain upgrade and range limit")
	game._update_lightning_arcs(1.0)
	_check(game.lightning_arcs.is_empty(), "Lightning visuals must expire")
	_reset()
	_take("unlock_pistol")
	_take("pistol_explosion")
	var primary := _enemy(Vector2(80, 0))
	var neighbor := _enemy(Vector2(80, 30))
	var distant := _enemy(Vector2(80, 150))
	priority = _enemy(Vector2(80, -30), 100, "jammer")
	game._emit_combat_trigger("word_complete")
	game._update_bullets(0.08)
	game._process_pending_reactions()
	_check(is_equal_approx(_hp(primary), 75.25), "Pistol direct damage plus splash")
	_check(is_equal_approx(_hp(neighbor), 90.25), "Splash hits neighbors")
	_check(_hp(distant) == 100 and _hp(priority) == 100, "Splash range and priority immunity")
	# Blast splash can consume Shock and queue Overload once, without recursion.
	game.enemies[game._get_enemy_index_by_uid(neighbor)]["statuses"] = {"shock": {"remaining": 2.0}}
	game._emit_combat_trigger("word_complete")
	game._update_bullets(0.08)
	game._process_pending_reactions()
	_check(game.pending_reactions.size() == 1, "Splash must trigger elemental reaction")
	game._process_pending_reactions()
	_check(game.pending_reactions.is_empty(), "Reactions must terminate")
	_reset()
	var boss := _enemy(Vector2(100, 0), 1000, "overseer")
	game._apply_combat_hit(boss, 10000, [], [], Color.WHITE)
	var boss_index: int = game._get_enemy_index_by_uid(boss)
	_check(boss_index >= 0 and _hp(boss) == 660, "Huge hits must preserve boss phase gate")
	game._apply_combat_hit(boss, 10000, [], [], Color.WHITE)
	_check(_hp(boss) == 660, "Shielded boss must reject secondary damage")
	_reset()
	var victim := _enemy(Vector2(80, 0))
	var shield := _enemy(Vector2(120, 0), 100, "bulwark")
	game.enemies[game._get_enemy_index_by_uid(shield)]["priority_active"] = true
	game._apply_combat_hit(victim, 20, [], [], Color.WHITE)
	_check(is_equal_approx(_hp(victim), 89), "Shield protection applies to new attack paths")
	_reset()
	# Choices stay useful and typable as weapons and ranks are acquired.
	for step in range(45):
		var choices: Array = game._roll_upgrade_choices(3)
		_check(choices.size() == 3, "Expected three upgrade choices")
		var initials := {}
		var has_crowd := false
		var crowd_available := false
		for upgrade in game.upgrade_definitions:
			if game._upgrade_is_available(upgrade) and upgrade.get("category", "") == "crowd":
				crowd_available = true
		for choice in choices:
			var initial: String = String(choice["command"]).left(1)
			_check(not initials.has(initial), "Ambiguous upgrade command")
			initials[initial] = true
			has_crowd = has_crowd or choice.get("category", "") == "crowd"
		_check(not crowd_available or has_crowd, "Must offer available crowd-clearing path")
		var selected: Dictionary = choices[0]
		_take(String(selected["id"]))
		game.current_upgrade_choices.assign(choices)
		game._refresh_upgrade_cards()
	_reset()
	# Dense late-run integration: simultaneous multishot, piercing, splash,
	# lightning, elemental reactions, and bounded feedback against 200 bodies.
	for upgrade_id in ["unlock_pistol", "unlock_shotgun", "unlock_arc_coil",
		"smg_multishot", "smg_pierce", "pistol_pierce", "pistol_explosion",
		"arc_chain", "shotgun_pellet", "cryo_rounds", "charged_chamber", "incendiary",
		"smg_damage", "pistol_damage", "shotgun_damage", "arc_damage", "global_damage"]:
		_take(upgrade_id)
	for i in range(200):
		var angle := TAU * float(i) / 200.0
		_enemy(Vector2.RIGHT.rotated(angle) * (150.0 + float(i % 4) * 25.0), 44.0)
	for frame in range(1800):
		if frame % 9 == 0:
			game._emit_combat_trigger("correct_key")
		if frame % 45 == 0:
			game._emit_combat_trigger("word_complete")
		game._update_bullets(1.0 / 60.0)
		game._process_pending_reactions()
		game._update_lightning_arcs(1.0 / 60.0)
		game._update_particles(1.0 / 60.0)
		game._update_damage_numbers(1.0 / 60.0)
		game._update_reaction_waves(1.0 / 60.0)
		game._trim_visual_feedback()
	_check(game.enemies.is_empty(), "Crowd build should clear the stationary 200-enemy integration fixture")
	_check(game.pending_reactions.is_empty(), "Stress fixture should drain pending damage")
	_check(game.lightning_arcs.size() <= game.MAX_LIGHTNING_ARCS, "Lightning feedback cap")
	_check(game.damage_numbers.size() <= game.MAX_DAMAGE_NUMBERS, "Damage feedback cap")
	# A fresh run loses all weapon modifiers/unlocks and elemental attachments.
	game.combat.equip_loadout("starter")
	var fresh: Array = game.combat.build_attacks("correct_key")
	_check(fresh.size() == 1 and fresh[0]["projectile_count"] == 1 and fresh[0]["pierce"] == 0, "Run upgrades must reset")
	_check(not game.combat.is_weapon_active("arc_coil"), "Arc unlock must reset")
	print("Crowd combat checks: ", checks, "; failures: ", failures)
	game.free()
	quit(1 if failures > 0 else 0)
