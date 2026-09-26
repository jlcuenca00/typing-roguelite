class_name CombatSystem
extends RefCounted

const WEAPONS_PATH := "res://data/combat/weapons.json"
const EFFECTS_PATH := "res://data/combat/effects.json"
const REACTIONS_PATH := "res://data/combat/reactions.json"
const LOADOUTS_PATH := "res://data/combat/loadouts.json"

var weapons: Dictionary = {}
var effects: Dictionary = {}
var reactions: Array = []
var loadouts: Dictionary = {}

var active_weapon_ids: Array[String] = []
var effect_bindings: Dictionary = {}
var weapon_modifiers: Dictionary = {}
var global_damage_multiplier := 1.0
var reaction_damage_multiplier := 1.0


func load_definitions(loadout_id: String = "starter") -> bool:
	weapons = _load_json_dictionary(WEAPONS_PATH)
	effects = _load_json_dictionary(EFFECTS_PATH)
	var reaction_data := _load_json_dictionary(REACTIONS_PATH)
	loadouts = _load_json_dictionary(LOADOUTS_PATH)

	reactions = reaction_data.get("reactions", [])
	if weapons.is_empty() or loadouts.is_empty():
		push_error("CombatSystem: missing weapon or loadout definitions.")
		return false

	return equip_loadout(loadout_id)


func equip_loadout(loadout_id: String) -> bool:
	if not loadouts.has(loadout_id):
		push_error("CombatSystem: unknown loadout '%s'." % loadout_id)
		return false

	var loadout: Dictionary = loadouts[loadout_id]
	active_weapon_ids.clear()
	weapon_modifiers.clear()
	global_damage_multiplier = 1.0
	reaction_damage_multiplier = 1.0

	for weapon_id in loadout.get("weapons", []):
		if weapons.has(weapon_id):
			active_weapon_ids.append(String(weapon_id))
		else:
			push_warning("CombatSystem: loadout references missing weapon '%s'." % weapon_id)

	effect_bindings = loadout.get("effect_bindings", {}).duplicate(true)
	return true


func build_attacks(trigger_id: String, context: Dictionary = {}) -> Array[Dictionary]:
	var attacks: Array[Dictionary] = []

	for weapon_id in active_weapon_ids:
		if not weapons.has(weapon_id):
			continue

		var weapon: Dictionary = weapons[weapon_id]
		if String(weapon.get("trigger", "")) != trigger_id:
			continue

		var attack := weapon.duplicate(true)
		_apply_weapon_modifiers(attack, weapon_id)

		attack["damage"] = float(attack.get("damage", 1.0)) * global_damage_multiplier
		attack["weapon_id"] = weapon_id
		attack["trigger"] = trigger_id
		attack["context"] = context.duplicate(true)
		attack["effects"] = effect_bindings.get(weapon_id, []).duplicate(true)
		attacks.append(attack)

	return attacks


func is_weapon_active(weapon_id: String) -> bool:
	return active_weapon_ids.has(weapon_id)


func unlock_weapon(weapon_id: String) -> bool:
	if not weapons.has(weapon_id):
		return false
	if active_weapon_ids.has(weapon_id):
		return false

	active_weapon_ids.append(weapon_id)
	return true


func multiply_weapon_stat(weapon_id: String, stat: String, factor: float) -> void:
	var modifiers: Dictionary = weapon_modifiers.get(weapon_id, {})
	var multipliers: Dictionary = modifiers.get("multipliers", {})
	multipliers[stat] = float(multipliers.get(stat, 1.0)) * factor
	modifiers["multipliers"] = multipliers
	weapon_modifiers[weapon_id] = modifiers


func add_weapon_stat(weapon_id: String, stat: String, amount: float) -> void:
	var modifiers: Dictionary = weapon_modifiers.get(weapon_id, {})
	var additions: Dictionary = modifiers.get("additions", {})
	additions[stat] = float(additions.get(stat, 0.0)) + amount
	modifiers["additions"] = additions
	weapon_modifiers[weapon_id] = modifiers


func multiply_global_damage(factor: float) -> void:
	global_damage_multiplier *= factor


func multiply_reaction_damage(factor: float) -> void:
	reaction_damage_multiplier *= factor


func add_or_increase_effect_binding(weapon_id: String, effect_id: String, chance_delta: float) -> void:
	var bindings: Array = effect_bindings.get(weapon_id, []).duplicate(true)

	for i in range(bindings.size()):
		var binding: Dictionary = bindings[i]
		if String(binding.get("effect_id", "")) == effect_id:
			binding["chance"] = clampf(float(binding.get("chance", 0.0)) + chance_delta, 0.0, 1.0)
			bindings[i] = binding
			effect_bindings[weapon_id] = bindings
			return

	bindings.append({
		"effect_id": effect_id,
		"chance": clampf(chance_delta, 0.0, 1.0)
	})
	effect_bindings[weapon_id] = bindings


func get_effect_binding_chance(weapon_id: String, effect_id: String) -> float:
	for raw_binding in effect_bindings.get(weapon_id, []):
		var binding: Dictionary = raw_binding
		if String(binding.get("effect_id", "")) == effect_id:
			return float(binding.get("chance", 0.0))
	return 0.0


func get_effect_definition(effect_id: String) -> Dictionary:
	if not effects.has(effect_id):
		return {}
	var definition: Dictionary = effects[effect_id]
	return definition.duplicate(true)


func resolve_reactions(active_effects: Dictionary, incoming_tags: Array) -> Array[Dictionary]:
	var resolved: Array[Dictionary] = []

	for raw_reaction in reactions:
		var reaction: Dictionary = raw_reaction
		var required_effects: Array = reaction.get("requires_effects", [])
		var required_tags: Array = reaction.get("requires_tags", [])

		if not _dictionary_has_all(active_effects, required_effects):
			continue
		if not _array_has_all(incoming_tags, required_tags):
			continue

		var resolved_reaction := reaction.duplicate(true)
		resolved_reaction["area_damage"] = float(resolved_reaction.get("area_damage", 0.0)) * reaction_damage_multiplier
		resolved.append(resolved_reaction)

	return resolved


func consume_reaction_effects(active_effects: Dictionary, reaction: Dictionary) -> void:
	for effect_id in reaction.get("consume_effects", []):
		active_effects.erase(String(effect_id))


func _apply_weapon_modifiers(attack: Dictionary, weapon_id: String) -> void:
	var modifiers: Dictionary = weapon_modifiers.get(weapon_id, {})
	var multipliers: Dictionary = modifiers.get("multipliers", {})
	var additions: Dictionary = modifiers.get("additions", {})

	for stat in multipliers.keys():
		if attack.has(stat):
			attack[stat] = float(attack[stat]) * float(multipliers[stat])

	for stat in additions.keys():
		if attack.has(stat):
			if attack[stat] is int:
				attack[stat] = int(attack[stat]) + int(round(float(additions[stat])))
			else:
				attack[stat] = float(attack[stat]) + float(additions[stat])


func _dictionary_has_all(source: Dictionary, required: Array) -> bool:
	for item in required:
		if not source.has(String(item)):
			return false
	return true


func _array_has_all(source: Array, required: Array) -> bool:
	for item in required:
		if not source.has(item):
			return false
	return true


func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("CombatSystem: file not found: %s" % path)
		return {}

	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_error("CombatSystem: invalid JSON dictionary: %s" % path)
		return {}

	return parsed
