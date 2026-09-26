extends Node2D

const CombatSystemScript = preload("res://scripts/combat/combat_system.gd")

const UPGRADES_PATH := "res://data/combat/upgrades.json"

const PLAYER_RADIUS := 14.0
const ENEMY_RADIUS := 10.0
const BULLET_RADIUS := 3.0
const SPAWN_RADIUS := 430.0
const DANGER_RADIUS := 42.0
const BASE_MAX_HP := 100.0

const TAPE_ANCHOR_X := 120.0
const TAPE_BUFFER_WORDS := 12
const TAPE_PRUNE_AT := 10
const TAPE_PRUNE_COUNT := 6

var rng := RandomNumberGenerator.new()
var combat = CombatSystemScript.new()

# Typing stream ---------------------------------------------------------------
var word_pool: Array[String] = []
var word_queue: Array[String] = []
var active_word_index := 0
var typed_index := 0

var typing_tape_target_x := TAPE_ANCHOR_X
var typing_tape_visual_x := TAPE_ANCHOR_X
var typing_tape_initialized := false

var caret_target_x := TAPE_ANCHOR_X
var caret_visual_x := TAPE_ANCHOR_X
var caret_initialized := false
var caret_idle_time := 0.0

# World -----------------------------------------------------------------------
var enemies: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var damage_numbers: Array[Dictionary] = []
var pending_reactions: Array[Dictionary] = []
var reaction_waves: Array[Dictionary] = []

var spawn_timer := 0.0
var spawn_interval := 0.95
var elapsed := 0.0
var error_flash := 0.0
var player_recoil := 0.0
var shake_time := 0.0
var shake_strength := 0.0

# Run state -------------------------------------------------------------------
var kills := 0
var words_completed := 0
var streak := 0
var best_streak := 0
var max_hp := BASE_MAX_HP
var hp := BASE_MAX_HP
var run_over := false

var correct_keys := 0
var incorrect_keys := 0
var typed_characters := 0

# XP / level ups --------------------------------------------------------------
var level := 1
var xp_total := 0
var xp_in_level := 0
var xp_required := 5
var pending_level_ups := 0
var level_up_open := false
var upgrade_definitions: Array = []
var upgrade_levels: Dictionary = {}
var current_upgrade_choices: Array[Dictionary] = []

var reaction_counts := {
	"shatter": 0,
	"overload": 0
}

# UI --------------------------------------------------------------------------
@onready var typing_viewport: Control = $HUD/TypingViewport
@onready var typing_panel: RichTextLabel = $HUD/TypingViewport/TypingPanel
@onready var typing_caret: ColorRect = $HUD/TypingViewport/TypingCaret
@onready var stats_label: Label = $HUD/Stats
@onready var xp_bar_background: ColorRect = $HUD/XPBarBackground
@onready var xp_bar_fill: ColorRect = $HUD/XPBarFill
@onready var level_label: Label = $HUD/LevelLabel

@onready var upgrade_overlay: ColorRect = $HUD/UpgradeOverlay
@onready var upgrade_title: Label = $HUD/UpgradeOverlay/Title
@onready var upgrade_subtitle: Label = $HUD/UpgradeOverlay/Subtitle
@onready var upgrade_card_labels: Array[RichTextLabel] = [
	$HUD/UpgradeOverlay/Card1/Text,
	$HUD/UpgradeOverlay/Card2/Text,
	$HUD/UpgradeOverlay/Card3/Text
]

@onready var death_overlay: ColorRect = $HUD/DeathOverlay
@onready var death_summary: Label = $HUD/DeathOverlay/Summary


func _ready() -> void:
	rng.randomize()
	combat.load_definitions("starter")
	_load_words()
	_load_upgrades()

	for i in range(TAPE_BUFFER_WORDS):
		_append_random_word()

	_update_typing_ui()
	_update_tape_target(true)
	_update_xp_ui()
	_update_stats()
	queue_redraw()


func _process(delta: float) -> void:
	# UI motion is allowed to settle even while gameplay is paused.
	_update_typing_tape(delta)
	_update_typing_caret(delta)

	if run_over or level_up_open:
		queue_redraw()
		return

	elapsed += delta
	error_flash = maxf(error_flash - delta, 0.0)
	player_recoil = maxf(player_recoil - delta, 0.0)
	shake_time = maxf(shake_time - delta, 0.0)

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_enemy()
		spawn_timer = spawn_interval
		spawn_interval = maxf(0.28, 0.95 - elapsed * 0.004)

	_update_enemies(delta)
	_update_bullets(delta)
	_process_pending_reactions()
	_update_reaction_waves(delta)
	_update_particles(delta)
	_update_damage_numbers(delta)
	_update_stats()
	_update_canvas_shake()
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return

	if run_over:
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()
		return

	if level_up_open:
		match event.keycode:
			KEY_1:
				_choose_upgrade(0)
			KEY_2:
				_choose_upgrade(1)
			KEY_3:
				_choose_upgrade(2)
		return

	if event.unicode == 0:
		return

	var typed := char(event.unicode).to_lower()
	if typed.length() != 1 or typed < "a" or typed > "z":
		return

	typed_characters += 1
	caret_idle_time = 0.0

	var current := _get_current_word()
	if current.is_empty():
		return

	var expected := current.substr(typed_index, 1)

	if typed == expected:
		correct_keys += 1
		typed_index += 1
		streak += 1
		best_streak = maxi(best_streak, streak)
		player_recoil = 0.07

		_emit_combat_trigger("correct_key", {
			"character": typed,
			"word": current,
			"word_length": current.length(),
			"streak": streak
		})

		if typed_index >= current.length():
			_complete_word(current)
	else:
		incorrect_keys += 1
		streak = 0
		error_flash = 0.16

	_update_typing_ui()


# Typing stream ---------------------------------------------------------------

func _load_words() -> void:
	var raw := FileAccess.get_file_as_string("res://data/words/common.txt")
	for line in raw.split("\n", false):
		var cleaned := line.strip_edges().to_lower()
		if cleaned.length() > 0:
			word_pool.append(cleaned)

	if word_pool.is_empty():
		word_pool = ["type", "fire", "word", "game", "light", "world"]


func _append_random_word() -> void:
	word_queue.append(word_pool[rng.randi_range(0, word_pool.size() - 1)])


func _ensure_word_buffer() -> void:
	while word_queue.size() - active_word_index < TAPE_BUFFER_WORDS:
		_append_random_word()


func _get_current_word() -> String:
	if active_word_index < 0 or active_word_index >= word_queue.size():
		return ""
	return word_queue[active_word_index]


func _complete_word(completed_word: String) -> void:
	words_completed += 1
	typed_index = 0
	active_word_index += 1
	_ensure_word_buffer()
	_prune_typing_tape_if_needed()
	_update_tape_target()

	_emit_combat_trigger("word_complete", {
		"word": completed_word,
		"word_length": completed_word.length(),
		"streak": streak
	})


func _update_typing_ui() -> void:
	if word_queue.is_empty():
		return

	var pieces: Array[String] = []

	for i in range(word_queue.size()):
		if i < active_word_index:
			pieces.append("[color=#4a5260]" + word_queue[i] + "[/color]")
		elif i == active_word_index:
			pieces.append("[color=#ffffff]" + word_queue[i] + "[/color]")
		else:
			pieces.append("[color=#697180]" + word_queue[i] + "[/color]")

	typing_panel.text = " ".join(pieces)


func _measure_text_width(value: String) -> float:
	if value.is_empty():
		return 0.0

	var font := typing_panel.get_theme_font("normal_font")
	var font_size := typing_panel.get_theme_font_size("normal_font_size")
	return font.get_string_size(
		value,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size
	).x


func _get_prefix_before_active() -> String:
	if active_word_index <= 0:
		return ""

	var previous: Array[String] = []
	for i in range(active_word_index):
		previous.append(word_queue[i])

	return " ".join(previous) + " "


func _update_tape_target(snap: bool = false) -> void:
	var prefix_width := _measure_text_width(_get_prefix_before_active())
	typing_tape_target_x = TAPE_ANCHOR_X - prefix_width

	if snap or not typing_tape_initialized:
		typing_tape_visual_x = typing_tape_target_x
		typing_tape_initialized = true
		typing_panel.position.x = typing_tape_visual_x


func _update_typing_tape(delta: float) -> void:
	if not typing_tape_initialized:
		return

	# Smooth "tape" movement: the next word physically glides into the same
	# reading position instead of the whole line being replaced/recentered.
	var follow := 1.0 - exp(-11.5 * delta)
	typing_tape_visual_x = lerpf(
		typing_tape_visual_x,
		typing_tape_target_x,
		follow
	)
	typing_panel.position.x = typing_tape_visual_x


func _prune_typing_tape_if_needed() -> void:
	if active_word_index <= TAPE_PRUNE_AT:
		return

	var remove_count := mini(TAPE_PRUNE_COUNT, active_word_index)
	var removed_words: Array[String] = []

	for i in range(remove_count):
		removed_words.append(word_queue[i])

	var removed_width := _measure_text_width(" ".join(removed_words) + " ")

	for i in range(remove_count):
		word_queue.pop_front()

	active_word_index -= remove_count

	# Removing offscreen text changes the local coordinate system. Offset the
	# tape by the same amount so nothing visible jumps.
	typing_tape_visual_x += removed_width
	typing_tape_target_x += removed_width
	typing_panel.position.x = typing_tape_visual_x


func _update_typing_caret(delta: float) -> void:
	if word_queue.is_empty() or active_word_index >= word_queue.size():
		return

	caret_idle_time += delta

	var prefix_width := _measure_text_width(_get_prefix_before_active())
	var current := _get_current_word()
	var completed := current.substr(0, typed_index)
	var completed_width := _measure_text_width(completed)

	caret_target_x = typing_tape_visual_x + prefix_width + completed_width - typing_caret.size.x * 0.5

	if not caret_initialized:
		caret_visual_x = caret_target_x
		caret_initialized = true

	var follow := 1.0 - exp(-38.0 * delta)
	caret_visual_x = lerpf(caret_visual_x, caret_target_x, follow)
	typing_caret.position.x = caret_visual_x

	if error_flash > 0.0:
		typing_caret.color = Color(1.0, 0.36, 0.42, 1.0)
		typing_caret.modulate.a = 1.0
	elif caret_idle_time > 0.65:
		typing_caret.color = Color(0.56, 0.94, 0.76, 1.0)
		var blink_phase := (sin((caret_idle_time - 0.65) * TAU * 1.15) + 1.0) * 0.5
		typing_caret.modulate.a = lerpf(0.22, 1.0, blink_phase)
	else:
		typing_caret.color = Color(0.56, 0.94, 0.76, 1.0)
		typing_caret.modulate.a = 1.0


# Combat ----------------------------------------------------------------------

func _emit_combat_trigger(trigger_id: String, context: Dictionary = {}) -> void:
	for attack in combat.build_attacks(trigger_id, context):
		_execute_attack(attack)


func _execute_attack(attack: Dictionary) -> void:
	var count := maxi(1, int(attack.get("projectile_count", 1)))
	var total_spread := float(attack.get("spread_radians", 0.0))
	var damage := float(attack.get("damage", 1.0))
	var speed := float(attack.get("projectile_speed", 720.0))
	var tags: Array = attack.get("tags", [])
	var effects: Array = attack.get("effects", [])
	var weapon_id := String(attack.get("weapon_id", "unknown"))
	var projectile_color := Color.from_string(
		String(attack.get("color", "#ffe680")),
		Color(1.0, 0.9, 0.5)
	)

	for i in range(count):
		var angle := 0.0
		if count > 1:
			var ratio := float(i) / float(count - 1)
			angle = lerpf(-total_spread * 0.5, total_spread * 0.5, ratio)

		_fire_at_nearest_enemy(
			damage,
			angle,
			speed,
			tags,
			effects,
			weapon_id,
			projectile_color
		)


func _spawn_enemy() -> void:
	var center := get_viewport_rect().size * 0.5
	var angle := rng.randf_range(0.0, TAU)
	var position := center + Vector2.RIGHT.rotated(angle) * SPAWN_RADIUS
	var speed := rng.randf_range(38.0, 62.0) + minf(elapsed * 0.20, 26.0)
	var hp_value := 44.0 + minf(elapsed * 0.18, 32.0)

	enemies.append({
		"position": position,
		"speed": speed,
		"hp": hp_value,
		"max_hp": hp_value,
		"flash": 0.0,
		"knockback": Vector2.ZERO,
		"statuses": {}
	})


func _update_enemies(delta: float) -> void:
	var center := get_viewport_rect().size * 0.5

	for i in range(enemies.size() - 1, -1, -1):
		var enemy := enemies[i]
		var pos: Vector2 = enemy["position"]
		var knockback: Vector2 = enemy["knockback"]

		var status_damage := _update_enemy_statuses(enemy, delta)
		if status_damage > 0.0:
			enemy["hp"] = float(enemy["hp"]) - status_damage
			_spawn_damage_number(
				pos,
				int(round(status_damage)),
				Color(1.0, 0.48, 0.30)
			)

		if float(enemy["hp"]) <= 0.0:
			_kill_enemy(i, pos)
			continue

		var to_player := center - pos
		var distance := to_player.length()
		var speed_multiplier := _get_enemy_speed_multiplier(enemy)

		enemy["flash"] = maxf(float(enemy["flash"]) - delta, 0.0)
		pos += knockback * delta
		enemy["knockback"] = knockback.move_toward(
			Vector2.ZERO,
			650.0 * delta
		)

		if distance > DANGER_RADIUS:
			pos += to_player.normalized() * float(enemy["speed"]) * speed_multiplier * delta
			enemy["position"] = pos
			enemies[i] = enemy
		else:
			hp = maxf(0.0, hp - 14.0)
			_spawn_impact_particles(
				pos,
				Color(1.0, 0.28, 0.34),
				7
			)
			enemies.remove_at(i)

			if hp <= 0.0:
				_end_run()
				return


func _update_enemy_statuses(enemy: Dictionary, delta: float) -> float:
	var statuses: Dictionary = enemy.get("statuses", {})
	var total_tick_damage := 0.0
	var expired: Array[String] = []

	for effect_key in statuses.keys():
		var effect_id := String(effect_key)
		var state: Dictionary = statuses[effect_id]
		var definition := combat.get_effect_definition(effect_id)

		state["remaining"] = float(state.get("remaining", 0.0)) - delta

		var tick_interval := float(definition.get("tick_interval", 0.0))
		if tick_interval > 0.0:
			state["tick_timer"] = float(
				state.get("tick_timer", tick_interval)
			) - delta

			while float(state["tick_timer"]) <= 0.0 and float(state["remaining"]) > 0.0:
				var stacks := int(state.get("stacks", 1))
				total_tick_damage += float(
					definition.get("tick_damage", 0.0)
				) * stacks
				state["tick_timer"] = float(state["tick_timer"]) + tick_interval

		if float(state["remaining"]) <= 0.0:
			expired.append(effect_id)
		else:
			statuses[effect_id] = state

	for effect_id in expired:
		statuses.erase(effect_id)

	enemy["statuses"] = statuses
	return total_tick_damage


func _get_enemy_speed_multiplier(enemy: Dictionary) -> float:
	var multiplier := 1.0
	var statuses: Dictionary = enemy.get("statuses", {})

	for effect_key in statuses.keys():
		var definition := combat.get_effect_definition(String(effect_key))
		multiplier *= float(
			definition.get("speed_multiplier", 1.0)
		)

	return multiplier


func _fire_at_nearest_enemy(
	damage: float,
	spread: float,
	speed: float,
	tags: Array,
	effects: Array,
	weapon_id: String,
	projectile_color: Color
) -> void:
	if enemies.is_empty():
		return

	var center := get_viewport_rect().size * 0.5
	var nearest_index := 0
	var nearest_distance_sq := INF

	for i in range(enemies.size()):
		var enemy_pos: Vector2 = enemies[i]["position"]
		var distance_sq := center.distance_squared_to(enemy_pos)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest_index = i

	var target: Vector2 = enemies[nearest_index]["position"]
	var direction := (target - center).normalized().rotated(spread)

	bullets.append({
		"position": center + direction * 16.0,
		"velocity": direction * speed,
		"damage": damage,
		"life": 1.1,
		"tags": tags.duplicate(),
		"effects": effects.duplicate(true),
		"weapon_id": weapon_id,
		"color": projectile_color
	})


func _update_bullets(delta: float) -> void:
	for bullet_index in range(bullets.size() - 1, -1, -1):
		var bullet := bullets[bullet_index]
		bullet["position"] = Vector2(bullet["position"]) + Vector2(bullet["velocity"]) * delta
		bullet["life"] = float(bullet["life"]) - delta
		var hit := false

		for enemy_index in range(enemies.size() - 1, -1, -1):
			var enemy_pos: Vector2 = enemies[enemy_index]["position"]

			if Vector2(bullet["position"]).distance_squared_to(enemy_pos) <= pow(
				ENEMY_RADIUS + BULLET_RADIUS,
				2
			):
				var enemy := enemies[enemy_index]
				var damage := float(bullet["damage"])
				enemy["hp"] = float(enemy["hp"]) - damage
				enemy["flash"] = 0.075

				var push_direction := (
					enemy_pos - get_viewport_rect().size * 0.5
				).normalized()
				enemy["knockback"] = Vector2(
					enemy["knockback"]
				) + push_direction * 92.0

				_spawn_impact_particles(
					enemy_pos,
					Color(1.0, 0.82, 0.42),
					3
				)
				_spawn_damage_number(
					enemy_pos,
					int(round(damage))
				)
				_apply_attack_effects(
					enemy,
					bullet.get("effects", [])
				)
				_queue_matching_reactions(
					enemy,
					bullet.get("tags", []),
					enemy_pos
				)

				if float(enemy["hp"]) <= 0.0:
					_kill_enemy(enemy_index, enemy_pos)
				else:
					enemies[enemy_index] = enemy

				hit = true
				break

		if hit or float(bullet["life"]) <= 0.0:
			bullets.remove_at(bullet_index)
		else:
			bullets[bullet_index] = bullet


func _apply_attack_effects(enemy: Dictionary, bindings: Array) -> void:
	if bindings.is_empty():
		return

	var statuses: Dictionary = enemy.get("statuses", {})

	for raw_binding in bindings:
		var binding: Dictionary = raw_binding
		var chance := float(binding.get("chance", 1.0))

		if rng.randf() > chance:
			continue

		var effect_id := String(binding.get("effect_id", ""))
		var definition := combat.get_effect_definition(effect_id)

		if effect_id.is_empty() or definition.is_empty():
			continue

		var duration := float(definition.get("duration", 1.0))
		var max_stacks := int(definition.get("max_stacks", 1))
		var existing: Dictionary = statuses.get(effect_id, {})
		var stacks := mini(
			int(existing.get("stacks", 0)) + 1,
			max_stacks
		)

		statuses[effect_id] = {
			"remaining": duration,
			"stacks": stacks,
			"tick_timer": float(
				definition.get("tick_interval", 0.0)
			)
		}

	enemy["statuses"] = statuses


func _queue_matching_reactions(
	enemy: Dictionary,
	incoming_tags: Array,
	position: Vector2
) -> void:
	var statuses: Dictionary = enemy.get("statuses", {})
	var matches := combat.resolve_reactions(
		statuses,
		incoming_tags
	)

	for reaction in matches:
		combat.consume_reaction_effects(
			statuses,
			reaction
		)
		pending_reactions.append({
			"reaction": reaction,
			"position": position
		})

	enemy["statuses"] = statuses


func _process_pending_reactions() -> void:
	if pending_reactions.is_empty():
		return

	var queued := pending_reactions.duplicate(true)
	pending_reactions.clear()

	for item in queued:
		var reaction: Dictionary = item["reaction"]
		var center: Vector2 = item["position"]
		var radius := float(
			reaction.get("area_radius", 0.0)
		)
		var damage := float(
			reaction.get("area_damage", 0.0)
		)
		var reaction_color := Color.from_string(
			String(reaction.get("color", "#ffffff")),
			Color.WHITE
		)

		_spawn_impact_particles(
			center,
			reaction_color,
			20
		)
		_spawn_combat_text(
			center + Vector2(0.0, -22.0),
			String(reaction.get("name", "REACTION")),
			reaction_color
		)
		_spawn_reaction_wave(
			center,
			radius,
			reaction_color
		)

		var reaction_id := String(
			reaction.get("id", "")
		)
		if reaction_counts.has(reaction_id):
			reaction_counts[reaction_id] = int(
				reaction_counts[reaction_id]
			) + 1

		shake_time = maxf(shake_time, 0.11)
		shake_strength = maxf(shake_strength, 3.0)

		for i in range(enemies.size() - 1, -1, -1):
			var enemy_pos: Vector2 = enemies[i]["position"]

			if center.distance_squared_to(enemy_pos) > radius * radius:
				continue

			var enemy := enemies[i]
			enemy["hp"] = float(enemy["hp"]) - damage
			enemy["flash"] = 0.10

			var push := (enemy_pos - center).normalized()
			enemy["knockback"] = Vector2(
				enemy["knockback"]
			) + push * 145.0

			_spawn_damage_number(
				enemy_pos,
				int(round(damage)),
				reaction_color
			)

			if float(enemy["hp"]) <= 0.0:
				_kill_enemy(i, enemy_pos)
			else:
				enemies[i] = enemy


func _spawn_reaction_wave(
	center: Vector2,
	radius: float,
	color: Color
) -> void:
	reaction_waves.append({
		"center": center,
		"radius": radius,
		"life": 0.34,
		"max_life": 0.34,
		"color": color
	})


func _update_reaction_waves(delta: float) -> void:
	for i in range(reaction_waves.size() - 1, -1, -1):
		var wave := reaction_waves[i]
		wave["life"] = float(wave["life"]) - delta

		if float(wave["life"]) <= 0.0:
			reaction_waves.remove_at(i)
		else:
			reaction_waves[i] = wave


func _kill_enemy(index: int, position: Vector2) -> void:
	if index < 0 or index >= enemies.size():
		return

	enemies.remove_at(index)
	kills += 1
	_grant_xp(1)
	_spawn_death_particles(position)
	_spawn_xp_particles(position)


# XP / progression ------------------------------------------------------------

func _grant_xp(amount: int) -> void:
	xp_total += amount
	xp_in_level += amount

	while xp_in_level >= xp_required:
		xp_in_level -= xp_required
		level += 1
		pending_level_ups += 1
		xp_required = _xp_required_for_level(level)

	_update_xp_ui()

	if pending_level_ups > 0 and not level_up_open:
		call_deferred("_open_level_up")


func _xp_required_for_level(current_level: int) -> int:
	return 5 + (current_level - 1) * 3


func _update_xp_ui() -> void:
	if not is_instance_valid(xp_bar_fill):
		return

	var ratio := 0.0
	if xp_required > 0:
		ratio = clampf(
			float(xp_in_level) / float(xp_required),
			0.0,
			1.0
		)

	xp_bar_fill.size.x = xp_bar_background.size.x * ratio
	level_label.text = "LV %d" % level


func _load_upgrades() -> void:
	if not FileAccess.file_exists(UPGRADES_PATH):
		push_error("Missing upgrades file: %s" % UPGRADES_PATH)
		return

	var parsed = JSON.parse_string(
		FileAccess.get_file_as_string(UPGRADES_PATH)
	)

	if parsed == null or not (parsed is Dictionary):
		push_error("Invalid upgrades file.")
		return

	upgrade_definitions = parsed.get("upgrades", [])


func _open_level_up() -> void:
	if run_over or pending_level_ups <= 0:
		return

	pending_level_ups -= 1
	current_upgrade_choices = _roll_upgrade_choices(3)

	if current_upgrade_choices.is_empty():
		return

	level_up_open = true
	upgrade_overlay.visible = true
	upgrade_title.text = "LEVEL %d" % level
	upgrade_subtitle.text = "Choose an upgrade — press 1, 2, or 3"

	for i in range(upgrade_card_labels.size()):
		var label := upgrade_card_labels[i]

		if i < current_upgrade_choices.size():
			var upgrade: Dictionary = current_upgrade_choices[i]
			var picks := int(
				upgrade_levels.get(
					String(upgrade.get("id", "")),
					0
				)
			)
			label.text = "[center][font_size=22][b]%d  %s[/b][/font_size]\n\n%s\n\n[color=#7f8998]Taken: %d[/color][/center]" % [
				i + 1,
				String(upgrade.get("name", "Upgrade")),
				String(upgrade.get("description", "")),
				picks
			]
			label.get_parent().visible = true
		else:
			label.get_parent().visible = false


func _roll_upgrade_choices(count: int) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []

	for raw_upgrade in upgrade_definitions:
		var upgrade: Dictionary = raw_upgrade
		if _upgrade_is_available(upgrade):
			candidates.append(upgrade.duplicate(true))

	candidates.shuffle()

	var result: Array[Dictionary] = []
	for i in range(mini(count, candidates.size())):
		result.append(candidates[i])

	return result


func _upgrade_is_available(upgrade: Dictionary) -> bool:
	var upgrade_id := String(upgrade.get("id", ""))
	var picks := int(upgrade_levels.get(upgrade_id, 0))
	var max_picks := int(upgrade.get("max_picks", 1))

	if picks >= max_picks:
		return false

	var required_weapon := String(
		upgrade.get("requires_weapon", "")
	)
	if not required_weapon.is_empty() and not combat.is_weapon_active(required_weapon):
		return false

	if String(upgrade.get("action", "")) == "unlock_weapon":
		var weapon_id := String(
			upgrade.get("weapon_id", "")
		)
		if combat.is_weapon_active(weapon_id):
			return false

	if bool(upgrade.get("requires_missing_hp", false)) and hp >= max_hp:
		return false

	if String(upgrade.get("action", "")) == "reaction_damage_mult":
		var has_blast := combat.is_weapon_active("shotgun")
		var has_status := (
			combat.get_effect_binding_chance("smg", "freeze") > 0.0
			or combat.get_effect_binding_chance("pistol", "shock") > 0.0
		)
		if not has_blast or not has_status:
			return false

	return true


func _choose_upgrade(index: int) -> void:
	if index < 0 or index >= current_upgrade_choices.size():
		return

	var upgrade := current_upgrade_choices[index]
	_apply_upgrade(upgrade)

	var upgrade_id := String(
		upgrade.get("id", "")
	)
	upgrade_levels[upgrade_id] = int(
		upgrade_levels.get(upgrade_id, 0)
	) + 1

	level_up_open = false
	upgrade_overlay.visible = false
	current_upgrade_choices.clear()

	if pending_level_ups > 0:
		call_deferred("_open_level_up")


func _apply_upgrade(upgrade: Dictionary) -> void:
	var action := String(
		upgrade.get("action", "")
	)
	var weapon_id := String(
		upgrade.get("weapon_id", "")
	)

	match action:
		"unlock_weapon":
			combat.unlock_weapon(weapon_id)

		"weapon_damage_mult":
			combat.multiply_weapon_stat(
				weapon_id,
				"damage",
				float(upgrade.get("factor", 1.0))
			)

		"weapon_projectile_add":
			combat.add_weapon_stat(
				weapon_id,
				"projectile_count",
				float(upgrade.get("amount", 1))
			)

		"weapon_spread_mult":
			combat.multiply_weapon_stat(
				weapon_id,
				"spread_radians",
				float(upgrade.get("factor", 1.0))
			)

		"effect_chance":
			combat.add_or_increase_effect_binding(
				weapon_id,
				String(upgrade.get("effect_id", "")),
				float(upgrade.get("chance_delta", 0.0))
			)

		"reaction_damage_mult":
			combat.multiply_reaction_damage(
				float(upgrade.get("factor", 1.0))
			)

		"global_damage_mult":
			combat.multiply_global_damage(
				float(upgrade.get("factor", 1.0))
			)

		"max_hp":
			var amount := float(
				upgrade.get("amount", 0.0)
			)
			max_hp += amount
			hp = minf(
				max_hp,
				hp + float(upgrade.get("heal", amount))
			)

		"heal":
			hp = minf(
				max_hp,
				hp + float(upgrade.get("amount", 0.0))
			)

	_update_stats()


func _end_run() -> void:
	if run_over:
		return

	run_over = true
	hp = 0.0
	death_overlay.visible = true
	death_summary.text = "LEVEL %d   KILLS %d   WORDS %d\nBEST STREAK %d   WPM %d\n\nPress R to restart" % [
		level,
		kills,
		words_completed,
		best_streak,
		_get_current_wpm()
	]
	_update_stats()


# Particles / feedback --------------------------------------------------------

func _spawn_impact_particles(
	position: Vector2,
	color: Color,
	amount: int
) -> void:
	for i in range(amount):
		var angle := rng.randf_range(0.0, TAU)
		particles.append({
			"position": position,
			"velocity": Vector2.RIGHT.rotated(angle) * rng.randf_range(35.0, 105.0),
			"life": rng.randf_range(0.12, 0.24),
			"max_life": 0.24,
			"color": color,
			"size": rng.randf_range(1.5, 3.0),
			"kind": "impact"
		})


func _spawn_death_particles(position: Vector2) -> void:
	_spawn_impact_particles(
		position,
		Color(1.0, 0.30, 0.38),
		9
	)


func _spawn_xp_particles(position: Vector2) -> void:
	var screen_width := get_viewport_rect().size.x
	var target_x := clampf(
		position.x,
		24.0,
		screen_width - 24.0
	)

	for i in range(3):
		var angle := rng.randf_range(0.0, TAU)
		particles.append({
			"position": position + Vector2(
				rng.randf_range(-5.0, 5.0),
				rng.randf_range(-5.0, 5.0)
			),
			"velocity": Vector2.RIGHT.rotated(angle) * rng.randf_range(35.0, 90.0),
			"target": Vector2(target_x, 5.0),
			"homing_delay": 0.10 + i * 0.06,
			"life": 1.45,
			"max_life": 1.45,
			"color": Color(0.42, 0.95, 0.72),
			"size": 3.4,
			"kind": "xp"
		})


func _update_particles(delta: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var particle := particles[i]
		particle["life"] = float(particle["life"]) - delta

		if particle["kind"] == "xp":
			var delay := float(
				particle.get("homing_delay", 0.0)
			) - delta
			particle["homing_delay"] = delay

			if delay <= 0.0:
				var pos: Vector2 = particle["position"]
				var target: Vector2 = particle["target"]
				var to_target := target - pos
				var desired := to_target.normalized() * 780.0
				var follow := 1.0 - exp(-5.5 * delta)
				particle["velocity"] = Vector2(
					particle["velocity"]
				).lerp(desired, follow)

				if to_target.length() < 14.0:
					_spawn_impact_particles(
						target,
						Color(0.42, 0.95, 0.72),
						4
					)
					particles.remove_at(i)
					continue
		else:
			particle["velocity"] = Vector2(
				particle["velocity"]
			) * pow(0.08, delta)

		particle["position"] = Vector2(
			particle["position"]
		) + Vector2(
			particle["velocity"]
		) * delta

		if float(particle["life"]) <= 0.0:
			particles.remove_at(i)
		else:
			particles[i] = particle


func _spawn_damage_number(
	position: Vector2,
	amount: int,
	color: Color = Color(1.0, 0.91, 0.62)
) -> void:
	damage_numbers.append({
		"position": position + Vector2(0.0, -14.0),
		"text": str(amount),
		"life": 0.42,
		"max_life": 0.42,
		"color": color,
		"font_size": 13
	})


func _spawn_combat_text(
	position: Vector2,
	value: String,
	color: Color
) -> void:
	damage_numbers.append({
		"position": position,
		"text": value,
		"life": 0.62,
		"max_life": 0.62,
		"color": color,
		"font_size": 15
	})


func _update_damage_numbers(delta: float) -> void:
	for i in range(damage_numbers.size() - 1, -1, -1):
		var number := damage_numbers[i]
		number["life"] = float(
			number["life"]
		) - delta
		number["position"] = Vector2(
			number["position"]
		) + Vector2(0.0, -24.0) * delta

		if float(number["life"]) <= 0.0:
			damage_numbers.remove_at(i)
		else:
			damage_numbers[i] = number


# HUD / drawing ---------------------------------------------------------------

func _get_current_wpm() -> int:
	var minutes := maxf(
		elapsed / 60.0,
		0.0167
	)
	return int(
		round(
			(correct_keys / 5.0) / minutes
		)
	)


func _update_stats() -> void:
	var total_attempts := correct_keys + incorrect_keys
	var accuracy := 100.0

	if total_attempts > 0:
		accuracy = (
			float(correct_keys)
			/ float(total_attempts)
		) * 100.0

	stats_label.text = "HP %d/%d   KILLS %d   WPM %d   ACC %.1f%%   STREAK %d" % [
		int(hp),
		int(max_hp),
		kills,
		_get_current_wpm(),
		accuracy,
		streak
	]


func _update_canvas_shake() -> void:
	if shake_time > 0.0:
		position = Vector2(
			rng.randf_range(
				-shake_strength,
				shake_strength
			),
			rng.randf_range(
				-shake_strength,
				shake_strength
			)
		)
	else:
		position = Vector2.ZERO


func _draw() -> void:
	var center := get_viewport_rect().size * 0.5

	var player_size := PLAYER_RADIUS + (
		2.0 if player_recoil > 0.0 else 0.0
	)
	draw_circle(
		center,
		player_size,
		Color(0.40, 0.90, 0.72)
	)
	draw_circle(
		center,
		5.0,
		Color(0.93, 1.0, 0.97)
	)
	draw_arc(
		center,
		DANGER_RADIUS,
		0.0,
		TAU,
		64,
		Color(0.35, 0.39, 0.48, 0.35),
		1.0
	)

	for enemy in enemies:
		var pos: Vector2 = enemy["position"]
		var enemy_color := _get_enemy_draw_color(enemy)

		if float(enemy["flash"]) > 0.0:
			enemy_color = enemy_color.lerp(
				Color.WHITE,
				0.72
			)

		draw_circle(
			pos,
			ENEMY_RADIUS,
			enemy_color
		)

		var statuses: Dictionary = enemy.get(
			"statuses",
			{}
		)
		if statuses.has("freeze"):
			draw_arc(
				pos,
				ENEMY_RADIUS + 3.0,
				0.0,
				TAU,
				24,
				Color(0.40, 0.81, 1.0, 0.95),
				2.0
			)
		if statuses.has("shock"):
			draw_arc(
				pos,
				ENEMY_RADIUS + 6.0,
				0.0,
				TAU,
				24,
				Color(1.0, 0.85, 0.30, 0.95),
				2.0
			)

	for bullet in bullets:
		var pos: Vector2 = bullet["position"]
		var direction := Vector2(
			bullet["velocity"]
		).normalized()
		var bullet_color: Color = bullet.get(
			"color",
			Color(1.0, 0.90, 0.50)
		)

		draw_line(
			pos - direction * 7.0,
			pos,
			bullet_color,
			3.0
		)
		draw_circle(
			pos,
			BULLET_RADIUS,
			bullet_color.lightened(0.18)
		)

	for wave in reaction_waves:
		var max_life_value := float(
			wave["max_life"]
		)
		var life_ratio := clampf(
			float(wave["life"])
			/ max_life_value,
			0.0,
			1.0
		)
		var progress := 1.0 - life_ratio
		var wave_color: Color = wave["color"]
		wave_color.a = life_ratio

		var current_radius := lerpf(
			8.0,
			float(wave["radius"]),
			progress
		)
		draw_arc(
			Vector2(wave["center"]),
			current_radius,
			0.0,
			TAU,
			48,
			wave_color,
			3.0
		)

	for particle in particles:
		var life_ratio := clampf(
			float(particle["life"])
			/ float(particle["max_life"]),
			0.0,
			1.0
		)
		var color: Color = particle["color"]

		# XP remains bright for most of its trip so the eye can track it from
		# the kill location all the way to the top progression bar.
		if particle["kind"] == "xp":
			color.a = maxf(0.75, life_ratio)
		else:
			color.a = life_ratio

		draw_circle(
			Vector2(particle["position"]),
			float(particle["size"]),
			color
		)

	var default_font := ThemeDB.fallback_font

	for number in damage_numbers:
		var max_life_value := float(
			number.get("max_life", 0.42)
		)
		var color: Color = number.get(
			"color",
			Color(1.0, 0.91, 0.62)
		)
		color.a = clampf(
			float(number["life"])
			/ max_life_value,
			0.0,
			1.0
		)

		draw_string(
			default_font,
			Vector2(number["position"]),
			String(number["text"]),
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			int(number.get("font_size", 13)),
			color
		)


func _get_enemy_draw_color(enemy: Dictionary) -> Color:
	var statuses: Dictionary = enemy.get(
		"statuses",
		{}
	)

	if statuses.has("shock"):
		return Color(1.0, 0.85, 0.30)
	if statuses.has("freeze"):
		return Color(0.40, 0.81, 1.0)
	if statuses.has("burn"):
		return Color(1.0, 0.45, 0.28)

	return Color(0.95, 0.33, 0.38)
