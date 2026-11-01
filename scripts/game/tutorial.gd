class_name Tutorial
extends RefCounted
## The guided tutorial mission: a small map (data/tutorial/) and a list of
## steps, each teaching one thing and waiting until the player has done it:
## select a unit, march, cancel, attack with the split slider, cavalry's two
## steps and the red X, the hourglass, gold income, mercenaries and recruiting.
## The game scene shows the current step in a parchment box (TutorialBox) and
## reports what the player does with record().

const SCENARIO := "res://data/tutorial/tutorial.json"
const PLAYER := "realm"

## Each step: an id (what finishes it, see is_done), a title and the hint.
const STEPS := [
	{"id": "select", "title": "Select a unit",
		"text": "Welcome, commander! Each region holds one unit: a group of soldiers under its banner. Click your [b]spearmen in Millbrook[/b] to select them."},
	{"id": "move", "title": "March",
		"text": "The regions lit [color=#2a4fa0][b]blue[/b][/color] are where they can march. Click [b]Fernridge[/b]: a blue spear-arrow shows the order. Nothing moves until the turn ends."},
	{"id": "cancel", "title": "Cancel an order",
		"text": "Changed your mind? Click the unit again, or its arrow, to [b]cancel[/b] the order. Then send the spearmen to Fernridge again."},
	{"id": "attack", "title": "Attack",
		"text": "Select the [b]swordsmen in Highmoor[/b] and click [b]Ravensford[/b], lit [color=#9b2d20][b]red[/b][/color]: an attack. Drag the [b]slider[/b] to choose how many soldiers to send (the rest stay home), then press the check mark."},
	{"id": "cavalry", "title": "Cavalry: two steps",
		"text": "Horsemen move twice. Select the [b]light cavalry in Eastwatch[/b], click [b]Saltfen[/b], then click a second region to ride on or attack. A unit with no moves left shows a [color=#c0301e][b]red X[/b][/color] by its health bar."},
	{"id": "hourglass", "title": "End the turn",
		"text": "Every unit has its orders. Turn the [b]hourglass[/b] (bottom right, or Enter) to end your turn: every side moves at once and the turn plays out on the map. Click to skip the show."},
	{"id": "treasury", "title": "Gold",
		"text": "Every region you hold pays [b]gold[/b] each turn: the number under its name. Towns and your capital pay more. Press the [b]coin shield[/b] (top left) to see your treasury."},
	{"id": "mercenary", "title": "Mercenaries",
		"text": "[b]Towns[/b] (houses) and [b]camps[/b] (tent) hire mercenaries. Click [b]Millbrook[/b], press [b]Recruit here[/b] and pick a card with a red number: how many are for hire. They arrive at the end of the turn."},
	{"id": "recruit", "title": "Recruit",
		"text": "Your own troops are trained in any empty region you hold. Click [b]Oakhollow[/b], your capital, press [b]Recruit here[/b] and choose a unit. It costs gold and is ready at the end of the turn."},
	{"id": "finish", "title": "Ready for war",
		"text": "That's everything. Take Ravensford if you like, or head for the campaigns. Spears beat horse, horse beats bows, bows beat spears. Good luck!"},
]

var step := 0
## How many times the player has done each thing (main.gd reports them).
var actions := {}
var start_turn := 1


static func scenario() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(SCENARIO))
	return data if data is Dictionary else {}


func _init(first_turn := 1) -> void:
	start_turn = first_turn


func current() -> Dictionary:
	return STEPS[step] if step < STEPS.size() else {}


func finished() -> bool:
	return step >= STEPS.size()


func record(kind: String) -> void:
	actions[kind] = int(actions.get(kind, 0)) + 1


func skip() -> void:
	step = mini(step + 1, STEPS.size())


## Whether the step is the one where the hourglass is taught or later: the
## turn shouldn't end before the orders steps are done (or skipped).
func may_end_turn() -> bool:
	return finished() or step >= _index("hourglass")


## Moves past every step the player has already done. True if the step changed.
func update(state: GameState, selected: Unit) -> bool:
	var before := step
	while not finished() and is_done(STEPS[step].id, state, selected):
		step += 1
	return step != before


## Whether the player has done what a step asks.
func is_done(id: String, state: GameState, selected: Unit) -> bool:
	match id:
		"select":
			return selected != null and selected.owner == PLAYER
		"move":
			return _has_step(state, func(unit, steps): return steps.any(func(s): return s.type == "move"))
		"cancel":
			return int(actions.get("cancel", 0)) > 0 and _has_step(state, func(unit, steps): return steps.any(func(s): return s.type == "move"))
		"attack":
			return _has_step(state, func(unit, steps): return not unit.type().is_cavalry() and steps.any(func(s): return s.type == "attack"))
		"cavalry":
			return _has_step(state, func(unit, steps): return unit.type().is_cavalry() and steps.size() >= 2)
		"hourglass":
			return state.turn > start_turn
		"treasury":
			return int(actions.get("treasury", 0)) > 0
		"mercenary":
			return int(actions.get("hire", 0)) > 0
		"recruit":
			return int(actions.get("recruit", 0)) > 0
	return false  # "finish" waits for the player to close the tutorial.


## Some unit of the player's has orders whose steps pass `test(unit, steps)`.
func _has_step(state: GameState, test: Callable) -> bool:
	for unit: Unit in state.orders:
		if unit.owner == PLAYER and test.call(unit, state.orders[unit].steps):
			return true
	return false


func _index(id: String) -> int:
	for i in STEPS.size():
		if STEPS[i].id == id:
			return i
	return -1
