extends Node2D

const CombatSystemScript = preload("res://scripts/combat/combat_system.gd")

const PLAYER_RADIUS := 14.0
const ENEMY_RADIUS := 10.0
const BULLET_RADIUS := 3.0
const SPAWN_RADIUS := 430.0
const DANGER_RADIUS := 42.0
const MAX_HP := 100.0

var rng := RandomNumberGenerator.new()
var combat = CombatSystemScript.new()

var word_pool: Array[String] = []
var word_queue: Array[String] = []
var typed_index := 0

var enemies: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var damage_numbers: Array[Dictionary] = []
var pending_reactions: Array[Dictionary] = []

var spawn_timer := 0.0
var spawn_interval := 0.72
var elapsed := 0.0
var error_flash := 0.0
var key_pulse := 0.0
var player_recoil := 0.0
var shake_time := 0.0
var shake_strength := 0.0

# The caret is a separate overlay, like Monkeytype's. It never becomes part
# of the text string, so advancing it cannot change the word's layout.
var caret_target_x := 0.0
var caret_visual_x := 0.0
var caret_initialized := false
var caret_idle_time := 0.0

var kills := 0
var xp := 0
var words_completed := 0
var streak := 0
var best_streak := 0
var hp := MAX_HP

var correct_keys := 0
var incorrect_keys := 0
var typed_characters := 0

@onready var typing_panel: RichTextLabel = $HUD/TypingPanel
@onready var typing_caret: ColorRect = $HUD/TypingCaret
@onready var stats_label: Label = $HUD/Stats


func _ready() -> void:
	rng.randomize()
	combat.load_definitions("prototype")
	_load_words()

	for i in range(6):
		_append_random_word()

	_update_typing_ui(true)
	_update_stats()
	queue_redraw()


func _process(delta: float) -> void:
	elapsed += delta
	error_flash = maxf(error_flash - delta, 0.0)
	key_pulse = maxf(key_pulse - delta, 0.0)
	player_recoil = maxf(player_recoil - delta, 0.0)
	shake_time = maxf(shake_time - delta, 0.0)

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_enemy()
		spawn_timer = spawn_interval
		spawn_interval = maxf(0.28, 0.72 - elapsed * 0.003)

	_update_enemies(delta)
	_update_bullets(delta)
	_process_pending_reactions()
	_update_particles(delta)
	_update_damage_numbers(delta)
	_update_stats()
	_update_canvas_shake()
	_update_typing_caret(delta)
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if event.unicode == 0:
		return

	var typed := char(event.unicode).to_lower()
	if typed.length() != 1 or typed < "a" or typed > "z":
		return

	typed_characters += 1
	caret_idle_time = 0.0

	var current := word_queue[0]
	var expected := current.substr(typed_index, 1)
	var snap_caret := false

	if typed == expected:
		correct_keys += 1
		typed_index += 1
		streak += 1
		best_streak = maxi(best_streak, streak)
		key_pulse = 0.08
		player_recoil = 0.07

		_emit_combat_trigger("correct_key", {
			"character": typed,
			"word": current,
			"word_length": current.length(),
			"streak": streak
		})

		if typed_index >= current.length():
			_complete_word(current)
			snap_caret = true
	else:
		incorrect_keys += 1
		streak = 0
		error_flash = 0.16

	_update_typing_ui(snap_caret)


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


func _complete_word(completed_word: String) -> void:
	words_completed += 1
	typed_index = 0
	word_queue.pop_front()
	_append_random_word()
	shake_time = 0.07
	shake_strength = 2.0

	_emit_combat_trigger("word_complete", {
		"word": completed_word,
		"word_length": completed_word.length(),
		"streak": streak
	})


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
	var speed := rng.randf_range(34.0, 58.0) + minf(elapsed * 0.22, 28.0)
	var hp_value := 24.0 + minf(elapsed * 0.12, 16.0)

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
			_spawn_damage_number(pos, int(round(status_damage)), Color(1.0, 0.48, 0.30))

		if float(enemy["hp"]) <= 0.0:
			_kill_enemy(i, pos)
			continue

		var to_player := center - pos
		var distance := to_player.length()
		var speed_multiplier := _get_enemy_speed_multiplier(enemy)

		enemy["flash"] = maxf(float(enemy["flash"]) - delta, 0.0)
		pos += knockback * delta
		enemy["knockback"] = knockback.move_toward(Vector2.ZERO, 650.0 * delta)

		if distance > DANGER_RADIUS:
			pos += to_player.normalized() * float(enemy["speed"]) * speed_multiplier * delta
			enemy["position"] = pos
			enemies[i] = enemy
		else:
			hp = maxf(0.0, hp - 10.0)
			_spawn_impact_particles(pos, Color(1.0, 0.28, 0.34), 7)
			enemies.remove_at(i)


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
			state["tick_timer"] = float(state.get("tick_timer", tick_interval)) - delta
			while float(state["tick_timer"]) <= 0.0 and float(state["remaining"]) > 0.0:
				var stacks := int(state.get("stacks", 1))
				total_tick_damage += float(definition.get("tick_damage", 0.0)) * stacks
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
		multiplier *= float(definition.get("speed_multiplier", 1.0))

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
			if Vector2(bullet["position"]).distance_squared_to(enemy_pos) <= pow(ENEMY_RADIUS + BULLET_RADIUS, 2):
				var enemy := enemies[enemy_index]
				var damage := float(bullet["damage"])
				enemy["hp"] = float(enemy["hp"]) - damage
				enemy["flash"] = 0.075

				var push_direction := (enemy_pos - get_viewport_rect().size * 0.5).normalized()
				enemy["knockback"] = Vector2(enemy["knockback"]) + push_direction * 92.0

				_spawn_impact_particles(enemy_pos, Color(1.0, 0.82, 0.42), 3)
				_spawn_damage_number(enemy_pos, int(round(damage)))
				_apply_attack_effects(enemy, bullet.get("effects", []))
				_queue_matching_reactions(enemy, bullet.get("tags", []), enemy_pos)

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
		var stacks := mini(int(existing.get("stacks", 0)) + 1, max_stacks)

		statuses[effect_id] = {
			"remaining": duration,
			"stacks": stacks,
			"tick_timer": float(definition.get("tick_interval", 0.0))
		}

	enemy["statuses"] = statuses


func _queue_matching_reactions(enemy: Dictionary, incoming_tags: Array, position: Vector2) -> void:
	var statuses: Dictionary = enemy.get("statuses", {})
	var matches := combat.resolve_reactions(statuses, incoming_tags)

	for reaction in matches:
		combat.consume_reaction_effects(statuses, reaction)
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
		var radius := float(reaction.get("area_radius", 0.0))
		var damage := float(reaction.get("area_damage", 0.0))
		var reaction_color := Color.from_string(
			String(reaction.get("color", "#ffffff")),
			Color.WHITE
		)

		_spawn_impact_particles(center, reaction_color, 16)
		_spawn_combat_text(center + Vector2(0.0, -22.0), String(reaction.get("name", "REACTION")), reaction_color)

		for i in range(enemies.size() - 1, -1, -1):
			var enemy_pos: Vector2 = enemies[i]["position"]
			if center.distance_squared_to(enemy_pos) > radius * radius:
				continue

			var enemy := enemies[i]
			enemy["hp"] = float(enemy["hp"]) - damage
			enemy["flash"] = 0.10
			var push := (enemy_pos - center).normalized()
			enemy["knockback"] = Vector2(enemy["knockback"]) + push * 145.0
			_spawn_damage_number(enemy_pos, int(round(damage)), reaction_color)

			if float(enemy["hp"]) <= 0.0:
				_kill_enemy(i, enemy_pos)
			else:
				enemies[i] = enemy


func _kill_enemy(index: int, position: Vector2) -> void:
	if index < 0 or index >= enemies.size():
		return

	enemies.remove_at(index)
	kills += 1
	xp += 1
	_spawn_death_particles(position)
	_spawn_xp_particles(position)


func _spawn_impact_particles(position: Vector2, color: Color, amount: int) -> void:
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
	_spawn_impact_particles(position, Color(1.0, 0.30, 0.38), 9)


func _spawn_xp_particles(position: Vector2) -> void:
	for i in range(3):
		particles.append({
			"position": position + Vector2(rng.randf_range(-5.0, 5.0), rng.randf_range(-5.0, 5.0)),
			"velocity": Vector2.ZERO,
			"life": 0.55 + i * 0.05,
			"max_life": 0.65,
			"color": Color(0.42, 0.95, 0.72),
			"size": 2.5,
			"kind": "xp"
		})


func _update_particles(delta: float) -> void:
	var center := get_viewport_rect().size * 0.5

	for i in range(particles.size() - 1, -1, -1):
		var particle := particles[i]
		particle["life"] = float(particle["life"]) - delta

		if particle["kind"] == "xp":
			var pos: Vector2 = particle["position"]
			var direction := (center - pos).normalized()
			particle["velocity"] = Vector2(particle["velocity"]).move_toward(direction * 520.0, 900.0 * delta)

		particle["position"] = Vector2(particle["position"]) + Vector2(particle["velocity"]) * delta
		particle["velocity"] = Vector2(particle["velocity"]) * pow(0.08, delta)

		if float(particle["life"]) <= 0.0:
			particles.remove_at(i)
		else:
			particles[i] = particle


func _spawn_damage_number(position: Vector2, amount: int, color: Color = Color(1.0, 0.91, 0.62)) -> void:
	damage_numbers.append({
		"position": position + Vector2(0.0, -14.0),
		"text": str(amount),
		"life": 0.42,
		"max_life": 0.42,
		"color": color,
		"font_size": 13
	})


func _spawn_combat_text(position: Vector2, value: String, color: Color) -> void:
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
		number["life"] = float(number["life"]) - delta
		number["position"] = Vector2(number["position"]) + Vector2(0.0, -24.0) * delta

		if float(number["life"]) <= 0.0:
			damage_numbers.remove_at(i)
		else:
			damage_numbers[i] = number


func _update_typing_ui(snap_caret: bool = false) -> void:
	if word_queue.is_empty():
		return

	# The caret is not part of this text. That keeps every glyph stationary.
	var pieces: Array[String] = []
	pieces.append("[color=#ffffff]" + word_queue[0] + "[/color]")

	for i in range(1, mini(word_queue.size(), 6)):
		pieces.append("[color=#697180]" + word_queue[i] + "[/color]")

	typing_panel.text = "[center]" + " ".join(pieces) + "[/center]"
	_update_caret_target(snap_caret)


func _update_caret_target(snap: bool = false) -> void:
	if word_queue.is_empty():
		return

	var font := typing_panel.get_theme_font("normal_font")
	var font_size := typing_panel.get_theme_font_size("normal_font_size")
	var visible_words: Array[String] = []

	for i in range(mini(word_queue.size(), 6)):
		visible_words.append(word_queue[i])

	var plain_line := " ".join(visible_words)
	var completed := word_queue[0].substr(0, typed_index)
	var total_width := font.get_string_size(
		plain_line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
	).x
	var completed_width := font.get_string_size(
		completed, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
	).x

	var line_left := typing_panel.position.x + (typing_panel.size.x - total_width) * 0.5
	caret_target_x = line_left + completed_width - typing_caret.size.x * 0.5

	if snap or not caret_initialized:
		caret_visual_x = caret_target_x
		caret_initialized = true
		typing_caret.position.x = caret_visual_x


func _update_typing_caret(delta: float) -> void:
	if not caret_initialized:
		return

	caret_idle_time += delta
	var follow := 1.0 - exp(-35.0 * delta)
	caret_visual_x = lerpf(caret_visual_x, caret_target_x, follow)
	typing_caret.position.x = caret_visual_x
	typing_caret.position.y = typing_panel.position.y + 4.0

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


func _update_stats() -> void:
	var minutes := maxf(elapsed / 60.0, 0.0167)
	var wpm := int(round((correct_keys / 5.0) / minutes))
	var total_attempts := correct_keys + incorrect_keys
	var accuracy := 100.0

	if total_attempts > 0:
		accuracy = (float(correct_keys) / float(total_attempts)) * 100.0

	stats_label.text = "HP %d/%d   KILLS %d   XP %d   WPM %d   ACC %.1f%%   STREAK %d" % [
		int(hp),
		int(MAX_HP),
		kills,
		xp,
		wpm,
		accuracy,
		streak
	]


func _update_canvas_shake() -> void:
	if shake_time > 0.0:
		position = Vector2(
			rng.randf_range(-shake_strength, shake_strength),
			rng.randf_range(-shake_strength, shake_strength)
		)
	else:
		position = Vector2.ZERO


func _draw() -> void:
	var center := get_viewport_rect().size * 0.5

	var player_size := PLAYER_RADIUS + (2.0 if player_recoil > 0.0 else 0.0)
	draw_circle(center, player_size, Color(0.40, 0.90, 0.72))
	draw_circle(center, 5.0, Color(0.93, 1.0, 0.97))
	draw_arc(center, DANGER_RADIUS, 0.0, TAU, 64, Color(0.35, 0.39, 0.48, 0.35), 1.0)

	for enemy in enemies:
		var pos: Vector2 = enemy["position"]
		var enemy_color := _get_enemy_draw_color(enemy)
		if float(enemy["flash"]) > 0.0:
			enemy_color = enemy_color.lerp(Color.WHITE, 0.72)
		draw_circle(pos, ENEMY_RADIUS, enemy_color)

	for bullet in bullets:
		var pos: Vector2 = bullet["position"]
		var direction := Vector2(bullet["velocity"]).normalized()
		var bullet_color: Color = bullet.get("color", Color(1.0, 0.90, 0.50))
		draw_line(pos - direction * 7.0, pos, bullet_color, 3.0)
		draw_circle(pos, BULLET_RADIUS, bullet_color.lightened(0.18))

	for particle in particles:
		var life_ratio := clampf(float(particle["life"]) / float(particle["max_life"]), 0.0, 1.0)
		var color: Color = particle["color"]
		color.a = life_ratio
		draw_circle(Vector2(particle["position"]), float(particle["size"]), color)

	var default_font := ThemeDB.fallback_font
	for number in damage_numbers:
		var max_life := float(number.get("max_life", 0.42))
		var color: Color = number.get("color", Color(1.0, 0.91, 0.62))
		color.a = clampf(float(number["life"]) / max_life, 0.0, 1.0)
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
	var statuses: Dictionary = enemy.get("statuses", {})

	if statuses.has("freeze"):
		return Color(0.48, 0.86, 1.0)
	if statuses.has("shock"):
		return Color(0.67, 0.56, 1.0)
	if statuses.has("burn"):
		return Color(1.0, 0.45, 0.28)

	return Color(0.95, 0.33, 0.38)
