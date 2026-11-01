extends Node
## Autoload "Session": carries what was chosen on the menus (a mission, a
## skirmish, hotseat or a saved game) into the game scene.

const SCENARIO_DIR := "res://data/scenarios"
const DEFAULT_SCENARIO := "heartlands"

## {"scenario": Dictionary, "seed": int} for a new game, or {"save": Dictionary} to load.
var setup := {}
## The last new-game setup, for "Play again".
var last_setup := {}


## The setup to start, falling back to the default scenario (for running the
## game scene directly).
func take_setup() -> Dictionary:
	var chosen := setup
	setup = {}
	if chosen.is_empty():
		chosen = {"scenario": load_scenario(DEFAULT_SCENARIO), "seed": 1}
	if chosen.has("scenario"):
		last_setup = chosen.duplicate(true)
	return chosen


static func load_scenario(id: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(SCENARIO_DIR.path_join(id + ".json")))
	return data if data is Dictionary else {}
