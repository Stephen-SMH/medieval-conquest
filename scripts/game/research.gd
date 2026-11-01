class_name Research
extends RefCounted
## Research (PRD 8.7).


## Moves a faction's research on by a turn. Returns events.
static func advance(_state: GameState, _faction: String) -> Array:
	return []


## Picks something to research for a computer faction.
static func choose_for_ai(_state: GameState, _faction: String) -> void:
	pass


static func income(_state: GameState, _faction: String, _kind: String) -> float:
	return 1.0


static func supply_range(_state: GameState, _faction: String) -> int:
	return 0


static func starting_xp(_state: GameState, _faction: String) -> int:
	return 0


static func battle(_state: GameState, _unit: Unit) -> void:
	pass
