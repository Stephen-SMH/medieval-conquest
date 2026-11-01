class_name Research
extends RefCounted
## Research (PRD 8.7).


## Moves a faction's research on by a turn. Returns events.
static func advance(_state: GameState, _faction: String) -> Array:
	return []


## Picks something to research for a computer faction.
static func choose_for_ai(_state: GameState, _faction: String) -> void:
	pass
