extends RefCounted
## Builds small games on the Heartlands map for tests.
## Regions: northmarch, greywater, highcrag, eastwold, ashford, kingsvale,
## thornwood, saltmere, redfield, stonehelm.


## A two-faction game: "blue" (human) and "red" (AI). `owners` maps regions to
## factions (others are neutral); `units` is a list of [owner, region, type]
## or [owner, region, type, soldiers].
static func game(owners: Dictionary, units: Array, game_seed := 7, extra := {}) -> GameState:
	var scenario := {
		"id": "test", "map": "heartlands",
		"factions": [
			{"id": "blue", "name": "Blue", "color": "#3d6fb6", "human": true, "civ": extra.get("blue_civ", "")},
			{"id": "red", "name": "Red", "color": "#b5423a", "human": false, "civ": extra.get("red_civ", "")},
		],
		"owners": owners,
		"capitals": extra.get("capitals", {}),
		"buildings": extra.get("buildings", {}),
		"units": [],
		"resources": extra.get("resources", {}),
	}
	for entry in units:
		var unit := {"owner": entry[0], "region": entry[1], "type": entry[2]}
		if entry.size() > 3:
			unit["soldiers"] = entry[3]
		scenario.units.append(unit)
	return GameState.from_scenario(scenario, game_seed)


static func units_of_type(state: GameState, type_id: String) -> Array:
	return state.units.filter(func(u: Unit): return u.type_id == type_id)
