class_name Tutorial
extends RefCounted
## The guided tutorial mission, as S&T's: the north of England, England
## against the Danes in Doncaster (data/tutorial/), and ten steps, each
## teaching one thing and waiting until the player has done it (or, for a
## step that only explains, until they press Next): select an army, its
## panel, march, the "!" that carries the order out, the hourglass that ends
## the turn, resting, the order ring, an attack with supports, carrying it
## out, and the surrounded enemy destroyed.
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
	{"id": "bang", "title": "Carry out the order",
		"text": "While you have orders to give, the button in the bottom right corner shows a [b]![/b]. Click it to carry out your orders: the troops march at once."},
	{"id": "end", "title": "End the turn",
		"text": "Troops that have marched or fought can't move again this turn. When you are done, click the [b]hourglass[/b] to end your turn. Then the enemy takes its turn."},
	{"id": "rest", "info": true, "title": "Rest",
		"text": "An army that does nothing for a turn gets back part of its strength: watch the bar under it. Tired armies fight worse."},
	{"id": "ring", "info": true, "title": "Kinds of order",
		"text": "Click a region next to the enemy and a ring of orders opens: the [b]X[/b] cancels, [b]crossed swords[/b] attack, and [b]crossed swords with a plus[/b] support another army's attack without moving in."},
	{"id": "support", "title": "Attack and support",
		"text": "Order the troops in [b]Stamford Bridge[/b] to attack [b]Doncaster[/b], and the troops in [b]York[/b], [b]Lancaster[/b] and [b]Lincoln[/b] to support the attack."},
	{"id": "carry", "title": "Attack!",
		"text": "Now carry out the orders you have given: click the [b]![/b]."},
	{"id": "finish", "title": "Victory",
		"text": "Surrounded troops have nowhere to retreat if they lose, and are destroyed. You won!"},
]

var step := 0
## How many times the player has done each thing (main.gd reports them).
var actions := {}
var start_turn := 1
## How many times the orders had been carried out when the last step began.
var _carried_before := 0


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
	_carried_before = int(actions.get("carry_out", 0))


## Whether the "!" has been taught: orders aren't carried out before the
## march step is done (or skipped).
func may_carry_out() -> bool:
	return finished() or step >= _index("bang")


## Whether the hourglass has been taught: the turn shouldn't end before.
func may_end_turn() -> bool:
	return finished() or step >= _index("end")


## Moves past every step the player has already done. True if the step changed.
func update(state: GameState, selected: Unit) -> bool:
	var before := step
	while not finished() and is_done(STEPS[step].id, state, selected):
		step += 1
		_carried_before = int(actions.get("carry_out", 0))
	return step != before


## Whether the player has done what a step asks.
func is_done(id: String, state: GameState, selected: Unit) -> bool:
	match id:
		"select":
			return selected != null and selected.owner == PLAYER
		"move":
			return _has_order(state, func(order): return order.steps.any(func(s): return s.type == "move"))
		"bang":
			return int(actions.get("carry_out", 0)) > 0 or state.turn > start_turn
		"end":
			return state.turn > start_turn
		"support":
			return _has_order(state, func(order): return order.get("support", false) and order.steps.back().target == "doncaster") \
				and _has_order(state, func(order): return not order.get("support", false) and order.steps.back().type == "attack")
		"carry":
			return int(actions.get("carry_out", 0)) > _carried_before or state.turn > start_turn + 1 or state.is_over()
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
