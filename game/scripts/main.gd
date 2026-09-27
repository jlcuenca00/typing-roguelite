extends Node2D

const CombatSystemScript = preload("res://scripts/combat/combat_system.gd")

const UPGRADES_PATH := "res://data/combat/upgrades.json"
const ENEMIES_PATH := "res://data/combat/enemies.json"

const PLAYER_RADIUS := 14.0
const ENEMY_RADIUS := 10.0
const BULLET_RADIUS := 3.0
const DANGER_RADIUS := 42.0
const BASE_MAX_HP := 100.0
const SPAWN_MARGIN_MIN := 18.0
const SPAWN_MARGIN_MAX := 42.0

const WORD_BUFFER := 24
const TYPING_LINE_WIDTH := 614.0
const TYPING_LINE_HEIGHT := 36.0
const TYPING_LEFT_X := 48.0

const TOTAL_WAVES := 10
# Each wave gets a fixed threat/XP budget. Enemy count is derived from which
# archetypes the seeded wave plan spends that budget on. Player damage never
# changes the budget or spawns extra enemies.
const WAVE_THREAT_BUDGETS := [
	8,
	12,
	18,
	28,
	42,
	68,
	100,
	145,
	205,
	285
]

const MAX_TYPES_PER_WAVE := 3

const XP_GOAL_BASE := 8.0
const XP_GOAL_GROWTH := 1.45
const XP_GOAL_POWER := 0.80

var rng := RandomNumberGenerator.new()
var combat = CombatSystemScript.new()
var enemy_definitions: Dictionary = {}
var next_enemy_uid := 1
var locked_target_uid := -1
var priority_focus_uid := -1
var priority_typed_index := 0

# Typing state ----------------------------------------------------------------
var word_pool: Array[String] = []
var word_queue: Array[String] = []
var active_word_index := 0
var typed_index := 0
var typing_line_offset_y := 0.0

var caret_target_x := TYPING_LEFT_X
var caret_target_y := 4.0
var caret_visual_x := TYPING_LEFT_X
var caret_visual_y := 4.0
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
var run_complete := false

var current_wave := 1
var wave_spawned_count := 0
var wave_resolved_count := 0
var wave_spawning := true
var wave_intermission := false
var wave_continue_waiting := false
var wave_continue_typed := ""
var wave_spawn_plan: Array[Dictionary] = []

var correct_keys := 0
var incorrect_keys := 0
var typed_characters := 0

# XP / level ups --------------------------------------------------------------
var level := 1
var xp_total := 0
var xp_in_level := 0
var xp_required := 8
var pending_level_ups := 0
var level_up_open := false
var upgrade_definitions: Array = []
var upgrade_levels: Dictionary = {}
var current_upgrade_choices: Array[Dictionary] = []
var upgrade_candidate_index := -1
var upgrade_typed := ""
var upgrade_error_time := 0.0
var xp_hud_pulse := 0.0
var xp_bar_jump_time := 0.0
var xp_bar_base_y := 0.0

var reaction_counts := {
	"shatter": 0,
	"overload": 0
}

# UI --------------------------------------------------------------------------
@onready var typing_viewport: Control = $HUD/TypingViewport
@onready var typing_panel: RichTextLabel = $HUD/TypingViewport/TypingPanel
@onready var typing_caret: ColorRect = $HUD/TypingViewport/TypingCaret
@onready var stats_label: Label = $HUD/Stats

@onready var xp_panel: Control = $HUD/XPPanel
@onready var xp_bar_background: Control = $HUD/XPPanel/XPBarBackground
@onready var xp_bar_fill: ColorRect = $HUD/XPPanel/XPBarBackground/XPBarFill
@onready var xp_count_label: Label = $HUD/XPPanel/XPCount
@onready var level_label: Label = $HUD/XPPanel/LevelLabel
@onready var wave_label: Label = $HUD/WaveLabel

@onready var upgrade_overlay: ColorRect = $HUD/UpgradeOverlay
@onready var upgrade_title: Label = $HUD/UpgradeOverlay/Title
@onready var upgrade_subtitle: RichTextLabel = $HUD/UpgradeOverlay/Subtitle
@onready var upgrade_card_nodes: Array[ColorRect] = [
	$HUD/UpgradeOverlay/Card1,
	$HUD/UpgradeOverlay/Card2,
	$HUD/UpgradeOverlay/Card3
]
@onready var upgrade_card_labels: Array[RichTextLabel] = [
	$HUD/UpgradeOverlay/Card1/Text,
	$HUD/UpgradeOverlay/Card2/Text,
	$HUD/UpgradeOverlay/Card3/Text
]

@onready var death_overlay: ColorRect = $HUD/DeathOverlay
@onready var run_end_title: Label = $HUD/DeathOverlay/GameOver
@onready var death_summary: Label = $HUD/DeathOverlay/Summary


func _ready() -> void:
	rng.randomize()
	combat.load_definitions("starter")
	_load_words()
	_load_upgrades()
	_load_enemy_definitions()
	xp_bar_base_y = xp_bar_background.position.y
	_prepare_wave_spawn_plan(current_wave)

	for i in range(WORD_BUFFER):
		_append_random_word()

	_update_typing_ui()
	_update_xp_ui()
	_update_wave_ui()
	_update_stats()
	queue_redraw()


func _process(delta: float) -> void:
	_update_typing_line_motion(delta)
	_update_typing_caret(delta)
	_update_xp_hud(delta)
	upgrade_error_time = maxf(upgrade_error_time - delta, 0.0)

	if run_over or run_complete or level_up_open or wave_intermission:
		# Combat pauses for decisions/death/wave breaks, while existing visual feedback
		# gets a chance to settle.
		_update_particles(delta)
		_update_damage_numbers(delta)
		_update_reaction_waves(delta)
		queue_redraw()
		return

	elapsed += delta
	error_flash = maxf(error_flash - delta, 0.0)
	player_recoil = maxf(player_recoil - delta, 0.0)
	shake_time = maxf(shake_time - delta, 0.0)

	if wave_spawning:
		spawn_timer -= delta

		if spawn_timer <= 0.0:
			_spawn_enemy()
			wave_spawned_count += 1
			spawn_timer = spawn_interval

			if wave_spawned_count >= wave_spawn_plan.size():
				wave_spawning = false

	_update_enemies(delta)
	_update_bullets(delta)
	_process_pending_reactions()
	_update_reaction_waves(delta)
	_update_particles(delta)
	_update_damage_numbers(delta)

	if (
		not wave_spawning
		and wave_resolved_count >= wave_spawn_plan.size()
		and enemies.is_empty()
		and not _has_pending_xp_particles()
		and not wave_intermission
	):
		_finish_wave()

	_update_wave_ui()
	_update_stats()
	_update_canvas_shake()
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return

	if run_over or run_complete:
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()
		return

	if wave_continue_waiting:
		if event.unicode != 0:
			var continue_key := char(event.unicode).to_lower()
			if continue_key.length() == 1 and continue_key >= "a" and continue_key <= "z":
				_handle_wave_continue_typing(continue_key)
		return

	if wave_intermission and not level_up_open:
		return

	if level_up_open:
		if event.unicode != 0:
			var upgrade_key := char(event.unicode).to_lower()
			if upgrade_key.length() == 1 and upgrade_key >= "a" and upgrade_key <= "z":
				_handle_upgrade_typing(upgrade_key)
		return

	if event.keycode == KEY_TAB:
		_toggle_priority_focus()
		return

	if event.unicode == 0:
		return

	var typed := char(event.unicode).to_lower()
	if typed.length() != 1 or typed < "a" or typed > "z":
		return

	if priority_focus_uid >= 0:
		_handle_priority_typing(typed)
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


# Priority enemies ------------------------------------------------------------

func _get_enemy_index_by_uid(uid: int) -> int:
	if uid < 0:
		return -1

	for i in range(enemies.size()):
		if int(enemies[i].get("uid", -1)) == uid:
			return i

	return -1


func _get_nearest_priority_index() -> int:
	var center := get_viewport_rect().size * 0.5
	var best_index := -1
	var best_distance_sq := INF

	for i in range(enemies.size()):
		if not bool(enemies[i].get("priority", false)):
			continue

		var pos: Vector2 = enemies[i]["position"]
		var distance_sq := center.distance_squared_to(pos)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_index = i

	return best_index


func _toggle_priority_focus() -> void:
	if priority_focus_uid >= 0:
		priority_focus_uid = -1
		priority_typed_index = 0
		return

	var index := _get_nearest_priority_index()
	if index < 0:
		return

	priority_focus_uid = int(enemies[index].get("uid", -1))
	priority_typed_index = 0


func _handle_priority_typing(typed: String) -> void:
	var index := _get_enemy_index_by_uid(priority_focus_uid)
	if index < 0:
		priority_focus_uid = -1
		priority_typed_index = 0
		return

	typed_characters += 1
	caret_idle_time = 0.0

	var enemy := enemies[index]
	var command := String(enemy.get("priority_word", ""))
	if command.is_empty():
		priority_focus_uid = -1
		priority_typed_index = 0
		return

	var expected := command.substr(priority_typed_index, 1)

	if typed == expected:
		correct_keys += 1
		streak += 1
		best_streak = maxi(best_streak, streak)
		priority_typed_index += 1
		enemy["flash"] = 0.10
		enemies[index] = enemy

		if priority_typed_index >= command.length():
			var position: Vector2 = enemy["position"]
			_spawn_combat_text(
				position + Vector2(0.0, -34.0),
				"PURGED",
				Color(0.72, 0.95, 1.0)
			)
			priority_focus_uid = -1
			priority_typed_index = 0
			_kill_enemy(index, position)
	else:
		incorrect_keys += 1
		streak = 0
		priority_typed_index = 0
		error_flash = 0.16


func _random_priority_word() -> String:
	var candidates: Array[String] = []

	for word in word_pool:
		if word.length() >= 4 and word.length() <= 7:
			candidates.append(word)

	if candidates.is_empty():
		return "signal"

	return candidates[rng.randi_range(0, candidates.size() - 1)]


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
	while word_queue.size() < WORD_BUFFER:
		_append_random_word()


func _get_current_word() -> String:
	if active_word_index < 0 or active_word_index >= word_queue.size():
		return ""
	return word_queue[active_word_index]


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


func _build_typing_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var start_index := 0
	var line_width := 0.0
	var space_width := _measure_text_width(" ")

	for i in range(word_queue.size()):
		var word_width := _measure_text_width(word_queue[i])
		var added_width := word_width
		if i > start_index:
			added_width += space_width

		if line_width > 0.0 and line_width + added_width > TYPING_LINE_WIDTH:
			lines.append({
				"start": start_index,
				"end": i,
				"width": line_width
			})
			start_index = i
			line_width = word_width
		else:
			line_width += added_width

		if lines.size() >= 2:
			break

	if lines.size() < 2 and start_index < word_queue.size():
		lines.append({
			"start": start_index,
			"end": word_queue.size(),
			"width": line_width
		})

	return lines


func _complete_word(completed_word: String) -> void:
	words_completed += 1
	typed_index = 0
	active_word_index += 1
	_ensure_word_buffer()

	# Completed words remain in place and fade. Only after an entire line is
	# finished do we move the next line upward, matching Monkeytype's rhythm.
	var lines := _build_typing_lines()
	if lines.size() >= 2:
		var second_line_start := int(lines[1]["start"])
		if active_word_index >= second_line_start:
			var remove_count := second_line_start
			for i in range(remove_count):
				word_queue.pop_front()
			active_word_index -= remove_count
			_ensure_word_buffer()
			typing_line_offset_y = TYPING_LINE_HEIGHT

	_update_typing_ui()

	_emit_combat_trigger("word_complete", {
		"word": completed_word,
		"word_length": completed_word.length(),
		"streak": streak
	})


func _update_typing_ui() -> void:
	if word_queue.is_empty():
		return

	var lines := _build_typing_lines()
	var rendered_lines: Array[String] = []

	for line_index in range(mini(2, lines.size())):
		var line: Dictionary = lines[line_index]
		var pieces: Array[String] = []

		for i in range(int(line["start"]), int(line["end"])):
			if i < active_word_index:
				pieces.append("[color=#454c58]" + word_queue[i] + "[/color]")
			elif i == active_word_index:
				pieces.append("[color=#ffffff]" + word_queue[i] + "[/color]")
			else:
				pieces.append("[color=#697180]" + word_queue[i] + "[/color]")

		rendered_lines.append(" ".join(pieces))

	typing_panel.text = "\n".join(rendered_lines)
	typing_panel.position.x = TYPING_LEFT_X
	typing_panel.position.y = typing_line_offset_y


func _update_typing_line_motion(delta: float) -> void:
	if typing_line_offset_y <= 0.01:
		typing_line_offset_y = 0.0
		typing_panel.position.y = 0.0
		return

	var follow := 1.0 - exp(-22.0 * delta)
	typing_line_offset_y = lerpf(typing_line_offset_y, 0.0, follow)
	typing_panel.position.y = typing_line_offset_y


func _get_active_word_line_data() -> Dictionary:
	var lines := _build_typing_lines()

	for line_index in range(lines.size()):
		var line: Dictionary = lines[line_index]
		var start := int(line["start"])
		var end := int(line["end"])

		if active_word_index >= start and active_word_index < end:
			var prefix_words: Array[String] = []
			for i in range(start, active_word_index):
				prefix_words.append(word_queue[i])

			var prefix := ""
			if not prefix_words.is_empty():
				prefix = " ".join(prefix_words) + " "

			return {
				"line": line_index,
				"prefix_width": _measure_text_width(prefix)
			}

	return {
		"line": 0,
		"prefix_width": 0.0
	}


func _update_typing_caret(delta: float) -> void:
	if word_queue.is_empty():
		return

	if priority_focus_uid >= 0:
		typing_caret.visible = false
		typing_panel.modulate.a = 0.42
		return

	typing_caret.visible = true
	typing_panel.modulate.a = 1.0
	caret_idle_time += delta

	var current := _get_current_word()
	var completed := current.substr(0, typed_index)
	var completed_width := _measure_text_width(completed)
	var line_data := _get_active_word_line_data()

	caret_target_x = TYPING_LEFT_X + float(line_data["prefix_width"]) + completed_width - typing_caret.size.x * 0.5
	caret_target_y = 4.0 + float(line_data["line"]) * TYPING_LINE_HEIGHT + typing_line_offset_y

	if not caret_initialized:
		caret_visual_x = caret_target_x
		caret_visual_y = caret_target_y
		caret_initialized = true

	var follow := 1.0 - exp(-38.0 * delta)
	caret_visual_x = lerpf(caret_visual_x, caret_target_x, follow)
	caret_visual_y = lerpf(caret_visual_y, caret_target_y, follow)
	typing_caret.position = Vector2(caret_visual_x, caret_visual_y)

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
	if wave_spawned_count < 0 or wave_spawned_count >= wave_spawn_plan.size():
		return

	var spec: Dictionary = wave_spawn_plan[wave_spawned_count]
	var viewport_size := get_viewport_rect().size
	var margin := rng.randf_range(SPAWN_MARGIN_MIN, SPAWN_MARGIN_MAX)
	var edge := rng.randi_range(0, 3)
	var position := Vector2.ZERO

	match edge:
		0: # top
			position = Vector2(
				rng.randf_range(-margin, viewport_size.x + margin),
				-margin
			)
		1: # right
			position = Vector2(
				viewport_size.x + margin,
				rng.randf_range(-margin, viewport_size.y + margin)
			)
		2: # bottom
			position = Vector2(
				rng.randf_range(-margin, viewport_size.x + margin),
				viewport_size.y + margin
			)
		_: # left
			position = Vector2(
				-margin,
				rng.randf_range(-margin, viewport_size.y + margin)
			)

	var wave_scale := float(current_wave - 1)
	var base_speed := rng.randf_range(38.0, 62.0) + wave_scale * 2.2 + minf(elapsed * 0.06, 12.0)
	var base_hp := 44.0 + wave_scale * 4.5 + minf(elapsed * 0.05, 14.0)
	var radius := ENEMY_RADIUS * float(spec.get("radius_multiplier", 1.0))
	var hp_value := base_hp * float(spec.get("hp_multiplier", 1.0))
	var speed := base_speed * float(spec.get("speed_multiplier", 1.0))
	var threat_cost := int(spec.get("threat_cost", 1))
	var is_priority := bool(spec.get("priority", false))
	var uid := next_enemy_uid
	next_enemy_uid += 1
	var priority_word := _random_priority_word() if is_priority else ""
	var base_color := Color.from_string(
		String(spec.get("color", "#f25561")),
		Color(0.95, 0.33, 0.38)
	)

	enemies.append({
		"uid": uid,
		"position": position,
		"enemy_id": String(spec.get("enemy_id", "basic")),
		"priority": is_priority,
		"priority_word": priority_word,
		"speed": speed,
		"hp": hp_value,
		"max_hp": hp_value,
		"xp_value": threat_cost,
		"radius": radius,
		"base_color": base_color,
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
			var removed_uid := int(enemy.get("uid", -1))
			enemies.remove_at(i)
			wave_resolved_count += 1

			if removed_uid == locked_target_uid:
				locked_target_uid = -1
			if removed_uid == priority_focus_uid:
				priority_focus_uid = -1
				priority_typed_index = 0

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


func _get_locked_target_index() -> int:
	var existing := _get_enemy_index_by_uid(locked_target_uid)

	if existing >= 0 and not bool(enemies[existing].get("priority", false)):
		return existing

	locked_target_uid = -1

	var center := get_viewport_rect().size * 0.5
	var nearest_index := -1
	var nearest_distance_sq := INF

	for i in range(enemies.size()):
		if bool(enemies[i].get("priority", false)):
			continue

		var enemy_pos: Vector2 = enemies[i]["position"]
		var distance_sq := center.distance_squared_to(enemy_pos)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest_index = i

	if nearest_index >= 0:
		locked_target_uid = int(enemies[nearest_index].get("uid", -1))

	return nearest_index


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

	var target_index := _get_locked_target_index()
	if target_index < 0:
		return

	var center := get_viewport_rect().size * 0.5
	var target: Vector2 = enemies[target_index]["position"]
	var direction := (target - center).normalized().rotated(spread)

	bullets.append({
		"position": center + direction * 16.0,
		"velocity": direction * speed,
		"damage": damage,
		"life": 1.1,
		"tags": tags.duplicate(),
		"effects": effects.duplicate(true),
		"weapon_id": weapon_id,
		"target_uid": locked_target_uid,
		"strict_target": absf(spread) < 0.001,
		"color": projectile_color
	})


func _update_bullets(delta: float) -> void:
	for bullet_index in range(bullets.size() - 1, -1, -1):
		var bullet := bullets[bullet_index]
		bullet["position"] = Vector2(bullet["position"]) + Vector2(bullet["velocity"]) * delta
		bullet["life"] = float(bullet["life"]) - delta
		var hit := false

		for enemy_index in range(enemies.size() - 1, -1, -1):
			if bool(enemies[enemy_index].get("priority", false)):
				continue

			if bool(bullet.get("strict_target", false)):
				var intended_uid := int(bullet.get("target_uid", -1))
				if int(enemies[enemy_index].get("uid", -1)) != intended_uid:
					continue

			var enemy_pos: Vector2 = enemies[enemy_index]["position"]

			var enemy_radius := float(
				enemies[enemy_index].get("radius", ENEMY_RADIUS)
			)
			if Vector2(bullet["position"]).distance_squared_to(enemy_pos) <= pow(
				enemy_radius + BULLET_RADIUS,
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

	var enemy_uid := int(enemies[index].get("uid", -1))
	var xp_value := int(enemies[index].get("xp_value", 1))
	enemies.remove_at(index)

	if enemy_uid == locked_target_uid:
		locked_target_uid = -1
	if enemy_uid == priority_focus_uid:
		priority_focus_uid = -1
		priority_typed_index = 0

	kills += 1
	wave_resolved_count += 1
	_spawn_death_particles(position)
	_spawn_xp_particles(position, xp_value)


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


func _xp_required_for_level(current_level: int) -> int:
	# Adapted from the useful part of shatAAAAp!'s model: level costs rise
	# nonlinearly while each wave's available XP budget also ramps upward.
	var pick_index := float(maxi(current_level - 1, 0))
	return int(round(
		XP_GOAL_BASE
		* pow(
			XP_GOAL_GROWTH,
			pow(pick_index, XP_GOAL_POWER)
		)
	))


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

	var fill_width := maxf(xp_bar_background.size.x - 2.0, 0.0)
	xp_bar_fill.size.x = fill_width * ratio
	level_label.text = "LV %d" % level
	xp_count_label.text = "%d/%d" % [xp_in_level, xp_required]


func _update_xp_hud(delta: float) -> void:
	xp_hud_pulse = maxf(xp_hud_pulse - delta, 0.0)
	xp_bar_jump_time = maxf(xp_bar_jump_time - delta, 0.0)

	var pulse := clampf(xp_hud_pulse / 0.18, 0.0, 1.0)
	xp_bar_fill.color = Color(0.42, 0.95, 0.72, 1.0).lerp(
		Color(0.82, 1.0, 0.91, 1.0),
		pulse * 0.55
	)

	var jump := 0.0
	if xp_bar_jump_time > 0.0:
		var progress := 1.0 - xp_bar_jump_time / 0.22
		jump = sin(progress * PI) * 3.5

	xp_bar_background.position.y = xp_bar_base_y - jump


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
		_open_wave_continue()
		return

	level_up_open = true
	upgrade_candidate_index = -1
	upgrade_typed = ""
	upgrade_overlay.visible = true
	upgrade_title.text = "WAVE %d COMPLETE" % current_wave
	upgrade_subtitle.text = "[center]%d upgrade%s banked — type one command word[/center]" % [
		pending_level_ups + 1,
		"" if pending_level_ups == 0 else "s"
	]
	_refresh_upgrade_cards()


func _roll_upgrade_choices(count: int) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []

	for raw_upgrade in upgrade_definitions:
		var upgrade: Dictionary = raw_upgrade
		if _upgrade_is_available(upgrade):
			candidates.append(upgrade.duplicate(true))

	candidates.shuffle()

	var result: Array[Dictionary] = []
	var used_first_letters: Dictionary = {}

	for upgrade in candidates:
		var command := String(upgrade.get("command", "")).to_lower()
		if command.is_empty():
			continue

		var first := command.substr(0, 1)
		if used_first_letters.has(first):
			continue

		result.append(upgrade)
		used_first_letters[first] = true

		if result.size() >= count:
			break

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


func _handle_upgrade_typing(typed: String) -> void:
	if current_upgrade_choices.is_empty():
		return

	if upgrade_candidate_index < 0:
		for i in range(current_upgrade_choices.size()):
			var command := String(
				current_upgrade_choices[i].get("command", "")
			).to_lower()

			if command.begins_with(typed):
				upgrade_candidate_index = i
				upgrade_typed = typed
				_refresh_upgrade_cards()

				if upgrade_typed.length() >= command.length():
					_choose_upgrade(i)
				return

		_upgrade_typing_error()
		return

	var selected_command := String(
		current_upgrade_choices[upgrade_candidate_index].get("command", "")
	).to_lower()
	var expected_index := upgrade_typed.length()

	if expected_index < selected_command.length() and typed == selected_command.substr(expected_index, 1):
		upgrade_typed += typed
		_refresh_upgrade_cards()

		if upgrade_typed.length() >= selected_command.length():
			_choose_upgrade(upgrade_candidate_index)
	else:
		# A wrong key resets the command, but the same key can immediately start
		# another card if it matches that card's unique first letter.
		_upgrade_typing_error()
		for i in range(current_upgrade_choices.size()):
			var command := String(
				current_upgrade_choices[i].get("command", "")
			).to_lower()
			if command.begins_with(typed):
				upgrade_candidate_index = i
				upgrade_typed = typed
				_refresh_upgrade_cards()
				return


func _upgrade_typing_error() -> void:
	upgrade_candidate_index = -1
	upgrade_typed = ""
	upgrade_error_time = 0.18
	_refresh_upgrade_cards()


func _refresh_upgrade_cards() -> void:
	for i in range(upgrade_card_labels.size()):
		var card := upgrade_card_nodes[i]
		var label := upgrade_card_labels[i]

		if i >= current_upgrade_choices.size():
			card.visible = false
			continue

		card.visible = true
		var upgrade: Dictionary = current_upgrade_choices[i]
		var command := String(upgrade.get("command", "")).to_lower()
		var picks := int(
			upgrade_levels.get(
				String(upgrade.get("id", "")),
				0
			)
		)

		var command_markup := "[color=#f2f5f7]" + command.to_upper() + "[/color]"
		if i == upgrade_candidate_index:
			var done := command.substr(0, upgrade_typed.length()).to_upper()
			var remaining := command.substr(upgrade_typed.length()).to_upper()
			command_markup = "[color=#65e6a6]" + done + "[/color][color=#ffffff]" + remaining + "[/color]"
			card.color = Color(0.13, 0.22, 0.20, 1.0)
		elif upgrade_candidate_index >= 0:
			card.color = Color(0.075, 0.085, 0.11, 1.0)
		else:
			card.color = Color(0.12, 0.14, 0.18, 1.0)

		if upgrade_error_time > 0.0 and upgrade_candidate_index < 0:
			card.color = card.color.lerp(Color(0.34, 0.10, 0.12, 1.0), 0.35)

		label.text = "[center][font_size=22][b]%s[/b][/font_size]\n\n%s\n\n[font_size=26][b]%s[/b][/font_size]\n[color=#7f8998]Taken: %d[/color][/center]" % [
			String(upgrade.get("name", "Upgrade")),
			String(upgrade.get("description", "")),
			command_markup,
			picks
		]


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
	upgrade_candidate_index = -1
	upgrade_typed = ""

	if pending_level_ups > 0:
		call_deferred("_open_level_up")
	else:
		_open_wave_continue()


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


func _load_enemy_definitions() -> void:
	if not FileAccess.file_exists(ENEMIES_PATH):
		push_error("Missing enemy definitions: %s" % ENEMIES_PATH)
		return

	var parsed = JSON.parse_string(
		FileAccess.get_file_as_string(ENEMIES_PATH)
	)

	if parsed == null or not (parsed is Dictionary):
		push_error("Invalid enemy definitions.")
		return

	enemy_definitions = parsed


func _wave_threat_budget(wave_number: int) -> int:
	var index := clampi(
		wave_number - 1,
		0,
		WAVE_THREAT_BUDGETS.size() - 1
	)
	return int(WAVE_THREAT_BUDGETS[index])


func _available_enemy_ids(wave_number: int) -> Array[String]:
	var specials: Array[Dictionary] = []

	for enemy_id in enemy_definitions.keys():
		if String(enemy_id) == "basic":
			continue

		var definition: Dictionary = enemy_definitions[enemy_id]
		var unlock_wave := int(definition.get("unlock_wave", 1))
		if unlock_wave <= wave_number:
			specials.append({
				"id": String(enemy_id),
				"unlock_wave": unlock_wave
			})

	specials.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["unlock_wave"]) > int(b["unlock_wave"])
	)

	var result: Array[String] = []
	if enemy_definitions.has("basic"):
		result.append("basic")

	var special_slots := maxi(MAX_TYPES_PER_WAVE - result.size(), 0)
	for i in range(mini(special_slots, specials.size())):
		result.append(String(specials[i]["id"]))

	return result


func _weighted_enemy_choice(
	candidates: Array[String],
	remaining_budget: int
) -> String:
	var affordable: Array[String] = []
	var total_weight := 0.0

	for enemy_id in candidates:
		var definition: Dictionary = enemy_definitions[enemy_id]
		var cost := int(definition.get("threat_cost", 1))
		if cost <= remaining_budget:
			affordable.append(enemy_id)
			total_weight += maxf(float(definition.get("weight", 1.0)), 0.01)

	if affordable.is_empty():
		return "basic"

	var roll := rng.randf() * total_weight
	var cursor := 0.0

	for enemy_id in affordable:
		var definition: Dictionary = enemy_definitions[enemy_id]
		cursor += maxf(float(definition.get("weight", 1.0)), 0.01)
		if roll <= cursor:
			return enemy_id

	return affordable.back()


func _prepare_wave_spawn_plan(wave_number: int) -> void:
	wave_spawn_plan.clear()

	var remaining_budget := _wave_threat_budget(wave_number)
	var available := _available_enemy_ids(wave_number)

	if available.is_empty():
		available = ["basic"]

	while remaining_budget > 0:
		var enemy_id := _weighted_enemy_choice(
			available,
			remaining_budget
		)
		if not enemy_definitions.has(enemy_id):
			break

		var definition: Dictionary = enemy_definitions[enemy_id]
		var cost := maxi(int(definition.get("threat_cost", 1)), 1)

		if cost > remaining_budget:
			enemy_id = "basic"
			definition = enemy_definitions.get("basic", {})
			cost = maxi(int(definition.get("threat_cost", 1)), 1)

		if cost > remaining_budget:
			break

		var spawn_spec := definition.duplicate(true)
		spawn_spec["enemy_id"] = enemy_id
		wave_spawn_plan.append(spawn_spec)
		remaining_budget -= cost

	wave_spawn_plan.shuffle()
	wave_spawned_count = 0
	wave_resolved_count = 0


func _has_pending_xp_particles() -> bool:
	for particle in particles:
		if String(particle.get("kind", "")) == "xp":
			return true
	return false


func _finish_wave() -> void:
	if wave_intermission or run_over or run_complete:
		return

	wave_intermission = true

	# Wave 1 is our onboarding beat: clearing it always unlocks the first
	# upgrade decision, even if a few enemies reached the player.
	if current_wave == 1 and level == 1:
		var first_level_top_up := maxi(xp_required - xp_in_level, 0)
		if first_level_top_up > 0:
			_grant_xp(first_level_top_up)

	if current_wave >= TOTAL_WAVES:
		_complete_run()
		return

	if pending_level_ups > 0:
		call_deferred("_open_level_up")
	else:
		_open_wave_continue()


func _open_wave_continue() -> void:
	level_up_open = false
	wave_continue_waiting = true
	wave_continue_typed = ""
	upgrade_overlay.visible = true
	upgrade_title.text = "WAVE %d CLEARED" % current_wave
	_refresh_wave_continue_indicator()

	for card in upgrade_card_nodes:
		card.visible = false


func _handle_wave_continue_typing(typed: String) -> void:
	const COMMAND := "ready"
	var expected_index := wave_continue_typed.length()

	if expected_index < COMMAND.length() and typed == COMMAND.substr(expected_index, 1):
		wave_continue_typed += typed
	else:
		wave_continue_typed = typed if typed == "r" else ""

	_refresh_wave_continue_indicator()

	if wave_continue_typed.length() >= COMMAND.length():
		wave_continue_waiting = false
		wave_continue_typed = ""
		_start_next_wave()


func _refresh_wave_continue_indicator() -> void:
	const COMMAND := "ready"
	var shown := wave_continue_typed.to_upper()
	var remaining := COMMAND.substr(wave_continue_typed.length()).to_upper()
	var command_markup := "[color=#65e6a6][b]%s[/b][/color][color=#67717f]%s[/color]" % [
		shown,
		remaining
	]

	upgrade_subtitle.text = "[center][color=#8b94a2]NEXT: WAVE %d  •  THREAT %d[/color]\n\n[font_size=30]%s[/font_size]\n[color=#68717d]TYPE TO START[/color][/center]" % [
		current_wave + 1,
		_wave_threat_budget(current_wave + 1),
		command_markup
	]


func _start_next_wave() -> void:
	if run_over or run_complete:
		return

	level_up_open = false
	wave_continue_waiting = false
	locked_target_uid = -1
	priority_focus_uid = -1
	priority_typed_index = 0
	upgrade_overlay.visible = false
	wave_intermission = false
	current_wave += 1
	wave_spawning = true
	spawn_timer = 0.35
	spawn_interval = maxf(0.30, 0.95 - float(current_wave - 1) * 0.045)
	_prepare_wave_spawn_plan(current_wave)
	_reset_typing_for_new_wave()
	_update_wave_ui()


func _reset_typing_for_new_wave() -> void:
	word_queue.clear()
	active_word_index = 0
	typed_index = 0
	typing_line_offset_y = 0.0
	caret_idle_time = 0.0
	caret_initialized = false
	caret_target_x = TYPING_LEFT_X
	caret_target_y = 4.0
	caret_visual_x = TYPING_LEFT_X
	caret_visual_y = 4.0
	typing_panel.position.y = 0.0

	for i in range(WORD_BUFFER):
		_append_random_word()

	_update_typing_ui()


func _complete_run() -> void:
	run_complete = true
	wave_intermission = true
	wave_spawning = false
	run_end_title.text = "RUN COMPLETE"
	death_overlay.visible = true
	death_summary.text = "%d WAVES CLEARED   LEVEL %d   KILLS %d\nWORDS %d   BEST STREAK %d   WPM %d\n\nPress R to restart" % [
		TOTAL_WAVES,
		level,
		kills,
		words_completed,
		best_streak,
		_get_current_wpm()
	]


func _update_wave_ui() -> void:
	if not is_instance_valid(wave_label):
		return

	if run_complete:
		wave_label.text = "WAVE %d / %d   COMPLETE" % [
			TOTAL_WAVES,
			TOTAL_WAVES
		]
	elif wave_intermission:
		wave_label.text = "WAVE %d / %d   CLEARED" % [current_wave, TOTAL_WAVES]
	else:
		var total_enemies := wave_spawn_plan.size()
		var remaining := maxi(total_enemies - wave_resolved_count, 0)
		wave_label.text = "WAVE %d / %d   ENEMIES %d" % [
			current_wave,
			TOTAL_WAVES,
			remaining
		]


func _end_run() -> void:
	if run_over:
		return

	run_over = true
	hp = 0.0
	wave_spawning = false
	run_end_title.text = "RUN OVER"
	death_overlay.visible = true
	death_summary.text = "WAVE %d / %d   LEVEL %d   KILLS %d\nWORDS %d   BEST STREAK %d   WPM %d\n\nPress R to restart" % [
		current_wave,
		TOTAL_WAVES,
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


func _random_xp_color() -> Color:
	var roll := rng.randf()
	if roll < 0.34:
		return Color(0.44, 1.0, 0.70)
	if roll < 0.67:
		return Color(0.70, 1.0, 0.55)
	return Color(0.90, 1.0, 0.72)


func _spawn_xp_particles(position: Vector2, amount: int) -> void:
	var screen_width := get_viewport_rect().size.x
	var normalized_x := clampf(position.x / screen_width, 0.0, 1.0)
	var bar_left := xp_bar_background.global_position.x
	var bar_width := xp_bar_background.size.x
	var target_x := bar_left + normalized_x * bar_width
	var target_y := xp_bar_background.global_position.y + xp_bar_background.size.y + 2.0

	# Reference feel: messy, varied death burst first; then several tiny motes
	# peel away toward the XP bar at slightly different times and curves.
	var burst_count := rng.randi_range(12, 20)
	for i in range(burst_count):
		var angle := rng.randf_range(0.0, TAU)
		var speed := rng.randf_range(35.0, 185.0)
		var life := rng.randf_range(0.18, 0.56)
		particles.append({
			"position": position + Vector2(
				rng.randf_range(-3.0, 3.0),
				rng.randf_range(-3.0, 3.0)
			),
			"velocity": Vector2.RIGHT.rotated(angle) * speed,
			"life": life,
			"max_life": life,
			"color": _random_xp_color(),
			"size": rng.randf_range(1.0, 4.2),
			"shape": "square" if rng.randf() < 0.62 else "dot",
			"kind": "impact"
		})

	var tracer_count := rng.randi_range(6, 10)
	for i in range(tracer_count):
		var launch_angle := rng.randf_range(-2.9, 0.25)
		var life := rng.randf_range(1.65, 2.15)
		particles.append({
			"position": position + Vector2(
				rng.randf_range(-5.0, 5.0),
				rng.randf_range(-5.0, 5.0)
			),
			"velocity": Vector2.RIGHT.rotated(launch_angle) * rng.randf_range(55.0, 150.0),
			"target": Vector2(
				target_x + rng.randf_range(-8.0, 8.0),
				target_y + rng.randf_range(-2.5, 2.5)
			),
			"homing_delay": rng.randf_range(0.07, 0.28),
			"homing_speed": rng.randf_range(430.0, 610.0),
			"homing_gain": rng.randf_range(3.8, 6.0),
			"wander_phase": rng.randf_range(0.0, TAU),
			"wander_speed": rng.randf_range(7.0, 14.0),
			"wander_strength": rng.randf_range(12.0, 42.0),
			"life": life,
			"max_life": life,
			"color": _random_xp_color(),
			"size": rng.randf_range(1.2, 3.1),
			"shape": "square" if rng.randf() < 0.72 else "dot",
			"kind": "xp",
			"amount": amount if i == 0 else 0
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

			var phase := float(
				particle.get("wander_phase", 0.0)
			) + float(
				particle.get("wander_speed", 0.0)
			) * delta
			particle["wander_phase"] = phase

			if delay <= 0.0:
				var pos: Vector2 = particle["position"]
				var target: Vector2 = particle["target"]
				var to_target := target - pos
				var direction := to_target.normalized()
				var tangent := Vector2(-direction.y, direction.x)
				var wander := tangent * sin(phase) * float(
					particle.get("wander_strength", 0.0)
				)
				var desired := direction * float(
					particle.get("homing_speed", 520.0)
				) + wander
				var follow := 1.0 - exp(
					-float(particle.get("homing_gain", 4.8)) * delta
				)
				particle["velocity"] = Vector2(
					particle["velocity"]
				).lerp(desired, follow)

				if to_target.length() < 12.0:
					var amount := int(particle.get("amount", 0))
					if amount > 0:
						_grant_xp(amount)
						xp_hud_pulse = 0.18
						_trigger_xp_bar_impact(target.x)

					_spawn_xp_landing_particles(target, amount > 0)
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
			if particle["kind"] == "xp":
				var amount := int(particle.get("amount", 0))
				if amount > 0:
					_grant_xp(amount)
					xp_hud_pulse = 0.18
					var target: Vector2 = particle["target"]
					_trigger_xp_bar_impact(target.x)
					_spawn_xp_landing_particles(target, true)
			particles.remove_at(i)
		else:
			particles[i] = particle


func _spawn_xp_landing_particles(position: Vector2, strong: bool) -> void:
	var count := rng.randi_range(7, 11) if strong else rng.randi_range(2, 4)

	for i in range(count):
		var angle := rng.randf_range(0.15, PI - 0.15)
		var life := rng.randf_range(0.16, 0.34)
		particles.append({
			"position": position + Vector2(
				rng.randf_range(-2.0, 2.0),
				rng.randf_range(-1.0, 2.0)
			),
			"velocity": Vector2.RIGHT.rotated(angle) * rng.randf_range(35.0, 120.0),
			"life": life,
			"max_life": life,
			"color": _random_xp_color(),
			"size": rng.randf_range(1.0, 3.2),
			"shape": "square" if rng.randf() < 0.70 else "dot",
			"kind": "impact"
		})


func _trigger_xp_bar_impact(_global_x: float) -> void:
	xp_bar_jump_time = 0.22


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

	var world_font := ThemeDB.fallback_font

	for enemy in enemies:
		var pos: Vector2 = enemy["position"]
		var enemy_color := _get_enemy_draw_color(enemy)

		if float(enemy["flash"]) > 0.0:
			enemy_color = enemy_color.lerp(
				Color.WHITE,
				0.72
			)

		var enemy_radius := float(enemy.get("radius", ENEMY_RADIUS))
		draw_circle(
			pos,
			enemy_radius,
			enemy_color
		)

		if int(enemy.get("uid", -1)) == locked_target_uid:
			draw_arc(
				pos,
				enemy_radius + 4.0,
				0.0,
				TAU,
				24,
				Color(0.56, 0.94, 0.76, 0.62),
				1.0
			)

		var statuses: Dictionary = enemy.get(
			"statuses",
			{}
		)
		if statuses.has("freeze"):
			draw_arc(
				pos,
				enemy_radius + 3.0,
				0.0,
				TAU,
				24,
				Color(0.40, 0.81, 1.0, 0.95),
				2.0
			)
		if statuses.has("shock"):
			draw_arc(
				pos,
				enemy_radius + 6.0,
				0.0,
				TAU,
				24,
				Color(1.0, 0.85, 0.30, 0.95),
				2.0
			)

		if bool(enemy.get("priority", false)):
			var uid := int(enemy.get("uid", -1))
			var command := String(enemy.get("priority_word", "")).to_upper()
			var focused := uid == priority_focus_uid
			var ring_color := Color(0.72, 0.52, 1.0, 0.95) if not focused else Color(0.55, 0.95, 1.0, 1.0)

			draw_arc(
				pos,
				enemy_radius + 10.0,
				0.0,
				TAU,
				32,
				ring_color,
				2.0
			)

			var word_pos := pos + Vector2(-enemy_radius - 16.0, -enemy_radius - 18.0)
			if focused:
				var done := command.substr(0, priority_typed_index)
				var remaining := command.substr(priority_typed_index)
				draw_string(
					world_font,
					word_pos,
					done,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					14,
					Color(0.42, 0.95, 0.72)
				)
				var done_width := world_font.get_string_size(
					done,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					14
				).x
				draw_string(
					world_font,
					word_pos + Vector2(done_width, 0.0),
					remaining,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					14,
					Color(0.94, 0.97, 1.0)
				)
			else:
				draw_string(
					world_font,
					word_pos,
					command,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					14,
					Color(0.78, 0.72, 1.0)
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
			color.a = maxf(0.72, life_ratio)
		else:
			color.a = life_ratio

		var particle_pos := Vector2(particle["position"])
		var particle_size := float(particle["size"])
		if String(particle.get("shape", "dot")) == "square":
			draw_rect(
				Rect2(
					particle_pos - Vector2.ONE * particle_size * 0.5,
					Vector2.ONE * particle_size
				),
				color
			)
		else:
			draw_circle(
				particle_pos,
				particle_size,
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

	var base_color: Color = enemy.get(
		"base_color",
		Color(0.95, 0.33, 0.38)
	)
	return base_color
