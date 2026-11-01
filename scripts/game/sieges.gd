class_name Sieges
extends RefCounted
## Walls and sieges (PRD 3.10).


## Wall level of a region: 0 none, 1 palisade, 2 stone walls, 3 castle.
static func walls(state: GameState, region: String) -> int:
	return state.provinces[region].level("walls")


static func wall_bonus(_state: GameState, _region: String, _attacking: Array[Unit]) -> float:
	return 0.0
