extends Node2D

const PLAYER_RADIUS := 14.0
const ENEMY_RADIUS := 10.0
const BULLET_RADIUS := 3.0
const SPAWN_RADIUS := 430.0
const DANGER_RADIUS := 42.0

var rng := RandomNumberGenerator.new()

var word_pool: Array[String] = []
var word_queue: Array[String] = []
var typed_index := 0

var enemies: Array[Dictionary] = []
var bullets: Array[Dictionary] = []

var spawn_timer := 0.0
var spawn_interval := 0.72
var elapsed := 0.0
var error_flash := 0.0

var kills := 0
var xp := 0
var words_completed := 0
var streak := 0
var best_streak := 0
var damage_taken := 0

@onready var typing_panel: RichTextLabel = $HUD/TypingPanel
@onready var stats_label: Label = $HUD/Stats


func _ready() -> void:
	rng.randomize()
	_load_words()
	for i in range(6):
		_append_random_word()
	_update_typing_ui()
	_update_stats()
	queue_redraw()


func _process(delta: float) -> void:
	elapsed += delta
	error_flash = maxf(error_flash - delta, 0.0)

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_enemy()
		spawn_timer = spawn_interval
		spawn_interval = maxf(0.28, 0.72 - elapsed * 0.003)

	_update_enemies(delta)
	_update_bullets(delta)
	_update_stats()
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return

	if event.unicode == 0:
		return

	var typed := char(event.unicode).to_lower()
	if typed.length() != 1 or typed < "a" or typed > "z":
		return

	var current := word_queue[0]
	var expected := current.substr(typed_index, 1)

	if typed == expected:
		typed_index += 1
		streak += 1
		best_streak = maxi(best_streak, streak)
		_fire_at_nearest_enemy(8.0)

		if typed_index >= current.length():
			_complete_word()
	else:
		streak = 0
		error_flash = 0.16

	_update_typing_ui()


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

	# Word completion is deliberately much stronger than a normal keystroke.
	for i in range(4):
		_fire_at_nearest_enemy(13.0)


func _spawn_enemy() -> void:
	var center := get_viewport_rect().size * 0.5
	var angle := rng.randf_range(0.0, TAU)
	var position := center + Vector2.RIGHT.rotated(angle) * SPAWN_RADIUS
	var speed := rng.randf_range(34.0, 58.0) + minf(elapsed * 0.22, 28.0)
	var hp := 20.0 + minf(elapsed * 0.12, 16.0)

	enemies.append({
		"position": position,
		"speed": speed,
		"hp": hp,
		"max_hp": hp
	})


func _update_enemies(delta: float) -> void:
	var center := get_viewport_rect().size * 0.5

	for i in range(enemies.size() - 1, -1, -1):
		var enemy := enemies[i]
		var pos: Vector2 = enemy["position"]
		var to_player := center - pos
		var distance := to_player.length()

		if distance > DANGER_RADIUS:
			pos += to_player.normalized() * float(enemy["speed"]) * delta
			enemy["position"] = pos
			enemies[i] = enemy
		else:
			# Prototype contact pressure: reaching the center counts as a hit
			# and the enemy is removed so the loop never hard-locks.
			damage_taken += 1
			enemies.remove_at(i)


func _fire_at_nearest_enemy(damage: float) -> void:
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
	var direction := (target - center).normalized()

	bullets.append({
		"position": center,
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
				enemy["hp"] = float(enemy["hp"]) - float(bullet["damage"])

				if float(enemy["hp"]) <= 0.0:
					enemies.remove_at(enemy_index)
					kills += 1
					xp += 1
				else:
					enemies[enemy_index] = enemy

				hit = true
				break

		if hit or float(bullet["life"]) <= 0.0:
			bullets.remove_at(bullet_index)
		else:
			bullets[bullet_index] = bullet


func _update_typing_ui() -> void:
	if word_queue.is_empty():
		return

	var current := word_queue[0]
	var completed := current.substr(0, typed_index)
	var remaining := current.substr(typed_index)

	var pieces: Array[String] = []
	pieces.append("[color=#65e6a6]" + completed + "[/color][color=#ffffff]" + remaining + "[/color]")

	for i in range(1, mini(word_queue.size(), 6)):
		pieces.append("[color=#707786]" + word_queue[i] + "[/color]")

	var prefix := ""
	if error_flash > 0.0:
		prefix = "[color=#ff5f6d]×[/color] "

	typing_panel.text = "[center]" + prefix + " ".join(pieces) + "[/center]"


func _update_stats() -> void:
	stats_label.text = "KILLS %d   XP %d   WORDS %d   STREAK %d   BEST %d   HITS TAKEN %d" % [
		kills,
		xp,
		words_completed,
		streak,
		best_streak,
		damage_taken
	]


func _draw() -> void:
	var center := get_viewport_rect().size * 0.5

	# Player.
	draw_circle(center, PLAYER_RADIUS, Color(0.40, 0.90, 0.72))
	draw_circle(center, 5.0, Color(0.93, 1.0, 0.97))

	# Danger ring.
	draw_arc(center, DANGER_RADIUS, 0.0, TAU, 64, Color(0.35, 0.39, 0.48, 0.45), 1.0)

	for enemy in enemies:
		var pos: Vector2 = enemy["position"]
		var health_ratio := float(enemy["hp"]) / float(enemy["max_hp"])
		draw_circle(pos, ENEMY_RADIUS, Color(0.95, 0.33, 0.38))
		draw_rect(Rect2(pos + Vector2(-10, -17), Vector2(20, 3)), Color(0.15, 0.16, 0.20))
		draw_rect(Rect2(pos + Vector2(-10, -17), Vector2(20.0 * health_ratio, 3)), Color(0.75, 0.95, 0.45))

	for bullet in bullets:
		draw_circle(Vector2(bullet["position"]), BULLET_RADIUS, Color(1.0, 0.90, 0.50))
