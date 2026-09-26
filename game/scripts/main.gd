extends Node2D

const PLAYER_RADIUS := 14.0
const ENEMY_RADIUS := 10.0
const BULLET_RADIUS := 3.0
const SPAWN_RADIUS := 430.0
const DANGER_RADIUS := 42.0
const MAX_HP := 100.0

var rng := RandomNumberGenerator.new()

var word_pool: Array[String] = []
var word_queue: Array[String] = []
var typed_index := 0

var enemies: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var damage_numbers: Array[Dictionary] = []

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
		_fire_at_nearest_enemy(8.0, 0.0)

		if typed_index >= current.length():
			_complete_word()
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


func _complete_word() -> void:
	words_completed += 1
	typed_index = 0
	word_queue.pop_front()
	_append_random_word()
	shake_time = 0.08
	shake_strength = 2.5

	# Prototype word burst. This becomes a real weapon system next.
	for i in range(4):
		_fire_at_nearest_enemy(13.0, rng.randf_range(-0.055, 0.055))


func _spawn_enemy() -> void:
	var center := get_viewport_rect().size * 0.5
	var angle := rng.randf_range(0.0, TAU)
	var position := center + Vector2.RIGHT.rotated(angle) * SPAWN_RADIUS
	var speed := rng.randf_range(34.0, 58.0) + minf(elapsed * 0.22, 28.0)
	var hp_value := 20.0 + minf(elapsed * 0.12, 16.0)

	enemies.append({
		"position": position,
		"speed": speed,
		"hp": hp_value,
		"max_hp": hp_value,
		"flash": 0.0,
		"knockback": Vector2.ZERO
	})


func _update_enemies(delta: float) -> void:
	var center := get_viewport_rect().size * 0.5

	for i in range(enemies.size() - 1, -1, -1):
		var enemy := enemies[i]
		var pos: Vector2 = enemy["position"]
		var knockback: Vector2 = enemy["knockback"]
		var to_player := center - pos
		var distance := to_player.length()

		enemy["flash"] = maxf(float(enemy["flash"]) - delta, 0.0)
		pos += knockback * delta
		enemy["knockback"] = knockback.move_toward(Vector2.ZERO, 650.0 * delta)

		if distance > DANGER_RADIUS:
			pos += to_player.normalized() * float(enemy["speed"]) * delta
			enemy["position"] = pos
			enemies[i] = enemy
		else:
			hp = maxf(0.0, hp - 10.0)
			_spawn_impact_particles(pos, Color(1.0, 0.28, 0.34), 7)
			enemies.remove_at(i)


func _fire_at_nearest_enemy(damage: float, spread: float) -> void:
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
		"velocity": direction * 720.0,
		"damage": damage,
		"life": 1.1
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

				if float(enemy["hp"]) <= 0.0:
					var death_pos: Vector2 = enemy["position"]
					enemies.remove_at(enemy_index)
					kills += 1
					xp += 1
					_spawn_death_particles(death_pos)
					_spawn_xp_particles(death_pos)
				else:
					enemies[enemy_index] = enemy

				hit = true
				break

		if hit or float(bullet["life"]) <= 0.0:
			bullets.remove_at(bullet_index)
		else:
			bullets[bullet_index] = bullet


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


func _spawn_damage_number(position: Vector2, amount: int) -> void:
	damage_numbers.append({
		"position": position + Vector2(0.0, -14.0),
		"text": str(amount),
		"life": 0.42
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

	# Do not insert a "|" character into the line. The displayed text remains
	# pixel-identical while typing; only the overlay caret moves.
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

	# Roughly Monkeytype's "fast" feel: settle over a few frames rather than
	# teleporting, while the underlying letters never move.
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
		int(hp), int(MAX_HP), kills, xp, wpm, accuracy, streak
	]


func _update_canvas_shake() -> void:
	if shake_time > 0.0:
		position = Vector2(rng.randf_range(-shake_strength, shake_strength), rng.randf_range(-shake_strength, shake_strength))
	else:
		position = Vector2.ZERO


func _draw() -> void:
	var center := get_viewport_rect().size * 0.5

	# Player reacts subtly to correct typing.
	var player_size := PLAYER_RADIUS + (2.0 if player_recoil > 0.0 else 0.0)
	draw_circle(center, player_size, Color(0.40, 0.90, 0.72))
	draw_circle(center, 5.0, Color(0.93, 1.0, 0.97))
	draw_arc(center, DANGER_RADIUS, 0.0, TAU, 64, Color(0.35, 0.39, 0.48, 0.35), 1.0)

	for enemy in enemies:
		var pos: Vector2 = enemy["position"]
		var color := Color(1.0, 0.92, 0.78) if float(enemy["flash"]) > 0.0 else Color(0.95, 0.33, 0.38)
		draw_circle(pos, ENEMY_RADIUS, color)

	for bullet in bullets:
		var pos: Vector2 = bullet["position"]
		var direction := Vector2(bullet["velocity"]).normalized()
		draw_line(pos - direction * 7.0, pos, Color(1.0, 0.90, 0.50), 3.0)
		draw_circle(pos, BULLET_RADIUS, Color(1.0, 0.95, 0.70))

	for particle in particles:
		var life_ratio := clampf(float(particle["life"]) / float(particle["max_life"]), 0.0, 1.0)
		var color: Color = particle["color"]
		color.a = life_ratio
		draw_circle(Vector2(particle["position"]), float(particle["size"]), color)

	var default_font := ThemeDB.fallback_font
	for number in damage_numbers:
		var color := Color(1.0, 0.91, 0.62, clampf(float(number["life"]) / 0.42, 0.0, 1.0))
		draw_string(default_font, Vector2(number["position"]), String(number["text"]), HORIZONTAL_ALIGNMENT_CENTER, -1, 13, color)
