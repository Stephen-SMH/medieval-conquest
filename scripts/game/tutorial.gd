class_name Tutorial
extends RefCounted
## The guided tutorial mission, as S&T's: the north of England, England
## against the Danes in Doncaster (data/tutorial/), and nine steps, each
## teaching one thing and waiting until the player has done it (or, for a
## step that only explains, until they press Next): select an army, its
## panel, march, the hourglass, resting, the order ring, an attack with
## supports, carrying it out, and the surrounded enemy destroyed.
## The game scene shows the current step in a parchment box (TutorialBox) and
## reports what the player does with record().

const SCENARIO := "res://data/tutorial/tutorial.json"
const PLAYER := "england"

## Each step: an id (what finishes it, see is_done), a title and the hint;
## "info" for a step that only explains.
const STEPS := [
	{"id": "select", "title": "Select an army",
		"text": "Welcome to the tutorial mission. Your troops fly England's banner, gold lions on red; the Danes' banners are pale. To select troops, click the region they stand in: click [b]York[/b]."},
	{"id": "panel", "info": true, "title": "The army's soldiers",
		"text": "The banner on the right lists the soldiers of the selected army, one icon for each type and how many there are. Click an icon to see its name."},
	{"id": "move", "title": "March",
		"text": "Now give an order. Select the troops in [b]Cumbria[/b] and click [b]Lancaster[/b]. Choose how many go and press the check mark: a blue arrow shows the order."},
	{"id": "hourglass", "title": "Carry out the order",
		"text": "Click the [b]hourglass[/b] to carry out your orders. Then the enemy takes its turn."},
	{"id": "rest", "info": true, "title": "Rest",
		"text": "An army that does nothing for a turn gets back part of its strength: watch the bar under it. Tired armies fight worse."},
	{"id": "ring", "info": true, "title": "Kinds of order",
		"text": "Click a region next to the enemy and a ring of orders opens: the [b]X[/b] cancels, [b]crossed swords[/b] attack, and [b]crossed swords with a plus[/b] support another army's attack without moving in."},
	{"id": "support", "title": "Attack and support",
		"text": "Order the troops in [b]Stamford Bridge[/b] to attack [b]Doncaster[/b], and the troops in [b]York[/b], [b]Lancaster[/b] and [b]Lincoln[/b] to support the attack."},
	{"id": "carry", "title": "Attack!",
		"text": "Now carry out the orders you have given: click the [b]hourglass[/b]."},
	{"id": "finish", "title": "Victory",
		"text": "Surrounded troops have nowhere to retreat if they lose, and are destroyed. You won!"},
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
			return _has_order(state, func(order): return order.steps.any(func(s): return s.type == "move"))
		"hourglass":
			return state.turn > start_turn
		"support":
			return _has_order(state, func(order): return order.get("support", false) and order.steps.back().target == "doncaster") \
				and _has_order(state, func(order): return not order.get("support", false) and order.steps.back().type == "attack")
		"carry":
			return state.turn > start_turn + 1 or state.is_over()
	return false  # A step that only explains waits for Next; "finish" for the player to close it.


## Some order of the player's passes `test(order)`.
func _has_order(state: GameState, test: Callable) -> bool:
	for unit: Unit in state.orders:
		for order in state.orders[unit]:
			if unit.owner == PLAYER and test.call(order):
				return true
	return false


func _index(id: String) -> int:
	for i in STEPS.size():
		if STEPS[i].id == id:
			return i
	return -1
