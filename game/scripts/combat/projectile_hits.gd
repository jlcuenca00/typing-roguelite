extends RefCounted


static func find_hits(
	start: Vector2, finish: Vector2, bullet: Dictionary, enemies: Array
) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var motion := finish - start
	var length_squared := motion.length_squared()
	var hit_uids: Array = bullet.get("hit_uids", [])
	var intended_uid := int(bullet.get("target_uid", -1))
	var strict := bool(bullet.get("strict_target", false)) and hit_uids.is_empty()
	# A target may die while earlier shots are still in flight.
	var target_exists := false
	for enemy in enemies:
		if int(enemy.get("uid", -1)) == intended_uid:
			target_exists = not bool(enemy.get("priority", false))
			break
	strict = strict and target_exists
	for enemy in enemies:
		var uid := int(enemy.get("uid", -1))
		if bool(enemy.get("priority", false)) or hit_uids.has(uid):
			continue
		if strict and uid != intended_uid:
			continue
		var offset := start - Vector2(enemy["position"])
		var radius := float(enemy.get("radius", 10.0)) + 3.0
		var c := offset.length_squared() - radius * radius
		var time := 0.0
		if c > 0.0:
			if length_squared <= 0.000001:
				continue
			var b := offset.dot(motion)
			var discriminant := b * b - length_squared * c
			if discriminant < 0.0:
				continue
			time = (-b - sqrt(discriminant)) / length_squared
			if time < 0.0 or time > 1.0:
				continue
		hits.append({"uid": uid, "time": time})
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["time"]) < float(b["time"])
	)
	return hits
