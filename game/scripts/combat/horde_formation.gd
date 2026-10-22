extends RefCounted


static func entry_positions(
	count: int, viewport_size: Vector2, rng: RandomNumberGenerator, fronts: int = 1
) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if count <= 0:
		return result
	var edge := rng.randi_range(0, 3)
	var front_count := clampi(fronts, 1, mini(2, count))
	var front_size := int(ceil(float(count) / float(front_count)))
	for front in range(front_count):
		var size := mini(front_size, count - result.size())
		var side := (edge + front * 2) % 4
		var horizontal := side == 0 or side == 2
		var width := viewport_size.x if horizontal else viewport_size.y
		var columns := mini(10, maxi(1, int(ceil(sqrt(float(size)) * 1.3))))
		var spacing := 26.0
		var half_span := float(columns - 1) * spacing * 0.5
		var anchor := rng.randf_range(half_span + 24.0, maxf(half_span + 24.0, width - half_span - 24.0))
		for slot in range(size):
			var row := slot / columns
			var column := slot % columns
			var along := anchor + (float(column) - float(columns - 1) * 0.5) * spacing
			along += rng.randf_range(-2.0, 2.0)
			var depth := 28.0 + float(row) * spacing + rng.randf_range(0.0, 3.0)
			match side:
				0: result.append(Vector2(along, -depth))
				1: result.append(Vector2(viewport_size.x + depth, along))
				2: result.append(Vector2(along, viewport_size.y + depth))
				3: result.append(Vector2(-depth, along))
	return result
